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

  private

  def supply_order(status:, state:)
    order = RawOzon::SupplyOrder.create!(account: @account, supply_order_id: "ORDER-#{@token}", status: status,
      raw_json: { "order_number" => "OZON-NUMBER-#{@token}" }, synced_at: Time.current)
    order.supply_order_items.create!(bundle_id: "BUNDLE-#{@token}", ozon_supply_id: 501, platform_sku_id: 1001,
      quantity: 10, state: state, macrolocal_cluster_id: 761, storage_warehouse_id: 9001, synced_at: Time.current)
    order
  end
end
