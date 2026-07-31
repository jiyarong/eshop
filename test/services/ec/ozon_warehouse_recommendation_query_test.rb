require "test_helper"

class Ec::OzonWarehouseRecommendationQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6).upcase
    @sku = Ec::Sku.create!(sku_code: "OWR-#{@token}", product_name: "Ozon warehouse test #{@token}")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Ozon A #{@token}", company_type: "general", ozon_raw_account_id: 900_000_000 + rand(10_000))
    @other_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon B #{@token}", company_type: "general", ozon_raw_account_id: 910_000_000 + rand(10_000))
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "PROD-A-#{@token}", platform_sku_id: "SKU-A-#{@token}", offer_id: "OFFER-A-#{@token}")
    @other_product = Ec::SkuProduct.create!(sku: @sku, store: @other_store, product_id: "PROD-B-#{@token}", platform_sku_id: "SKU-B-#{@token}", offer_id: "OFFER-B-#{@token}")
    @operator = User.create!(email: "ozon-warehouse-operator-#{@token.downcase}@example.com", password: "password123", active: true)
    Ec::SkuProductOperator.create!(sku_product: @product, user: @operator)

    create_sale(@store, @product.platform_sku_id, "Москва", 28)
    create_sale(@other_store, @other_product.platform_sku_id, "Казань", 280)
    create_inventory(@store, 7, "Москва", "ДОМОДЕДОВО_РФЦ")
    create_inventory(@other_store, 700, "Казань", "КАЗАНЬ_РФЦ")
  end

  teardown do
    store_ids = [@store&.id, @other_store&.id].compact
    Ec::OrderItem.where(store_id: store_ids).delete_all
    Ec::OrderFulfillment.where(store_id: store_ids).delete_all
    Ec::Order.where(store_id: store_ids).delete_all
    Ec::SkuInventoryLevel.where(store_id: store_ids).delete_all
    Ec::SkuProductOperator.where(user_id: @operator&.id).delete_all
    Ec::SkuProduct.where(store_id: store_ids).delete_all
    Ec::Store.where(id: store_ids).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku&.sku_code).delete_all
    User.where(id: @operator&.id).delete_all
  end

  test "builds recommendations from only the selected store" do
    report = Ec::OzonWarehouseRecommendationQuery.new(
      store: @store,
      from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 28),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      target_days: 28
    ).call

    row = report[:rows].sole
    assert_equal 28, row[:sales_quantity]
    assert_equal 7, row[:available]
    assert_equal @sku.inventory_overview.dig(:summary, :available_stock), row[:fbs_available]
    assert_equal 21, row[:recommended]
    assert_equal "Москва", row[:clusters].sole[:cluster_name]
    assert_equal "ДОМОДЕДОВО_РФЦ", row[:clusters].sole[:warehouses].sole[:warehouse_name]
    assert_equal 7, report.dig(:summary, :available)

    cluster_row = report[:cluster_rows].sole
    assert_equal "Москва", cluster_row[:cluster_name]
    assert_equal 28, cluster_row[:sales_quantity]
    assert_equal 7, cluster_row[:available]
    assert_equal @sku.sku_code, cluster_row[:products].sole[:sku_code]
  end

  test "does not recommend new inbound when total stock covers demand despite a cluster gap" do
    Ec::SkuInventoryLevel.where(store_id: @store.id).update_all(
      quantity: 40,
      warehouse_breakdown: [{ warehouse_name: "КАЗАНЬ_РФЦ", cluster_name: "Казань", quantity: 40, reserved: 0, promised: 0 }]
    )

    report = Ec::OzonWarehouseRecommendationQuery.new(
      store: @store,
      from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 28),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      target_days: 28
    ).call

    row = report[:rows].sole
    moscow = row[:clusters].find { |cluster| cluster[:cluster_name] == "Москва" }
    assert_equal 0, row[:recommended]
    assert_equal 28, row[:distribution_gap]
    assert_equal 28, moscow[:distribution_gap]
  end

  test "filters products by assigned operator" do
    report = Ec::OzonWarehouseRecommendationQuery.new(
      store: @store,
      from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 28),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      operator_id: @operator.id
    ).call

    assert_equal [@sku.sku_code], report[:rows].map { |row| row[:sku_code] }

    unassigned_report = Ec::OzonWarehouseRecommendationQuery.new(
      store: @store,
      from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 28),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      operator_id: -1
    ).call
    assert_empty unassigned_report[:rows]
  end

  private

  def create_sale(store, platform_sku_id, cluster, quantity)
    order = Ec::Order.create!(
      platform: "ozon",
      store: store,
      order_key: "ozon:#{store.id}:#{@token}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-07-14 12:00:00")
    )
    fulfillment = order.fulfillments.create!(
      platform: "ozon",
      store: store,
      external_fulfillment_id: "FUL-#{store.id}-#{@token}",
      fulfillment_key: "ozon:#{store.id}:FUL-#{@token}",
      fulfillment_type: "fbo",
      status: "delivered",
      cluster_from: cluster,
      cluster_to: cluster
    )
    order.items.create!(platform: "ozon", store: store, fulfillment: fulfillment, platform_sku_id: platform_sku_id, quantity: quantity)
  end

  def create_inventory(store, quantity, cluster, warehouse)
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      account_id: store.ozon_raw_account_id,
      store: store,
      store_name: store.store_name,
      fulfillment_type: "fbo",
      quantity: quantity,
      synced_at: Time.zone.parse("2026-07-28 08:00:00"),
      warehouse_breakdown: [{ warehouse_name: warehouse, cluster_name: cluster, quantity: quantity, reserved: 2, promised: 0 }]
    )
  end

end
