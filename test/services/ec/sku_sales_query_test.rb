require "test_helper"

module Ec
  class SkuSalesQueryTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4).upcase
      @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
      @store = Ec::Store.create!(
        platform: "ozon",
        store_name: "销量测试店 #{@token}",
        company_type: "general",
        is_active: true
      )
      @sku = Ec::Sku.create!(sku_code: "SALE-#{@token}", product_name: "销量商品 #{@token}")
      @wrong_sku = Ec::Sku.create!(sku_code: "SALE-WRONG-#{@token}", product_name: "错误商品 #{@token}")
      Ec::SkuProduct.create!(
        sku_code: @sku.sku_code,
        store: @store,
        product_id: "SALE-P-#{@token}",
        platform_sku_id: "SALE-PS-#{@token}",
        product_name: "平台销量商品 #{@token}"
      )
      create_order(
        external_id: "SALE-CUR-#{@token}",
        ordered_at: @time_zone.parse("2026-07-02 10:00:00"),
        quantity: 3,
        status: "delivered"
      )
      create_order(
        external_id: "SALE-RET-#{@token}",
        ordered_at: @time_zone.parse("2026-07-03 10:00:00"),
        quantity: 1,
        status: "returned"
      )
      create_order(
        external_id: "SALE-PREV-#{@token}",
        ordered_at: @time_zone.parse("2026-06-25 10:00:00"),
        quantity: 2,
        status: "delivered"
      )
    end

    teardown do
      Ec::OrderItem.joins(:order).where(ec_orders: { store_id: @store&.id }).delete_all
      Ec::OrderFulfillment.joins(:order).where(ec_orders: { store_id: @store&.id }).delete_all
      Ec::Order.where(store_id: @store&.id).delete_all
      Ec::SkuProduct.where(sku_code: [@sku&.sku_code, @wrong_sku&.sku_code]).delete_all
      Ec::Sku.with_deleted.where(sku_code: [@sku&.sku_code, @wrong_sku&.sku_code]).delete_all
      Ec::Store.where(id: @store&.id).delete_all
    end

    test "summarizes sales by sku product binding instead of order item sku_code" do
      rows = Ec::SkuSalesQuery.new(
        sku_codes: [@sku.sku_code],
        from_date: Date.new(2026, 6, 30),
        to_date: Date.new(2026, 7, 3),
        period: "range",
        grain: "store",
        time_zone: @time_zone
      ).call

      assert_equal 1, rows.size
      row = rows.first
      assert_equal @sku.sku_code, row.fetch(:sku_code)
      assert_equal @store.store_name, row.fetch(:store_name)
      assert_equal 3, row.fetch(:sales_quantity)
      assert_equal 1, row.fetch(:return_quantity)
      assert_equal 2, row.fetch(:net_quantity)
      assert_equal BigDecimal("400"), row.fetch(:gross_revenue)
    end

    private

    def create_order(external_id:, ordered_at:, quantity:, status:)
      order = Ec::Order.create!(
        platform: "ozon",
        store: @store,
        external_order_id: external_id,
        external_order_number: external_id,
        order_key: "ozon:#{@store.id}:#{external_id}",
        order_status: status,
        ordered_at: ordered_at,
        synced_at: ordered_at + 5.minutes
      )
      fulfillment = order.fulfillments.create!(
        platform: "ozon",
        store: @store,
        external_fulfillment_id: "#{external_id}-F",
        fulfillment_key: "ozon:#{@store.id}:#{external_id}-F",
        fulfillment_type: "fbo",
        status: status,
        synced_at: ordered_at + 5.minutes
      )
      order.items.create!(
        fulfillment: fulfillment,
        platform: "ozon",
        store: @store,
        external_item_id: "#{external_id}-I",
        platform_sku_id: "SALE-PS-#{@token}",
        sku_code: @wrong_sku.sku_code,
        product_name_source: "sale item",
        quantity: quantity,
        unit_price: 100,
        payout: 80,
        commission_amount: 10,
        discount_amount: 5,
        currency_code: "BYN",
        synced_at: ordered_at + 5.minutes
      )
    end
  end
end
