require "test_helper"

module Ec
  class OrderImportTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4).upcase

      @ozon_account = RawOzon::SellerAccount.create!(
        client_id: "import-ozon-#{@token}",
        api_key: "test-api-key",
        company_name: "Ozon 导入店",
        company_type: "general",
        raw_json: {}
      )
      @ozon_store = Ec::Store.create!(
        platform: "ozon",
        store_name: "Ozon 导入店",
        company_type: "general",
        ozon_raw_account_id: @ozon_account.id
      )

      @wb_account = RawWb::SellerAccount.create!(
        name: "WB 导入店",
        api_token: "wb-token-#{@token}",
        company_type: "small"
      )
      @wb_store = Ec::Store.create!(
        platform: "wb",
        store_name: "WB 导入店",
        company_type: "small",
        wb_raw_account_id: @wb_account.id
      )

      @ozon_fbo = RawOzon::PostingFbo.create!(
        account: @ozon_account,
        posting_number: "OZON-FBO-#{@token}",
        order_id: 100_001,
        order_number: "OZON-ORDER-#{@token}",
        status: "delivered",
        substatus: "posting_received",
        analytics_data: {
          "city" => "Орск",
          "warehouse_id" => 180_445,
          "warehouse_name" => "ЕКАТЕРИНБУРГ_РФЦ_НОВЫЙ",
          "payment_type_group_name" => "SberPay"
        },
        financial_data: {
          "products" => [
            {
              "product_id" => 3_902_460_130,
              "price" => 140,
              "old_price" => 553.96,
              "currency_code" => "RUB",
              "payout" => 0,
              "commission_amount" => 0,
              "commission_percent" => 0,
              "total_discount_value" => 413.96,
              "total_discount_percent" => 75
            }
          ]
        },
        raw_json: { "posting_number" => "OZON-FBO-#{@token}", "status" => "delivering" },
        in_process_at: Time.zone.parse("2026-06-02 03:54:24"),
        fact_delivery_date: Time.zone.parse("2026-06-04 10:00:00"),
        created_at: Time.zone.parse("2026-06-02 03:54:10"),
        synced_at: Time.zone.parse("2026-06-02 04:00:00")
      )
      RawOzon::PostingItem.create!(
        account: @ozon_account,
        posting_number: @ozon_fbo.posting_number,
        posting_type: "fbo",
        ozon_sku: 3_902_460_130,
        offer_id: "XCQ707",
        name: "Пылесос вертикальный",
        quantity: 1,
        price: 140,
        old_price: 553.96,
        currency_code: "BYN",
        raw_json: { "sku" => 3_902_460_130, "offer_id" => "XCQ707" }
      )

      @ozon_fbs = RawOzon::PostingFbs.create!(
        account: @ozon_account,
        posting_number: "OZON-FBS-#{@token}",
        order_id: 100_002,
        order_number: "OZON-ORDER-FBS-#{@token}",
        status: "delivering",
        substatus: "posting_on_way_to_city",
        delivery_method_name: "Ozon Rocket",
        tracking_number: "TRACK-#{@token}",
        analytics_data: { "city" => "Минск", "payment_type_group_name" => "Card" },
        financial_data: { "products" => [] },
        raw_json: { "posting_number" => "OZON-FBS-#{@token}", "status" => "awaiting_packaging" },
        in_process_at: Time.zone.parse("2026-06-03 08:00:00"),
        shipment_date: Time.zone.parse("2026-06-03 18:00:00"),
        delivering_date: Time.zone.parse("2026-06-04 09:00:00"),
        created_at: Time.zone.parse("2026-06-03 07:55:00"),
        synced_at: Time.zone.parse("2026-06-03 08:10:00")
      )
      RawOzon::PostingItem.create!(
        account: @ozon_account,
        posting_number: @ozon_fbs.posting_number,
        posting_type: "fbs",
        ozon_sku: 4_000_001,
        offer_id: "FBS707",
        name: "FBS товар",
        quantity: 2,
        price: 99,
        currency_code: "RUB",
        raw_json: { "sku" => 4_000_001, "offer_id" => "FBS707" }
      )

      @wb_order = RawWb::Order.create!(
        account: @wb_account,
        wb_order_id: 77_001,
        order_uid: "WB-UID-#{@token}",
        srid: "WB-SRID-#{@token}",
        g_number: "WB-G-#{@token}",
        delivery_type: "fbs",
        nm_id: 123_456,
        article: "WB707",
        barcode: "460000000001",
        supplier_status: "confirm",
        wb_status: "waiting",
        price: 1200,
        converted_price: 1200,
        currency_code: 643,
        wb_office: "Moscow Office",
        buyer_info: { "fio" => "Test Buyer" },
        created_at: Time.zone.parse("2026-06-04 09:00:00"),
        updated_at: Time.zone.parse("2026-06-04 09:05:00"),
        synced_at: Time.zone.parse("2026-06-04 09:10:00")
      )
      RawWb::StatsOrder.create!(
        account: @wb_account,
        g_number: @wb_order.g_number,
        order_date: @wb_order.created_at,
        last_change_date: Time.zone.parse("2026-06-05 10:00:00"),
        supplier_article: @wb_order.article,
        barcode: @wb_order.barcode,
        is_cancel: true,
        cancel_date: Time.zone.parse("2026-06-05 10:30:00"),
        srid: @wb_order.srid,
        synced_at: Time.zone.parse("2026-06-05 10:35:00")
      )
      RawWb::StatsSale.create!(
        account: @wb_account,
        g_number: @wb_order.g_number,
        sale_date: Time.zone.parse("2026-06-06 11:00:00"),
        last_change_date: Time.zone.parse("2026-06-06 11:05:00"),
        supplier_article: @wb_order.article,
        barcode: @wb_order.barcode,
        srid: @wb_order.srid,
        synced_at: Time.zone.parse("2026-06-06 11:10:00")
      )
    end

    teardown do
      Ec::OrderSourceLink.where(source_key: [
        @ozon_fbo&.posting_number,
        @ozon_fbs&.posting_number,
        @wb_order&.wb_order_id.to_s
      ].compact).delete_all
      Ec::OrderItem.where(offer_id: %w[XCQ707 FBS707 WB707]).delete_all
      Ec::OrderFulfillment.where(external_fulfillment_id: [
        @ozon_fbo&.posting_number,
        @ozon_fbs&.posting_number,
        @wb_order&.wb_order_id.to_s
      ].compact).delete_all
      Ec::Order.where(store_id: [@ozon_store&.id, @wb_store&.id]).delete_all
      RawOzon::PostingItem.where(account_id: @ozon_account&.id).delete_all
      RawWb::StatsSale.where(account_id: @wb_account&.id).delete_all
      RawWb::StatsOrder.where(account_id: @wb_account&.id).delete_all
      @ozon_fbo&.destroy
      @ozon_fbs&.destroy
      @wb_order&.destroy
      @ozon_store&.destroy
      @wb_store&.destroy
      @ozon_account&.destroy
      @wb_account&.destroy
    end

    test "imports ozon and wb raw orders into normalized orders" do
      result = Ec::OrderImport::Runner.run

      assert_operator result[:ozon], :>=, 2
      assert_operator result[:wb], :>=, 1

      ozon_order = Ec::Order.find_by!(platform: "ozon", external_order_number: "OZON-ORDER-#{@token}")
      assert_equal "delivered", ozon_order.order_status
      assert_equal Time.zone.parse("2026-06-04 10:00:00"), ozon_order.completed_at
      assert_nil ozon_order.cancelled_at
      assert_equal "Орск", ozon_order.buyer_city
      assert_equal "SberPay", ozon_order.payment_method_source
      assert_equal 1, ozon_order.fulfillments.count
      assert_equal "OZON-FBO-#{@token}", ozon_order.fulfillments.first.external_fulfillment_id
      assert_equal "fbo", ozon_order.fulfillments.first.fulfillment_type
      assert_equal @ozon_fbo, ozon_order.source_links.first.source
      assert_equal "XCQ707", ozon_order.items.first.offer_id
      assert_equal "3902460130", ozon_order.items.first.platform_sku_id

      ozon_fbs_order = Ec::Order.find_by!(platform: "ozon", external_order_number: "OZON-ORDER-FBS-#{@token}")
      assert_equal "shipped", ozon_fbs_order.order_status
      assert_nil ozon_fbs_order.completed_at
      assert_equal "fbs", ozon_fbs_order.fulfillments.first.fulfillment_type
      assert_nil ozon_fbs_order.fulfillments.first.delivered_at
      assert_equal "TRACK-#{@token}", ozon_fbs_order.fulfillments.first.tracking_number

      wb_order = Ec::Order.find_by!(platform: "wb", external_order_number: "WB-G-#{@token}")
      assert_equal "processing", wb_order.order_status
      assert_equal Time.zone.parse("2026-06-06 11:00:00"), wb_order.completed_at
      assert_equal Time.zone.parse("2026-06-05 10:30:00"), wb_order.cancelled_at
      assert_equal "WB-SRID-#{@token}", wb_order.external_order_id
      assert_equal "WB707", wb_order.items.first.offer_id
      assert_equal @wb_order, wb_order.source_links.first.source
    end

    private
  end
end
