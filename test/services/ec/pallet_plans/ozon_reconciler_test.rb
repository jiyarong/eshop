require "test_helper"

class Ec::PalletPlans::OzonReconcilerTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    @token = SecureRandom.hex(6).upcase
    @account = RawOzon::SellerAccount.create!(client_id: "pallet-reconcile-#{@token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Pallet reconcile #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
    @sku = Ec::Sku.create!(sku_code: "PALLET-RECONCILE-#{@token}")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "PROD-#{@token}", platform_sku_id: "1001")
    @plan = Ec::PalletPlan.create!(store: @store, created_by: User.create!(email: "pallet-reconcile-#{@token.downcase}@example.com", password: "password123"),
      macrolocal_cluster_id: 761, cluster_name: "Москва", status: "packed", from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 28), target_days: 28, time_zone: "Asia/Shanghai")
    @plan_item = @plan.items.create!(sku_code: @sku.sku_code, sku_product: @product, platform_sku_id: "1001", boxes: 1, pcs: 10, units: 10)
    @pallet = @plan.pallets.create!(position: 1, layout: {}, metrics: {})
    @pallet.items.create!(pallet_plan_item: @plan_item, boxes: 1, units: 10, layout: {})
  end

  test "binds an Ozon supply number and stores pallet destination evidence" do
    order = supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")

    Ec::PalletPlans::OzonReconciler.new(plan: @plan).bind!("OZON-NUMBER-#{@token}", enqueue: false)

    assert_equal order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal "OZON-NUMBER-#{@token}", @plan.supply_order_number
    assert_equal "READY_TO_SUPPLY", @plan.platform_status
    assert_equal "501", @pallet.reload.ozon_supply_id
    assert_equal 9001, @pallet.storage_warehouse_id
    assert_equal 10, @plan.platform_snapshot.dig("items", @sku.sku_code, "quantity")
  end

  test "advances a bound plan when the platform reports departure" do
    supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")
    Ec::PalletPlans::OzonReconciler.new(plan: @plan).bind!("OZON-NUMBER-#{@token}", enqueue: false)
    order = RawOzon::SupplyOrder.find_by!(account: @account, supply_order_id: "ORDER-#{@token}")
    order.update!(status: "IN_TRANSIT")
    order.supply_order_items.update_all(state: "IN_TRANSIT")

    Ec::PalletPlans::OzonReconciler.new(plan: @plan.reload).sync!

    assert_equal "dispatched", @plan.reload.status
    assert_equal "IN_TRANSIT", @plan.platform_status
  end

  test "binds every bundle even when the supply order spans report pages" do
    order = supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")
    order.supply_order_items.sole.update!(quantity: 1)
    11.times do |index|
      order.supply_order_items.create!(bundle_id: "EXTRA-#{index}-#{@token}", ozon_supply_id: 501, platform_sku_id: 1001,
        quantity: 1, state: "READY_TO_SUPPLY", macrolocal_cluster_id: 761, storage_warehouse_id: 9001)
    end
    @plan_item.update!(pcs: 12, units: 12)
    @pallet.items.sole.update!(units: 12)

    Ec::PalletPlans::OzonReconciler.new(plan: @plan).bind!(order.supply_order_id, enqueue: false)

    assert_equal order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal 12, @plan.platform_snapshot.dig("items", @sku.sku_code, "quantity")
    assert_equal "501", @pallet.reload.ozon_supply_id
  end

  test "rejects extra platform items instead of hiding them with report SKU filters" do
    order = supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")
    order.supply_order_items.create!(bundle_id: "OTHER-#{@token}", ozon_supply_id: 501, platform_sku_id: 1002,
      quantity: 1, state: "READY_TO_SUPPLY", macrolocal_cluster_id: 761, storage_warehouse_id: 9001)

    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::PalletPlans::OzonReconciler.new(plan: @plan).bind!(order.supply_order_id, enqueue: false)
    end

    assert_equal :supply_mismatch, error.key
    assert_nil @plan.reload.ozon_order_id
  end

  test "automatically binds an imported order using the submission ID before a number is filled" do
    @plan.update!(status: "draft")
    order = supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")
    @plan.create_ozon_supply_submission!(request_key: "recover-#{@token}", state: "syncing", order_id: order.supply_order_id)

    Ec::PalletPlans::OzonReconciler.sync_for(account_id: @account.id, order_ids: [order.supply_order_id])

    assert_equal order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal "OZON-NUMBER-#{@token}", @plan.supply_order_number
    assert_equal "reserved", @plan.status
    assert @plan.confirmed_at
    assert_nil @plan.sync_error
  end

  test "automatically matches a manually filled number when the order is imported later" do
    @plan.update!(status: "draft")
    reconciler = Ec::PalletPlans::OzonReconciler.new(plan: @plan)
    reconciler.bind!("OZON-NUMBER-#{@token}", enqueue: false)
    assert_nil @plan.reload.ozon_order_id
    assert_equal "draft", @plan.status
    assert @plan.sync_error
    order = supply_order(status: "IN_TRANSIT", state: "IN_TRANSIT")

    Ec::PalletPlans::OzonReconciler.sync_for(account_id: @account.id, order_ids: [order.supply_order_id])

    assert_equal order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal "dispatched", @plan.status
    assert @plan.confirmed_at
    assert @plan.dispatched_at
    assert_nil @plan.sync_error
  end

  test "maps verified platform completion from a draft to closed" do
    @plan.update!(status: "draft")
    order = supply_order(status: "COMPLETED", state: "COMPLETED")

    Ec::PalletPlans::OzonReconciler.new(plan: @plan).bind!(order.supply_order_id, enqueue: false)

    assert_equal "closed", @plan.reload.status
    assert @plan.confirmed_at
    assert @plan.dispatched_at
    assert @plan.closed_at
    assert_not Ec::PalletPlan.committed.exists?(@plan.id)
  end

  test "does not close an order until every destination is completed or reopen a completed plan" do
    order = supply_order(status: "COMPLETED", state: "IN_TRANSIT")
    reconciler = Ec::PalletPlans::OzonReconciler.new(plan: @plan)
    reconciler.bind!(order.supply_order_id, enqueue: false)
    assert_equal "dispatched", @plan.reload.status
    order.supply_order_items.update_all(state: "COMPLETED")
    reconciler.sync!
    assert_equal "closed", @plan.reload.status

    order.update!(status: "IN_TRANSIT")
    order.supply_order_items.update_all(state: "IN_TRANSIT")
    reconciler.sync!
    assert_equal "closed", @plan.reload.status
    assert_equal "COMPLETED", @plan.platform_status
    assert_equal Ec::PalletPlans::Error.new(:supply_status_regressed).message, @plan.sync_error
  end

  test "platform ready state preserves manually recorded packing progress" do
    order = supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")
    %w[reserved packing packed].each do |status|
      @plan.update!(status: status)
      Ec::PalletPlans::OzonReconciler.new(plan: @plan).bind!(order.supply_order_id, enqueue: false)
      assert_equal status, @plan.reload.status
      assert_nil @plan.dispatched_at
    end
  end

  test "cancelling a bound supply before departure releases the plan reservation without bundle details" do
    order = supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")
    reconciler = Ec::PalletPlans::OzonReconciler.new(plan: @plan)
    reconciler.bind!(order.supply_order_id, enqueue: false)
    order.update!(status: "CANCELLED")
    order.supply_order_items.delete_all

    reconciler.sync!

    assert_equal "cancelled", @plan.reload.status
    assert_equal "CANCELLED", @plan.platform_status
    assert_nil @plan.sync_error
    assert_not Ec::PalletPlan.committed.exists?(@plan.id)
  end

  test "cancellation after departure preserves the reservation for manual reconciliation" do
    order = supply_order(status: "IN_TRANSIT", state: "IN_TRANSIT")
    reconciler = Ec::PalletPlans::OzonReconciler.new(plan: @plan)
    reconciler.bind!(order.supply_order_id, enqueue: false)
    order.update!(status: "CANCELLED")
    order.supply_order_items.delete_all

    reconciler.sync!

    assert_equal "dispatched", @plan.reload.status
    assert_equal "CANCELLED", @plan.platform_status
    assert_equal Ec::PalletPlans::Error.new(:supply_cancelled_after_dispatch).message, @plan.sync_error
    assert Ec::PalletPlan.committed.exists?(@plan.id)
  end

  test "status regression and changed destinations leave the verified plan intact" do
    order = supply_order(status: "IN_TRANSIT", state: "IN_TRANSIT")
    reconciler = Ec::PalletPlans::OzonReconciler.new(plan: @plan)
    reconciler.bind!(order.supply_order_id, enqueue: false)
    order.update!(status: "READY_TO_SUPPLY")
    order.supply_order_items.update_all(state: "READY_TO_SUPPLY")
    reconciler.sync!
    assert_equal "dispatched", @plan.reload.status
    assert_equal "IN_TRANSIT", @plan.platform_status
    assert_equal Ec::PalletPlans::Error.new(:supply_status_regressed).message, @plan.sync_error

    order.update!(status: "IN_TRANSIT")
    order.supply_order_items.update_all(state: "IN_TRANSIT", storage_warehouse_id: 9002)
    reconciler.sync!
    assert_equal 9001, @pallet.reload.storage_warehouse_id
    assert_equal Ec::PalletPlans::Error.new(:supply_warehouse_changed).message, @plan.reload.sync_error
  end

  test "manual recovery cannot attach another order instead of the submitted order" do
    order = supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")
    @plan.create_ozon_supply_submission!(request_key: "recover-#{@token}", state: "review_required", order_id: "OTHER-#{@token}")

    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::PalletPlans::Workflow.new(plan: @plan, user: @plan.created_by).bind!(order.supply_order_id)
    end

    assert_equal :supply_mismatch, error.key
    assert_nil @plan.reload.ozon_order_id
    assert_nil @pallet.reload.ozon_supply_id
  end

  test "manual recovery of a known order preserves unresolved submission errors" do
    order = supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")
    submission = @plan.create_ozon_supply_submission!(request_key: "recover-#{@token}", state: "review_required",
      order_id: order.supply_order_id, last_error: "cargo write uncertain")

    Ec::PalletPlans::Workflow.new(plan: @plan, user: @plan.created_by).bind!("OZON-NUMBER-#{@token}")

    assert_equal order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal "review_required", submission.reload.state
    assert_equal "cargo write uncertain", submission.last_error
    assert_nil @pallet.reload.ozon_cargo_id
  end

  test "rejects an order already bound to another plan on the same account" do
    order = supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")
    other = @plan.dup
    other.plan_no = nil
    other.ozon_order_id = order.supply_order_id
    other.save!

    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::PalletPlans::OzonReconciler.new(plan: @plan).bind!(order.supply_order_id, enqueue: false)
    end

    assert_equal :supply_already_bound, error.key
    assert_nil @plan.reload.ozon_order_id
  end

  test "a sync queued before local cancellation cannot reactivate a cancelled plan" do
    order = supply_order(status: "IN_TRANSIT", state: "IN_TRANSIT")
    @plan.update!(ozon_order_id: order.supply_order_id)
    reconciler = Ec::PalletPlans::OzonReconciler.new(plan: @plan)
    @plan.class.find(@plan.id).update!(status: "cancelled")

    reconciler.sync!

    assert_equal "cancelled", @plan.reload.status
    assert_nil @plan.dispatched_at
    assert_nil @pallet.reload.ozon_supply_id
  end

  test "import matching is scoped to the platform account" do
    order = supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")
    @plan.update!(supply_order_number: "OZON-NUMBER-#{@token}")
    other_account = RawOzon::SellerAccount.create!(client_id: "other-#{@token}", api_key: "test", company_type: "general")
    RawOzon::SupplyOrder.create!(account: other_account, supply_order_id: order.supply_order_id,
      status: "READY_TO_SUPPLY", raw_json: order.raw_json)

    Ec::PalletPlans::OzonReconciler.sync_for(account_id: other_account.id, order_ids: [order.supply_order_id])

    assert_nil @plan.reload.ozon_order_id
    assert_nil @plan.platform_synced_at
  end

  test "import matches a manually filled parent ID as well as an order number" do
    order = supply_order(status: "READY_TO_SUPPLY", state: "READY_TO_SUPPLY")
    @plan.update!(supply_order_number: order.supply_order_id)

    Ec::PalletPlans::OzonReconciler.sync_for(account_id: @account.id, order_ids: [order.supply_order_id])

    assert_equal order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal "OZON-NUMBER-#{@token}", @plan.supply_order_number
  end

  private

  def supply_order(status:, state:)
    order = RawOzon::SupplyOrder.create!(account: @account, supply_order_id: "ORDER-#{@token}", status: status,
      raw_json: { "order_number" => "OZON-NUMBER-#{@token}" }, synced_at: Time.current)
    order.supply_order_items.create!(bundle_id: "BUNDLE-#{@token}", ozon_supply_id: 501, platform_sku_id: 1001,
      quantity: 10, state: state, macrolocal_cluster_id: 761, storage_warehouse_id: 9001, synced_at: Time.current)
    order
  end
end
