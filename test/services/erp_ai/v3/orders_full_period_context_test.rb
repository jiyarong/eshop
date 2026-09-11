require "test_helper"

class ErpAI::V3::OrdersFullPeriodContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    @sku = Ec::Sku.create!(sku_code: "V3-ORDER-#{@token}", product_name: "V3 Order context")
    @other_sku = Ec::Sku.create!(sku_code: "V3-ORDER-OTHER-#{@token}", product_name: "Other V3 Order")
    @store = Ec::Store.create!(platform: "ozon", store_name: "V3 Order #{@token}", company_type: "small")
    @product = Ec::SkuProduct.create!(
      sku: @sku, store: @store, product_id: "PRODUCT-#{@token}", platform_sku_id: "81001"
    )
    @order = Ec::Order.create!(
      platform: "ozon", store: @store, order_key: "v3-ozon:#{@token}", order_status: "processing",
      external_order_number: "ORDER-#{@token}", ordered_at: @time_zone.parse("2026-08-03 09:00")
    )
    @fulfillment = @order.fulfillments.create!(
      platform: "ozon", store: @store, external_fulfillment_id: "F-#{@token}",
      fulfillment_key: "v3-ozon:#{@store.id}:F-#{@token}", fulfillment_type: "fbo", status: "processing"
    )
    @item = @order.items.create!(
      fulfillment: @fulfillment, platform: "ozon", store: @store,
      external_item_id: "ITEM-#{@token}", platform_sku_id: "81001",
      sku_code: @other_sku.sku_code, quantity: 2, unit_price: 100,
      currency_code: "RUB",
      buyer_paid_unit_price: 876.54,
      buyer_currency_code: "RUB",
      buyer_paid_synced_at: @time_zone.parse("2026-08-04 10:35:00"),
      seller_discount_unit_price: 42.63,
      seller_discount_currency_code: "BYN",
      seller_discount_synced_at: @time_zone.parse("2026-08-04 11:35:00")
    )
  end

  teardown do
    Ec::OrderItem.where(order_id: @order&.id).delete_all
    Ec::OrderFulfillment.where(order_id: @order&.id).delete_all
    Ec::Order.where(id: @order&.id).delete_all
    Ec::SkuProduct.where(id: @product&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::Sku.with_deleted.where(id: [@sku&.id, @other_sku&.id]).delete_all
  end

  test "keeps v2 order matching and adds buyer paid and seller discount price fields" do
    result = ErpAI::V3::OrdersFullPeriodContext.new(
      sku: @sku,
      period_from: Date.new(2026, 8, 3),
      period_to: Date.new(2026, 8, 9),
      time_zone: @time_zone
    ).call

    row = result.sole
    assert_equal @item.id, row.fetch(:item_id)
    assert_equal @sku.sku_code, row.fetch(:sku_code)
    assert_equal BigDecimal("100"), row.fetch(:unit_price)
    assert_equal "RUB", row.fetch(:currency_code)
    assert_equal BigDecimal("876.54"), row.fetch(:buyer_paid_unit_price)
    assert_equal "RUB", row.fetch(:buyer_currency_code)
    assert_equal @time_zone.parse("2026-08-04 10:35:00"), row.fetch(:buyer_paid_synced_at)
    assert_equal BigDecimal("42.63"), row.fetch(:seller_discount_unit_price)
    assert_equal "BYN", row.fetch(:seller_discount_currency_code)
    assert_equal @time_zone.parse("2026-08-04 11:35:00"), row.fetch(:seller_discount_synced_at)
  end
end
