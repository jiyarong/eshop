require "test_helper"

module Ec
  class OrderTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4).upcase

      @sku = Ec::Sku.create!(
        sku_code: "ORD-#{@token}",
        product_name: "统一订单测试商品",
        product_name_ru: "Тестовый товар",
        is_active: true
      )

      @raw_account = RawOzon::SellerAccount.create!(
        client_id: "order-test-#{@token}",
        api_key: "test-api-key",
        company_name: "Ozon 统一订单店",
        company_type: "general",
        raw_json: {}
      )

      @store = Ec::Store.create!(
        platform: "ozon",
        store_name: "Ozon 统一订单店",
        company_type: "general",
        ozon_raw_account_id: @raw_account.id
      )

      @raw_posting = RawOzon::PostingFbo.create!(
        account: @raw_account,
        posting_number: "0128619527-0157-1",
        order_id: 36_122_165_127,
        order_number: "0128619527-0157",
        status: "delivering",
        substatus: "posting_on_way_to_city",
        financial_data: {
          "products" => [
            {
              "product_id" => 3_902_460_130,
              "price" => 140,
              "currency_code" => "RUB"
            }
          ]
        },
        analytics_data: {
          "city" => "Орск",
          "warehouse_name" => "ЕКАТЕРИНБУРГ_РФЦ_НОВЫЙ",
          "payment_type_group_name" => "SberPay"
        },
        raw_json: {
          "status" => "delivering",
          "posting_number" => "0128619527-0157-1"
        },
        in_process_at: Time.zone.parse("2026-06-02 03:54:24"),
        created_at: Time.zone.parse("2026-06-02 03:54:10"),
        synced_at: Time.zone.parse("2026-06-02 04:00:00")
      )
    end

    teardown do
      if defined?(Ec::Order)
        orders = Ec::Order.where(order_key: "ozon:#{@store&.id}:0128619527-0157")
        Ec::OrderSourceLink.where(order_id: orders.select(:id)).delete_all if defined?(Ec::OrderSourceLink)
        Ec::OrderItem.where(order_id: orders.select(:id)).delete_all if defined?(Ec::OrderItem)
        Ec::OrderFulfillment.where(order_id: orders.select(:id)).delete_all if defined?(Ec::OrderFulfillment)
        orders.delete_all
      end
      @store&.destroy
      @raw_posting&.destroy
      @raw_account&.destroy
      @sku&.destroy
    end

    test "records normalized marketplace order and links back to raw posting" do
      order = Ec::Order.create!(
        platform: "ozon",
        store: @store,
        external_order_id: "36122165127",
        external_order_number: "0128619527-0157",
        order_key: "ozon:#{@store.id}:0128619527-0157",
        order_status: "shipped",
        source_status: "delivering",
        source_substatus: "posting_on_way_to_city",
        ordered_at: Time.zone.parse("2026-06-02 03:54:10"),
        in_process_at: Time.zone.parse("2026-06-02 03:54:24"),
        buyer_city: "Орск",
        payment_method_source: "SberPay",
        source_payload: @raw_posting.raw_json,
        synced_at: Time.zone.parse("2026-06-02 04:00:00")
      )

      fulfillment = order.fulfillments.create!(
        platform: "ozon",
        store: @store,
        external_fulfillment_id: "0128619527-0157-1",
        fulfillment_key: "ozon:#{@store.id}:0128619527-0157-1",
        fulfillment_type: "fbo",
        status: "shipped",
        source_status: "delivering",
        source_substatus: "posting_on_way_to_city",
        warehouse_name: "ЕКАТЕРИНБУРГ_РФЦ_НОВЫЙ",
        raw_source_type: "RawOzon::PostingFbo",
        raw_source_id: @raw_posting.id,
        synced_at: Time.zone.parse("2026-06-02 04:00:00")
      )

      item = order.items.create!(
        fulfillment: fulfillment,
        platform: "ozon",
        store: @store,
        external_item_id: "0128619527-0157-1:3902460130",
        platform_sku_id: "3902460130",
        offer_id: @sku.sku_code,
        sku_code: @sku.sku_code,
        product_name_source: "Пылесос вертикальный беспроводной 2 в 1",
        quantity: 1,
        unit_price: 140,
        old_unit_price: 553.96,
        currency_code: "BYN",
        payout: 0,
        commission_amount: 0,
        commission_percent: 0,
        discount_amount: 413.96,
        discount_percent: 75,
        item_payload: {
          "sku" => 3_902_460_130,
          "offer_id" => @sku.sku_code
        },
        synced_at: Time.zone.parse("2026-06-02 04:00:00")
      )

      link = order.source_links.create!(
        fulfillment: fulfillment,
        item: item,
        platform: "ozon",
        source_type: "RawOzon::PostingFbo",
        source_id: @raw_posting.id,
        source_key: "0128619527-0157-1",
        source_role: "primary",
        synced_at: Time.zone.parse("2026-06-02 04:00:00")
      )

      assert_equal "shipped", order.order_status
      assert_equal "delivering", order.source_status
      assert_equal [fulfillment], order.fulfillments.to_a
      assert_equal [item], fulfillment.items.to_a
      assert_equal @sku, item.sku
      assert_equal @raw_posting, fulfillment.raw_source
      assert_equal @raw_posting, link.source
    end
  end
end
