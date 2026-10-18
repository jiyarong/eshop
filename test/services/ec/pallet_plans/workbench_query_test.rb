require "test_helper"

class Ec::PalletPlans::WorkbenchQueryTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    @token = SecureRandom.hex(6).upcase
    @user = User.create!(email: "pallet-query-#{@token.downcase}@example.com", password: "password123")
    @user.roles << Role.find_by!(code: "super_admin")
    @account = RawOzon::SellerAccount.create!(client_id: "pallet-query-#{@token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Pallet query #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
    @cluster = RawOzon::WarehouseCluster.create!(account: @account, macrolocal_cluster_id: 721,
      cluster_name: "Москва", warehouse_id: 123, warehouse_name: "MOSCOW_TEST", synced_at: Time.current)
    @sku = Ec::Sku.create!(sku_code: "PALLET-QUERY-#{@token}", product_name: "Query test #{@token}")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "PROD-#{@token}", platform_sku_id: "SKU-#{@token}")
    @sku.create_dimension!(outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 8, outer_box_pcs: 10)
    @batch = Ec::SkuBatch.create!(sku: @sku, batch_code: "PALLET-QUERY-#{@token}", status: "received",
      purchased_quantity: 100, received_quantity: 100, purchase_unit_price_cny: 1)
    create_sale(@store, @product, "Москва", 28)
    Ec::SkuInventoryLevel.create!(sku: @sku, store: @store, platform: "ozon", account_id: @account.id,
      fulfillment_type: "fbo", quantity: 7, synced_at: Time.current,
      warehouse_breakdown: [{ warehouse_name: "MOSCOW_TEST", cluster_name: "Москва", quantity: 7, promised: 2 }])
    Ec::SkuOperatorAssignment.create!(sku: @sku, user: @user)
  end

  test "uses selected store and cluster and rounds shortage up to cartons" do
    other_store = Ec::Store.create!(platform: "ozon", store_name: "Other query #{@token}", company_type: "general", ozon_raw_account_id: @account.id + 100_000)
    other_product = Ec::SkuProduct.create!(sku: @sku, store: other_store, product_id: "OTHER-#{@token}", platform_sku_id: "OTHER-SKU-#{@token}")
    create_sale(other_store, other_product, "Москва", 5)

    row = query[:rows].sole

    assert_equal 28, row[:sales_quantity]
    assert_equal 7, row[:available]
    assert_equal 2, row[:inbound]
    assert_equal 19, row[:shortage]
    assert_equal 2, row[:suggested_boxes]
    assert_equal @product.id, row[:sku_product_id]
    assert_equal @user.id, row[:operator_id]
    assert_equal 65, row[:fbs_available]
    assert_equal 65, row[:fbs_allocatable]
    assert row[:packaging_complete]
    assert_nil row[:exclusion_reason]
  end

  test "caps suggested cartons at available whole cartons and preserves negative book stock" do
    @batch.update!(received_quantity: 50)
    assert_equal 15, query[:rows].sole[:fbs_allocatable]
    assert_equal 1, query[:rows].sole[:suggested_boxes]

    @batch.update!(received_quantity: 30)
    row = query[:rows].sole
    assert_equal(-5, row[:fbs_available])
    assert_equal 0, row[:suggested_boxes]
    assert_equal :unavailable, row[:exclusion_reason]
  end

  test "excludes missing packaging and ambiguous listing SKUs from automatic suggestions" do
    @sku.dimension.update!(outer_box_pcs: nil)
    row = query[:rows].sole
    assert_equal :missing_packaging, row[:exclusion_reason]
    assert_equal 0, row[:suggested_boxes]

    @sku.dimension.update!(outer_box_pcs: 10)
    Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "DUPLICATE-#{@token}", platform_sku_id: "DUPLICATE-SKU-#{@token}")
    row = query[:rows].sole
    assert_equal :ambiguous_listing, row[:exclusion_reason]
    assert_nil row[:sku_product_id]
    assert_equal 0, row[:suggested_boxes]
  end

  test "filters visible sku relations and current SKU level responsibility" do
    outsider = User.create!(email: "pallet-outsider-#{@token.downcase}@example.com", password: "password123")
    assert_empty query(user: outsider)[:rows]
    Ec::SkuDeveloperAssignment.create!(sku: @sku, user: outsider)
    assert_equal @sku.sku_code, query(user: outsider, developer_id: outsider.id)[:rows].sole[:sku_code]
    assert_empty query(operator_id: outsider.id)[:rows]
    assert_empty query(sku_codes: Ec::Sku.none.select(:sku_code))[:rows]
  end

  test "rejects inactive accounts and clusters from another account" do
    error = assert_raises(Ec::PalletPlans::Error) { query(cluster_id: -1) }
    assert_equal :invalid_cluster, error.key
    @account.update!(is_active: false)
    error = assert_raises(Ec::PalletPlans::Error) { query }
    assert_equal :invalid_store, error.key
  end

  test "retains SKUs with no selected-cluster sales for manual selection without per-SKU overview" do
    RawOzon::WarehouseCluster.create!(account: @account, macrolocal_cluster_id: 722,
      cluster_name: "Казань", warehouse_id: 124, warehouse_name: "KAZAN_TEST", synced_at: Time.current)
    row = query(cluster_id: 722)[:rows].sole
    assert_equal 0, row[:shortage]
    assert_equal 0, row[:sales_quantity]
    assert_equal :no_shortage, row[:exclusion_reason]
  end

  test "does not double count the plan being edited" do
    plan = Ec::PalletPlan.create!(store: @store, created_by: @user, macrolocal_cluster_id: @cluster.macrolocal_cluster_id,
      cluster_name: @cluster.cluster_name, status: "reserved", from_date: Date.new(2026, 7, 1), to_date: Date.new(2026, 7, 28),
      target_days: 28, time_zone: "Asia/Shanghai")
    plan.items.create!(sku_code: @sku.sku_code, sku_product: @product, platform_sku_id: @product.platform_sku_id,
      boxes: 1, pcs: 10, units: 10)

    row = query[:rows].sole
    assert_equal 10, row[:reserved_quantity]
    assert_equal 55, row[:fbs_allocatable]

    row = query(excluding_plan_id: plan.id)[:rows].sole
    assert_equal 0, row[:reserved_quantity]
    assert_equal 65, row[:fbs_allocatable]

    plan.update!(status: "closed")
    row = query[:rows].sole
    assert_equal 0, row[:reserved_quantity]
    assert_equal 65, row[:fbs_allocatable]
  end

  private

  def query(**overrides)
    Ec::PalletPlans::WorkbenchQuery.new(**{
      user: @user, store: @store, cluster_id: @cluster.macrolocal_cluster_id,
      from_date: Date.new(2026, 7, 1), to_date: Date.new(2026, 7, 28),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"], target_days: 28
    }.merge(overrides)).call
  end

  def create_sale(store, product, cluster, quantity)
    order = Ec::Order.create!(platform: "ozon", store: store, order_key: "pallet-query-#{store.id}-#{@token}",
      order_status: "delivered", ordered_at: Time.zone.parse("2026-07-14 12:00:00"))
    fulfillment = order.fulfillments.create!(platform: "ozon", store: store,
      external_fulfillment_id: "PALLET-#{store.id}-#{@token}", fulfillment_key: "pallet-query-#{store.id}-#{@token}",
      fulfillment_type: "fbo", status: "delivered", cluster_to: cluster)
    order.items.create!(platform: "ozon", store: store, fulfillment: fulfillment, platform_sku_id: product.platform_sku_id, quantity: quantity)
  end
end
