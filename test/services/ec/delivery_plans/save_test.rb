require "test_helper"

class Ec::DeliveryPlans::SaveTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    token = SecureRandom.hex(5).upcase
    @user = User.create!(email: "delivery-#{token}@example.com", password: "password123")
    @user.roles << Role.find_by!(code: "super_admin")
    @account = RawOzon::SellerAccount.create!(client_id: "delivery-#{token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Delivery #{token}", company_type: "general", ozon_raw_account_id: @account.id)
    @cluster = RawOzon::WarehouseCluster.create!(account: @account, macrolocal_cluster_id: 761,
      cluster_name: "Москва", warehouse_id: 161, warehouse_name: "DELIVERY_TEST", synced_at: Time.current)
    @sku = Ec::Sku.create!(sku_code: "DELIVERY-#{token}")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: token, platform_sku_id: "10001")
  end

  test "saves unit demand without stock carton data or a packing calculation" do
    assert_no_difference ["Ec::PalletPlan.count", "Ec::Pallet.count", "Ec::OzonSupplySubmission.count"] do
      @delivery = save_delivery(units: 10003)
    end
    assert_equal 10003, @delivery.items.sole.units
    assert_equal Date.new(2026, 10, 19), @delivery.week_start
    assert_equal({}, @delivery.allocated_units)
    assert_equal 0, Ec::PalletPlans::Availability.new(sku_codes: [@sku.sku_code], store_id: @store.id).call.fetch(@sku.sku_code)[:reserved_quantity]
  end

  test "plans more than five SKUs without limiting demand to one pallet" do
    input = attributes(units: 10003)
    5.times do |i|
      sku = Ec::Sku.create!(sku_code: "#{@sku.sku_code}-#{i}")
      Ec::SkuProduct.create!(sku: sku, store: @store, product_id: sku.sku_code, platform_sku_id: "SKU-#{i}")
      input[:items] << { sku_code: sku.sku_code, units: i + 1 }
    end
    assert_equal 6, Ec::DeliveryPlans::Save.new(user: @user, attributes: input).call.items.count
  end

  test "saves SKU selections with optional estimates" do
    [nil, "", " "].each do |units|
      delivery = save_delivery(units: units)
      assert_nil delivery.items.sole.units
    end
    input = attributes(units: nil)
    input[:items].sole.delete(:units)
    assert_nil Ec::DeliveryPlans::Save.new(user: @user, attributes: input).call.items.sole.units
  end

  test "rejects duplicate SKUs fractional zero and invalid estimates atomically" do
    [0, -1, "1.5", "abc", false].each do |units|
      assert_no_difference("Ec::DeliveryPlan.count") do
        assert_raises(Ec::PalletPlans::Error) { save_delivery(units: units) }
      end
    end
    input = attributes(units: 1)
    input[:items] << input[:items].first
    assert_raises(Ec::PalletPlans::Error) { Ec::DeliveryPlans::Save.new(user: @user, attributes: input).call }
  end

  test "splits one plan into box and pallet batches and only confirmed batches reserve stock" do
    prepare_packaging
    delivery = save_delivery(units: 50)
    boxes = save_packing(delivery, boxes: 1, mode: "box")
    pallets = save_packing(delivery, boxes: 2, mode: "pallet")
    assert_equal({ @sku.sku_code => 30 }, delivery.allocated_units)
    assert_equal ["box"], boxes.pallets.pluck(:cargo_type)
    assert_equal ["pallet"], pallets.pallets.pluck(:cargo_type)
    availability = -> { Ec::PalletPlans::Availability.new(sku_codes: [@sku.sku_code], store_id: @store.id).call.fetch(@sku.sku_code) }
    assert_equal 0, availability.call[:reserved_quantity]
    Ec::PalletPlans::Workflow.new(plan: boxes, user: @user).confirm!
    assert_equal 10, availability.call[:reserved_quantity]
    assert_equal 30, delivery.allocated_units.fetch(@sku.sku_code)
    Ec::PalletPlans::Workflow.new(plan: pallets, user: @user).cancel!
    assert_equal 10, delivery.allocated_units.fetch(@sku.sku_code)
  end

  test "packing can exceed estimates and edits update totals while stock still limits quantities" do
    prepare_packaging
    delivery = save_delivery(units: 10)
    batch = save_packing(delivery, boxes: 2)
    save_packing(delivery, boxes: 2, mode: "box")
    assert_equal 40, delivery.allocated_units.fetch(@sku.sku_code)
    Ec::PalletPlans::Workflow.new(plan: batch, user: @user).confirm!
    save_packing(delivery, boxes: 3, plan: batch)
    assert_equal 50, delivery.allocated_units.fetch(@sku.sku_code)
    assert_equal 2, delivery.packing_plans.count
    assert_equal 10, delivery.items.sole.units
    assert_no_difference ["Ec::PalletPlan.count", "Ec::PalletPlanItem.count"] do
      error = assert_raises(Ec::PalletPlans::Error) { save_packing(delivery, boxes: 8) }
      assert_equal :insufficient_stock, error.key
    end
    save_packing(delivery, boxes: 1, plan: batch)
    assert_equal 30, delivery.allocated_units.fetch(@sku.sku_code)
  end

  test "packing without estimates still validates SKU membership" do
    prepare_packaging
    delivery = save_delivery(units: nil)
    save_packing(delivery, boxes: 2)
    assert_equal 20, delivery.allocated_units.fetch(@sku.sku_code)
    delivery.items.destroy_all
    error = assert_raises(Ec::PalletPlans::Error) { save_packing(delivery, boxes: 1) }
    assert_equal :delivery_sku_unavailable, error.key
  end

  test "estimates can decrease or be cleared and edits invalidate stale editors" do
    prepare_packaging
    delivery = save_delivery(units: 31)
    save_packing(delivery, boxes: 2)
    original_version = delivery.lock_version
    Ec::DeliveryPlans::Save.new(user: @user, plan: delivery,
      attributes: attributes(units: 19).merge(lock_version: original_version)).call
    assert_operator delivery.reload.lock_version, :>, original_version
    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::DeliveryPlans::Save.new(user: @user, plan: delivery,
        attributes: attributes(units: 50).merge(lock_version: original_version)).call
    end
    assert_equal :stale_plan, error.key
    assert_equal 19, delivery.items.reload.sole.units
    Ec::DeliveryPlans::Save.new(user: @user, plan: delivery,
      attributes: attributes(units: nil).merge(lock_version: delivery.lock_version)).call
    assert_nil delivery.items.reload.sole.units
    assert_equal 20, delivery.allocated_units.fetch(@sku.sku_code)
  end

  test "used SKUs cannot be removed until their batches are cancelled" do
    prepare_packaging
    delivery = save_delivery(units: nil)
    batch = save_packing(delivery, boxes: 2)
    other_sku = Ec::Sku.create!(sku_code: "#{@sku.sku_code}-OTHER")
    Ec::SkuProduct.create!(sku: other_sku, store: @store, product_id: other_sku.sku_code, platform_sku_id: "10002")
    input = attributes(units: nil).merge(items: [{ sku_code: other_sku.sku_code }], lock_version: delivery.lock_version)
    error = assert_raises(Ec::PalletPlans::Error) do
      Ec::DeliveryPlans::Save.new(user: @user, plan: delivery, attributes: input).call
    end
    assert_equal :delivery_sku_in_use, error.key
    assert_equal @sku.sku_code, delivery.items.reload.sole.sku_code
    Ec::PalletPlans::Workflow.new(plan: batch, user: @user).cancel!
    Ec::DeliveryPlans::Save.new(user: @user, plan: delivery, attributes: input).call
    assert_equal other_sku.sku_code, delivery.items.reload.sole.sku_code
  end

  test "does not reparent a saved batch or allocate to a cancelled delivery" do
    prepare_packaging
    delivery = save_delivery(units: 40)
    batch = save_packing(delivery, boxes: 1)
    other = save_delivery(units: 40)
    assert_raises(Ec::PalletPlans::Error) { save_packing(other, boxes: 1, plan: batch) }
    assert_equal delivery.id, batch.reload.delivery_plan_id
    other.update!(status: "cancelled")
    error = assert_raises(Ec::PalletPlans::Error) { save_packing(other, boxes: 1) }
    assert_equal :delivery_inactive, error.key
  end

  test "allocation summary uses one aggregate query with no instantiated items as batches grow" do
    delivery = save_delivery(units: 200)
    12.times do
      batch = delivery.packing_plans.create!(store: @store, created_by: @user, macrolocal_cluster_id: @cluster.macrolocal_cluster_id,
        cluster_name: @cluster.cluster_name, from_date: delivery.from_date, to_date: delivery.to_date, target_days: 28, time_zone: delivery.time_zone)
      batch.items.create!(sku_product: @product, sku_code: @sku.sku_code, platform_sku_id: "10001", boxes: 1, pcs: 10, units: 10)
    end
    sql, instantiated = [], 0
    sql_subscriber = ->(event) { sql << event.payload[:sql] unless event.payload[:name] == "SCHEMA" }
    record_subscriber = ->(event) { instantiated += event.payload[:record_count] }
    result = nil
    ActiveSupport::Notifications.subscribed(sql_subscriber, "sql.active_record") do
      ActiveSupport::Notifications.subscribed(record_subscriber, "instantiation.active_record") do
        ActiveRecord::Base.uncached { result = delivery.allocated_units }
      end
    end
    assert_equal({ @sku.sku_code => 120 }, result)
    assert_equal 1, sql.size
    assert_includes sql.sole, "SUM"
    assert_operator sql.sole.length, :<, 1000
    assert_equal 0, instantiated
  end

  private

  def attributes(units:)
    { store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id, week_start: "2026-10-21",
      from_date: "2026-09-21", to_date: "2026-10-18", target_days: 28, time_zone: "Asia/Shanghai",
      items: [{ sku_code: @sku.sku_code, units: units }] }
  end

  def save_delivery(units:)
    Ec::DeliveryPlans::Save.new(user: @user, attributes: attributes(units: units)).call
  end

  def prepare_packaging
    @sku.create_dimension!(inner_length_cm: 20, inner_width_cm: 10, inner_height_cm: 10, inner_box_weight_kg: 1,
      outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 8, outer_box_pcs: 10)
    @sku.batches.create!(batch_code: "DELIVERY-#{@sku.sku_code}", status: "received", received_quantity: 100, purchased_quantity: 100)
  end

  def save_packing(delivery, boxes:, mode: "pallet", plan: nil)
    Ec::PalletPlans::Save.new(user: @user, plan: plan, attributes: {
      delivery_plan_id: delivery.id, store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id,
      from_date: delivery.from_date, to_date: delivery.to_date, target_days: 28, shipping_mode: mode,
      items: [{ sku_code: @sku.sku_code, quantity: boxes }]
    }).call
  end
end
