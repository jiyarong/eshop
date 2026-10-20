require "test_helper"

class Ec::PalletPlanSyncJobTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    @token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(client_id: "plan-sync-#{@token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Plan sync #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
    user = User.create!(email: "plan-sync-#{@token}@example.com", password: "password123")
    sku = Ec::Sku.create!(sku_code: "PLAN-SYNC-#{@token}")
    product = Ec::SkuProduct.create!(sku: sku, store: @store, product_id: "PRODUCT-#{@token}", platform_sku_id: "1001")
    @plan = Ec::PalletPlan.create!(store: @store, created_by: user, status: "reserved", macrolocal_cluster_id: 761,
      cluster_name: "Москва", from_date: Date.new(2026, 7, 1), to_date: Date.new(2026, 7, 28), target_days: 28, time_zone: "Asia/Shanghai")
    item = @plan.items.create!(sku_code: sku.sku_code, sku_product: product, platform_sku_id: "1001", boxes: 1, pcs: 10, units: 10)
    @plan.pallets.create!(position: 1, layout: {}, metrics: {}).items.create!(pallet_plan_item: item, boxes: 1, units: 10, layout: {})
    @order = RawOzon::SupplyOrder.create!(account: @account, supply_order_id: "ORDER-#{@token}", status: "IN_TRANSIT",
      raw_json: { "order_number" => "NUMBER-#{@token}" }, synced_at: Time.current)
    @order.supply_order_items.create!(bundle_id: "BUNDLE-#{@token}", ozon_supply_id: 501, platform_sku_id: 1001,
      quantity: 10, state: "IN_TRANSIT", macrolocal_cluster_id: 761, storage_warehouse_id: 9001)
    @calls = []
  end

  test "scheduled sync recovers a submission with an order ID before plan binding and number backfill" do
    @plan.create_ozon_supply_submission!(request_key: "sync-#{@token}", state: "failed", order_id: @order.supply_order_id)

    sync_job

    assert_includes @calls, [@account.id, [@order.supply_order_id]]
    assert_equal @order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal "NUMBER-#{@token}", @plan.supply_order_number
    assert_equal "dispatched", @plan.status
    assert_nil @plan.sync_error
  end

  test "known plan IDs use targeted readback even when the display number is missing" do
    @plan.update!(ozon_order_id: @order.supply_order_id)

    sync_job(plan_id: @plan.id)

    assert_equal [[@account.id, [@order.supply_order_id]]], @calls
    assert_equal "NUMBER-#{@token}", @plan.reload.supply_order_number
    assert_equal "dispatched", @plan.status
  end

  test "unknown manually filled numbers discover and reconcile orders through the account list" do
    @plan.update!(supply_order_number: "NUMBER-#{@token}")

    sync_job(plan_id: @plan.id)

    assert_equal [[@account.id, nil]], @calls
    assert_equal @order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal "dispatched", @plan.status
  end

  test "platform read failures preserve binding and status and record a retryable local error" do
    @plan.update!(ozon_order_id: @order.supply_order_id)

    sync_job(plan_id: @plan.id, error: IOError.new("unavailable"))

    assert_equal @order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal "reserved", @plan.status
    assert_equal Ec::PalletPlans::Error.new(:sync_failed).message, @plan.sync_error
    sync_job(plan_id: @plan.id)
    assert_nil @plan.reload.sync_error
    assert_equal "dispatched", @plan.status
  end

  test "sync selection batches related reads as the pending plan count grows" do
    @plan.create_ozon_supply_submission!(request_key: "batch-#{@token}", state: "syncing", order_id: @order.supply_order_id)
    small = measure_selection
    9.times do |index|
      plan = @plan.dup
      plan.plan_no = nil
      plan.save!
      plan.create_ozon_supply_submission!(request_key: "batch-#{index}-#{@token}", state: "syncing", order_id: "OTHER-#{index}-#{@token}")
    end
    excluded = @plan.dup
    excluded.plan_no = nil
    excluded.status = "cancelled"
    excluded.ozon_order_id = "CANCELLED-#{@token}"
    excluded.save!
    large = measure_selection

    assert_equal 1, small[:plans]
    assert_equal 10, large[:plans]
    assert_operator large[:queries], :<=, small[:queries]
    assert_operator large[:max_sql], :<=, small[:max_sql] + 500
    assert_equal 10, large[:instantiated]["Ec::PalletPlan"]
    assert_equal 10, large[:instantiated]["Ec::OzonSupplySubmission"]
    assert_equal 1, large[:instantiated]["Ec::Store"]
    assert_equal 0, large[:instantiated]["RawOzon::SupplyOrder"]
  end

  private

  def measure_selection
    metrics = { queries: 0, max_sql: 0, instantiated: Hash.new(0) }
    sql = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || payload[:name] == "SCHEMA"
      metrics[:queries] += 1
      metrics[:max_sql] = [metrics[:max_sql], payload[:sql].length].max
    end
    instantiated = lambda do |_name, _start, _finish, _id, payload|
      metrics[:instantiated][payload[:class_name]] += payload[:record_count]
    end
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(sql, "sql.active_record") do
        ActiveSupport::Notifications.subscribed(instantiated, "instantiation.active_record") do
          plans = Ec::PalletPlan.where(store_id: @store.id, status: Ec::PalletPlans::OzonReconciler::SYNC_STATUSES)
            .where.not(status: "closed").with_ozon_supply_reference.includes(:store, :ozon_supply_submission).to_a
          metrics[:plans] = plans.size
          plans.each do |plan|
            assert_equal @account.id, plan.store.ozon_raw_account_id
            assert plan.ozon_sync_order_id.present?
          end
        end
      end
    end
    metrics
  end

  def sync_job(plan_id: nil, error: nil)
    calls = @calls
    test_case = self
    factory = lambda do |account, days:|
      test_case.assert_equal 2, days
      Object.new.tap do |sync|
        sync.define_singleton_method(:sync_supply_orders) do |order_ids: nil|
          calls << [account.id, order_ids]
          raise error if error
        end
      end
    end
    original = RawOzon::DailySync.method(:new)
    RawOzon::DailySync.define_singleton_method(:new, factory)
    Ec::PalletPlanSyncJob.perform_now(plan_id: plan_id)
  ensure
    RawOzon::DailySync.define_singleton_method(:new, original) if original
  end
end
