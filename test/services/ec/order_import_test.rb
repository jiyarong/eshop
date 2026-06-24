require "test_helper"

module Ec
  class OrderImportTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4).upcase
      @ozon_product_id = 9_000_000_000 + @token.to_i(16)
      @ozon_sku_id = 3_900_000_000 + @token.to_i(16)
      @ozon_fbs_sku_id = 4_000_000_000 + @token.to_i(16)
      @ozon_fbo_order_id = 100_000_000 + @token.to_i(16)
      @wb_nm_id = 123_000_000 + @token.to_i(16)
      @wb_order_id = 77_000_000 + @token.to_i(16)

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
      @ozon_sku = Ec::Sku.create!(
        sku_code: "ERP-OZON-#{@token}",
        product_name: "Ozon ERP SKU #{@token}"
      )
      @ozon_product = RawOzon::Product.create!(
        account: @ozon_account,
        ozon_product_id: @ozon_product_id,
        offer_id: "XCQ707",
        name: "Ozon 平台商品",
        raw_json: { "sku" => @ozon_sku_id },
        synced_at: Time.zone.parse("2026-06-02 03:00:00")
      )
      Ec::SkuProduct.create!(
        sku_code: @ozon_sku.sku_code,
        store: @ozon_store,
        product_id: @ozon_product.ozon_product_id.to_s,
        offer_id: @ozon_product.offer_id,
        platform_sku_id: @ozon_product.raw_json["sku"].to_s,
        product_name: @ozon_product.name
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
      @wb_sku = Ec::Sku.create!(
        sku_code: "ERP-WB-#{@token}",
        product_name: "WB ERP SKU #{@token}"
      )
      @wb_product = RawWb::Product.create!(
        account: @wb_account,
        nm_id: @wb_nm_id,
        vendor_code: "WB707",
        title: "WB 平台商品",
        synced_at: Time.zone.parse("2026-06-04 08:00:00")
      )
      Ec::SkuProduct.create!(
        sku_code: @wb_sku.sku_code,
        store: @wb_store,
        product_id: @wb_product.nm_id.to_s,
        offer_id: @wb_product.vendor_code,
        product_name: @wb_product.title
      )

      @ozon_fbo = RawOzon::PostingFbo.create!(
        account: @ozon_account,
        posting_number: "OZON-FBO-#{@token}",
        order_id: @ozon_fbo_order_id,
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
              "product_id" => @ozon_sku_id,
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
        ozon_sku: @ozon_sku_id,
        offer_id: "XCQ707",
        name: "Пылесос вертикальный",
        quantity: 1,
        price: 140,
        old_price: 553.96,
        currency_code: "BYN",
        raw_json: { "sku" => @ozon_sku_id, "offer_id" => "XCQ707" }
      )

      @ozon_fbs = RawOzon::PostingFbs.create!(
        account: @ozon_account,
        posting_number: "OZON-FBS-#{@token}",
        order_id: @ozon_fbo_order_id + 1,
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
        ozon_sku: @ozon_fbs_sku_id,
        offer_id: "FBS707",
        name: "FBS товар",
        quantity: 2,
        price: 99,
        currency_code: "RUB",
        raw_json: { "sku" => @ozon_fbs_sku_id, "offer_id" => "FBS707" }
      )

      @wb_order = RawWb::Order.create!(
        account: @wb_account,
        wb_order_id: @wb_order_id,
        order_uid: "WB-UID-#{@token}",
        srid: "WB-SRID-#{@token}",
        g_number: "WB-G-#{@token}",
        delivery_type: "fbs",
        nm_id: @wb_nm_id,
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
        total_price: @wb_order.converted_price,
        is_cancel: true,
        cancel_date: Time.zone.parse("2026-06-05 10:30:00"),
        nm_id: @wb_order.nm_id,
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
      order_scope = Ec::Order.where(store_id: [@ozon_store&.id, @wb_store&.id].compact)
      fulfillment_scope = Ec::OrderFulfillment.where(order_id: order_scope.select(:id))
      Ec::OrderSourceLink.where(order_id: order_scope.select(:id)).or(Ec::OrderSourceLink.where(fulfillment_id: fulfillment_scope.select(:id))).delete_all
      Ec::OrderItem.where(order_id: order_scope.select(:id)).or(Ec::OrderItem.where(fulfillment_id: fulfillment_scope.select(:id))).delete_all
      fulfillment_scope.delete_all
      order_scope.delete_all
      Ec::SkuProduct.where(store_id: [@ozon_store&.id, @wb_store&.id]).delete_all if defined?(Ec::SkuProduct)
      RawOzon::PostingItem.where(account_id: @ozon_account&.id).delete_all
      RawWb::StatsSale.where(account_id: @wb_account&.id).delete_all
      RawWb::StatsOrder.where(account_id: @wb_account&.id).delete_all
      RawOzon::Product.where(account_id: @ozon_account&.id).delete_all
      RawWb::Product.where(account_id: @wb_account&.id).delete_all
      @ozon_fbo&.destroy
      @ozon_fbs&.destroy
      @wb_order&.destroy
      @ozon_store&.destroy
      @wb_store&.destroy
      @ozon_account&.destroy
      @wb_account&.destroy
      @ozon_sku&.destroy
      @wb_sku&.destroy
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
      assert_equal @ozon_sku_id.to_s, ozon_order.items.first.platform_sku_id
      assert_equal @ozon_sku.sku_code, ozon_order.items.first.sku_code

      ozon_fbs_order = Ec::Order.find_by!(platform: "ozon", external_order_number: "OZON-ORDER-FBS-#{@token}")
      assert_equal "shipped", ozon_fbs_order.order_status
      assert_nil ozon_fbs_order.completed_at
      assert_equal "fbs", ozon_fbs_order.fulfillments.first.fulfillment_type
      assert_nil ozon_fbs_order.fulfillments.first.delivered_at
      assert_equal "TRACK-#{@token}", ozon_fbs_order.fulfillments.first.tracking_number

      wb_order = Ec::Order.find_by!(platform: "wb", external_order_number: "WB-SRID-#{@token}")
      assert_equal "cancelled", wb_order.order_status
      assert_equal Time.zone.parse("2026-06-06 11:00:00"), wb_order.completed_at
      assert_equal Time.zone.parse("2026-06-05 10:30:00"), wb_order.cancelled_at
      assert_equal "WB-SRID-#{@token}", wb_order.external_order_id
      assert_equal 1, Ec::Order.where(platform: "wb", external_order_id: "WB-SRID-#{@token}").count
      assert_equal "WB707", wb_order.items.first.offer_id
      assert_equal @wb_sku.sku_code, wb_order.items.first.sku_code
      assert_equal @wb_order, wb_order.source_links.first.source
    end

    test "wb import can limit raw orders by synced_at" do
      old_raw = RawWb::Order.create!(
        account: @wb_account,
        wb_order_id: @wb_order_id + 1,
        order_uid: "WB-OLD-#{@token}",
        srid: "WB-OLD-SRID-#{@token}",
        delivery_type: "fbs",
        article: "WBOLD",
        supplier_status: "confirm",
        wb_status: "waiting",
        created_at: Time.zone.parse("2026-06-01 09:00:00"),
        updated_at: Time.zone.parse("2026-06-01 09:05:00"),
        synced_at: Time.zone.parse("2026-06-01 09:10:00")
      )
      cutoff = Time.zone.parse("2026-06-04 00:00:00")

      result = Ec::OrderImport::Wb.new.call(synced_since: cutoff)

      assert_operator result, :>=, 2
      assert_nil Ec::Order.find_by(platform: "wb", external_order_id: old_raw.srid)
      assert Ec::Order.find_by(platform: "wb", external_order_number: "WB-SRID-#{@token}")
    ensure
      Ec::OrderSourceLink.where(source_key: old_raw&.wb_order_id&.to_s).delete_all
      Ec::OrderItem.where(offer_id: "WBOLD").delete_all
      Ec::OrderFulfillment.where(external_fulfillment_id: old_raw&.wb_order_id&.to_s).delete_all
      Ec::Order.where(platform: "wb", external_order_id: old_raw&.srid).delete_all
      old_raw&.destroy
    end

    test "wb import updates existing orders when matching stats orders synced later" do
      first_cutoff = Time.zone.parse("2026-06-04 00:00:00")
      Ec::OrderImport::Wb.new.call(synced_since: first_cutoff)
      wb_order = Ec::Order.find_by!(platform: "wb", external_order_number: "WB-SRID-#{@token}")
      wb_order.update!(cancelled_at: nil)
      @wb_order.update!(synced_at: Time.zone.parse("2026-06-04 09:10:00"))
      stats_order = RawWb::StatsOrder.find_by!(account: @wb_account, srid: @wb_order.srid)
      stats_order.update!(
        is_cancel: true,
        cancel_date: Time.zone.parse("2026-06-07 12:00:00"),
        synced_at: Time.zone.parse("2026-06-07 12:05:00")
      )

      result = Ec::OrderImport::Wb.new.call(synced_since: Time.zone.parse("2026-06-07 00:00:00"))

      assert_operator result, :>=, 1
      assert_equal Time.zone.parse("2026-06-07 12:00:00"), wb_order.reload.cancelled_at
    end

    test "wb import creates orders from stats orders without raw order rows" do
      RawWb::StatsOrder.create!(
        account: @wb_account,
        g_number: "WB-STATS-G-#{@token}",
        order_date: Time.zone.parse("2026-06-08 09:00:00"),
        last_change_date: Time.zone.parse("2026-06-08 09:30:00"),
        supplier_article: "WBSTATSONLY-#{@token}",
        barcode: "460000000099",
        total_price: 456.78,
        warehouse_name: "Stats Warehouse",
        warehouse_type: "Склад WB",
        oblast: "Stats Region",
        nm_id: @wb_product.nm_id,
        srid: "WB-STATS-SRID-#{@token}",
        synced_at: Time.zone.parse("2026-06-08 09:35:00")
      )

      result = Ec::OrderImport::Wb.new.call(synced_since: Time.zone.parse("2026-06-08 00:00:00"))

      assert_operator result, :>=, 1
      stats_order = Ec::Order.find_by!(platform: "wb", external_order_number: "WB-STATS-SRID-#{@token}")
      assert_equal "WB-STATS-SRID-#{@token}", stats_order.external_order_id
      assert_equal "processing", stats_order.order_status
      assert_equal Time.zone.parse("2026-06-08 09:00:00"), stats_order.ordered_at
      assert_equal "Stats Region", stats_order.buyer_city
      assert_equal "WBSTATSONLY-#{@token}", stats_order.items.first.offer_id
      assert_equal BigDecimal("456.78"), stats_order.items.first.unit_price
      assert_equal @wb_sku.sku_code, stats_order.items.first.sku_code
      assert_equal "fbw", stats_order.fulfillments.first.fulfillment_type
    end

    test "wb stats order import maps seller warehouse type to fbs fulfillment" do
      RawWb::StatsOrder.create!(
        account: @wb_account,
        g_number: "WB-STATS-FBS-G-#{@token}",
        order_date: Time.zone.parse("2026-06-08 10:00:00"),
        last_change_date: Time.zone.parse("2026-06-08 10:30:00"),
        supplier_article: "WBSTATSFBS-#{@token}",
        barcode: "460000000098",
        total_price: 123.45,
        warehouse_name: "Seller Warehouse",
        warehouse_type: "Склад продавца",
        nm_id: @wb_product.nm_id,
        srid: "WB-STATS-FBS-SRID-#{@token}",
        synced_at: Time.zone.parse("2026-06-08 10:35:00")
      )

      Ec::OrderImport::Wb.new.call(synced_since: Time.zone.parse("2026-06-08 00:00:00"))

      stats_order = Ec::Order.find_by!(platform: "wb", external_order_number: "WB-STATS-FBS-SRID-#{@token}")
      assert_equal "fbs", stats_order.fulfillments.first.fulfillment_type
    end

    test "wb import lets stats orders overwrite matching raw order data" do
      stats_order = RawWb::StatsOrder.find_by!(account: @wb_account, srid: @wb_order.srid)
      stats_order.update!(
        supplier_article: "WB707-STATS",
        total_price: 777.77,
        warehouse_name: "Stats Cover Warehouse",
        oblast: "Stats Cover Region",
        is_cancel: true,
        cancel_date: Time.zone.parse("2026-06-09 15:00:00"),
        synced_at: Time.zone.parse("2026-06-09 15:05:00")
      )

      Ec::OrderImport::Wb.new.call(synced_since: Time.zone.parse("2026-06-04 00:00:00"))

      wb_order = Ec::Order.find_by!(platform: "wb", external_order_number: "WB-SRID-#{@token}")
      assert_equal Time.zone.parse("2026-06-09 15:00:00"), wb_order.cancelled_at
      assert_equal "Stats Cover Region", wb_order.buyer_city
      assert_equal "WB707-STATS", wb_order.items.first.offer_id
      assert_equal BigDecimal("777.77"), wb_order.items.first.unit_price
      assert_equal "Stats Cover Warehouse", wb_order.fulfillments.first.warehouse_name
    end

    test "ozon import can limit raw postings by synced_at" do
      old_posting = RawOzon::PostingFbo.create!(
        account: @ozon_account,
        posting_number: "OZON-OLD-FBO-#{@token}",
        order_id: 200_001,
        order_number: "OZON-OLD-ORDER-#{@token}",
        status: "delivered",
        raw_json: {},
        created_at: Time.zone.parse("2026-06-01 09:00:00"),
        synced_at: Time.zone.parse("2026-06-01 09:10:00")
      )
      cutoff = Time.zone.parse("2026-06-02 00:00:00")

      result = Ec::OrderImport::Ozon.new.call(synced_since: cutoff)

      assert_operator result, :>=, 2
      assert_nil Ec::Order.find_by(platform: "ozon", external_order_number: old_posting.order_number)
      assert Ec::Order.find_by(platform: "ozon", external_order_number: "OZON-ORDER-#{@token}")
      assert Ec::Order.find_by(platform: "ozon", external_order_number: "OZON-ORDER-FBS-#{@token}")
    ensure
      Ec::OrderSourceLink.where(source_key: old_posting&.posting_number).delete_all
      Ec::OrderFulfillment.where(external_fulfillment_id: old_posting&.posting_number).delete_all
      Ec::Order.where(platform: "ozon", external_order_number: old_posting&.order_number).delete_all
      old_posting&.destroy
    end

    private
  end
end
