require "test_helper"

class ErpAI::V2::OrdersFullPeriodContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    @sku = Ec::Sku.create!(sku_code: "ORDER-CONTEXT-#{@token}", product_name: "Order context")
    @other_sku = Ec::Sku.create!(sku_code: "ORDER-OTHER-#{@token}", product_name: "Other order item")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Order context #{@token}", company_type: "small")
    @product = Ec::SkuProduct.create!(
      sku: @sku, store: @store, product_id: "PRODUCT-#{@token}", platform_sku_id: "81001"
    )
    @other_product = Ec::SkuProduct.create!(
      sku: @other_sku, store: @store, product_id: "OTHER-#{@token}", platform_sku_id: "81002"
    )
    @order = Ec::Order.create!(
      platform: "ozon", store: @store, order_key: "ozon:#{@token}", order_status: "processing",
      external_order_number: "ORDER-#{@token}", ordered_at: @time_zone.parse("2026-08-03 09:00"),
      source_status: "awaiting_packaging", source_payload: { "region" => "test" }
    )
    @fulfillment = @order.fulfillments.create!(
      platform: "ozon", store: @store, external_fulfillment_id: "F-#{@token}",
      fulfillment_key: "ozon:#{@store.id}:F-#{@token}", fulfillment_type: "fbo", status: "processing",
      warehouse_name: "Test warehouse", cluster_to: "Minsk"
    )
    2.times do |index|
      @order.items.create!(
        fulfillment: @fulfillment, platform: "ozon", store: @store,
        external_item_id: "ITEM-#{@token}-#{index}", platform_sku_id: "81001",
        sku_code: @other_sku.sku_code, quantity: index + 1, unit_price: 100 + index,
        currency_code: "RUB", item_payload: { "index" => index }
      )
    end
    @unrelated_item = @order.items.create!(
      fulfillment: @fulfillment, platform: "ozon", store: @store,
      external_item_id: "OTHER-#{@token}", platform_sku_id: "81002", sku_code: @sku.sku_code,
      quantity: 1, unit_price: 999, currency_code: "RUB"
    )
  end

  teardown do
    Ec::OrderItem.where(order_id: @order&.id).delete_all
    Ec::OrderFulfillment.where(order_id: @order&.id).delete_all
    Ec::Order.where(id: @order&.id).delete_all
    Ec::SkuProduct.where(id: [@product&.id, @other_product&.id]).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::Sku.with_deleted.where(id: [@sku&.id, @other_sku&.id]).delete_all
  end

  test "returns one flattened row per bound item without sku_code fallback" do
    result = ErpAI::V2::OrdersFullPeriodContext.new(
      sku: @sku,
      period_from: Date.new(2026, 8, 3),
      period_to: Date.new(2026, 8, 9),
      time_zone: @time_zone
    ).call

    assert_equal 2, result.size
    assert_equal [@order.id], result.map { |row| row.fetch(:order_id) }.uniq
    assert_equal ["ozon"], result.map { |row| row.fetch(:platform) }.uniq
    assert_equal [@store.id], result.map { |row| row.fetch(:store_id) }.uniq
    assert_equal "Test warehouse", result.first.fetch(:warehouse_name)
    assert_equal [ 1, 2 ], result.map { |row| row.fetch(:quantity) }
    assert_not_includes result.map { |row| row.fetch(:quantity) }, 999
  end

  test "matches WB items through the bound product id" do
    wb_store = Ec::Store.create!(platform: "wb", store_name: "WB order context #{@token}", company_type: "small")
    wb_product = Ec::SkuProduct.create!(sku: @sku, store: wb_store, product_id: "91001")
    wb_order = Ec::Order.create!(
      platform: "wb", store: wb_store, order_key: "wb:#{@token}", order_status: "delivered",
      ordered_at: @time_zone.parse("2026-08-04 10:00")
    )
    wb_order.items.create!(
      platform: "wb", store: wb_store, external_item_id: "WB-ITEM-#{@token}",
      platform_sku_id: "91001", quantity: 1, currency_code: "RUB"
    )

    result = ErpAI::V2::OrdersFullPeriodContext.new(
      sku: @sku,
      period_from: Date.new(2026, 8, 3),
      period_to: Date.new(2026, 8, 9),
      time_zone: @time_zone
    ).call

    assert_equal 3, result.size
    assert_equal({ "ozon" => 2, "wb" => 1 }, result.group_by { |row| row.fetch(:platform) }.transform_values(&:size))
  ensure
    Ec::OrderItem.where(order_id: wb_order&.id).delete_all
    Ec::Order.where(id: wb_order&.id).delete_all
    Ec::SkuProduct.where(id: wb_product&.id).delete_all
    Ec::Store.where(id: wb_store&.id).delete_all
  end
end
