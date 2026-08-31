require "test_helper"

class Ec::WbWarehouseRecommendationQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6).upcase
    @account = RawWb::SellerAccount.create!(name: "WB query #{@token}", api_token: "token-#{@token}", company_type: "small", is_active: true)
    @store = Ec::Store.create!(platform: "wb", store_name: "WB query #{@token}", company_type: "general", wb_raw_account_id: @account.id)
    @sku = Ec::Sku.create!(sku_code: "WBW-#{@token}", product_name: "WB warehouse product #{@token}")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: (700_000_000 + rand(10_000)).to_s, offer_id: "OFFER-#{@token}")
    @operator = User.create!(email: "wb-warehouse-operator-#{@token.downcase}@example.com", password: "password123", active: true)
    Ec::SkuProductOperator.create!(sku_product: @product, user: @operator)
    @region = RawWb::WarehouseRegion.create!(
      account: @account,
      warehouse_id: 600_000_000 + rand(10_000),
      warehouse_name: "Новый склад WB #{@token}",
      normalized_warehouse_name: "unused",
      region_name: "Центральный",
      source: "test",
      raw_json: {},
      synced_at: Time.zone.parse("2026-07-28 08:00:00"),
      last_seen_at: Time.zone.parse("2026-07-28 08:00:00")
    )
    @mapping = RawWb::WarehouseNameMapping.create!(
      account: @account,
      historical_name: "Старый склад #{@token}",
      warehouse_id: @region.warehouse_id,
      canonical_name: @region.warehouse_name,
      region_name: @region.region_name,
      mapping_source: "test",
      confidence: 1,
      status: "verified"
    )
    create_normalized_sales("fbw", "Центральный", 28, "processing")
    create_normalized_sales("fbw", "Центральный", 5, "cancelled")
    create_normalized_sales("fbs", "Центральный", 50, "processing")
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "wb",
      account_id: @account.id,
      store: @store,
      store_name: @store.store_name,
      fulfillment_type: "fbw",
      quantity: 7,
      is_latest: true,
      synced_at: Time.zone.parse("2026-07-28 08:00:00"),
      warehouse_breakdown: [
        { warehouse_name: @region.warehouse_name, warehouse_id: @region.warehouse_id, cluster_name: @region.region_name, quantity: 7 },
        { warehouse_name: "В пути возвраты на склад WB", quantity: 245 },
        { warehouse_name: "В пути до получателей", quantity: 142 }
      ]
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "wb",
      account_id: @account.id,
      store: @store,
      store_name: @store.store_name,
      fulfillment_type: "inbound",
      quantity: 5,
      is_latest: true,
      synced_at: Time.zone.parse("2026-07-28 09:00:00")
    )
  end

  teardown do
    RawWb::StatsOrder.where(account_id: @account&.id).delete_all
    order_scope = Ec::Order.where(store_id: @store&.id)
    fulfillment_scope = Ec::OrderFulfillment.where(order_id: order_scope.select(:id))
    Ec::OrderItem.where(order_id: order_scope.select(:id)).delete_all
    fulfillment_scope.delete_all
    order_scope.delete_all
    Ec::SkuInventoryLevel.where(store_id: @store&.id).delete_all
    RawWb::WarehouseNameMapping.where(account_id: @account&.id).delete_all
    RawWb::WarehouseRegion.where(account_id: @account&.id).delete_all
    Ec::SkuProductOperator.where(user_id: @operator&.id).delete_all
    Ec::SkuProduct.where(store_id: @store&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku&.sku_code).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
    User.where(id: @operator&.id).delete_all
  end

  test "builds recommendations from normalized FBW fulfillment destination clusters" do
    report = Ec::WbWarehouseRecommendationQuery.new(
      store: @store,
      from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 28),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      target_days: 28
    ).call

    row = report[:rows].sole
    assert_equal 28, row[:sales_quantity]
    assert_equal 7, row[:available]
    assert_equal 5, row[:inbound]
    assert_equal @sku.inventory_overview.dig(:summary, :available_stock), row[:fbs_available]
    assert_equal 16, row[:recommended]
    assert_equal "Центральный", row[:clusters].sole[:cluster_name]
    assert_equal @region.warehouse_name, row[:clusters].sole[:warehouses].sole[:warehouse_name]
    assert_equal 28, report.dig(:summary, :mapped_orders)
    assert_equal 28, report.dig(:summary, :total_orders)
    assert_equal 100.to_d, report.dig(:summary, :mapping_coverage)
    assert_equal 5, report.dig(:summary, :inbound)

    cluster = report[:cluster_rows].sole
    assert_equal "Центральный", cluster[:cluster_name]
    assert_equal @sku.sku_code, cluster[:products].sole[:sku_code]
    assert_equal row[:fbs_available], cluster[:products].sole[:fbs_available]
  end

  test "filters products by the selected sku codes" do
    report = Ec::WbWarehouseRecommendationQuery.new(
      store: @store,
      from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 28),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      sku_codes: []
    ).call

    assert_empty report[:rows]
    assert_empty report[:cluster_rows]
  end

  test "filters products by assigned operator" do
    report = Ec::WbWarehouseRecommendationQuery.new(
      store: @store,
      from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 28),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      operator_id: @operator.id
    ).call

    assert_equal [@sku.sku_code], report[:rows].map { |row| row[:sku_code] }

    unassigned_report = Ec::WbWarehouseRecommendationQuery.new(
      store: @store,
      from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 28),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      operator_id: -1
    ).call
    assert_empty unassigned_report[:rows]
  end

  private

  def create_normalized_sales(fulfillment_type, cluster_to, quantity, status)
    suffix = SecureRandom.hex(3)
    order = Ec::Order.create!(
      platform: "wb",
      store: @store,
      order_key: "wb-warehouse-query-#{@token}-#{suffix}",
      order_status: status,
      ordered_at: Time.zone.parse("2026-07-14 12:00:00")
    )
    fulfillment = Ec::OrderFulfillment.create!(
      platform: "wb",
      store: @store,
      order: order,
      external_fulfillment_id: "wb-warehouse-query-#{suffix}",
      fulfillment_key: "wb-warehouse-query-#{@token}-#{suffix}",
      fulfillment_type: fulfillment_type,
      status: status,
      cluster_to: cluster_to
    )
    Ec::OrderItem.create!(
      platform: "wb",
      store: @store,
      order: order,
      fulfillment: fulfillment,
      platform_sku_id: @product.product_id,
      quantity: quantity
    )
  end
end
