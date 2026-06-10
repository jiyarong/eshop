require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("orders-#{@token.downcase}@example.com", "manager")
    sign_in @current_user

    @sku = Ec::Sku.create!(
      sku_code: "CTR-#{@token}",
      product_name: "订单中心商品超长名称用于验证详情页商品名称截断展示避免表格被撑开",
      product_name_ru: "Центр заказов",
      is_active: true
    )

    @ozon_account = RawOzon::SellerAccount.create!(
      client_id: "orders-ozon-#{@token}",
      api_key: "test-key",
      company_name: "订单中心 Ozon Raw #{@token}",
      company_type: "general"
    )

    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "订单中心 Ozon 店",
      company_type: "general",
      ozon_raw_account_id: @ozon_account.id
    )

    @order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      external_order_id: "36122165127",
      external_order_number: "0128619527-0157-LONG-ORDER",
      order_key: "ozon:#{@store.id}:0128619527-0157-LONG-ORDER",
      order_status: "shipped",
      source_status: "delivering",
      source_substatus: "posting_on_way_to_city",
      ordered_at: Time.zone.parse("2026-06-02 03:54:10"),
      in_process_at: Time.zone.parse("2026-06-02 03:54:24"),
      buyer_city: "Орск",
      buyer_country: "RU",
      payment_method_source: "SberPay",
      source_payload: { "status" => "delivering", "posting_number" => "0128619527-0157-1" },
      synced_at: Time.zone.parse("2026-06-02 04:00:00")
    )

    @fulfillment = @order.fulfillments.create!(
      platform: "ozon",
      store: @store,
      external_fulfillment_id: "0128619527-0157-1",
      fulfillment_key: "ozon:#{@store.id}:0128619527-0157-1",
      fulfillment_type: "fbo",
      status: "shipped",
      source_status: "delivering",
      source_substatus: "posting_on_way_to_city",
      warehouse_name: "ЕКАТЕРИНБУРГ_РФЦ_НОВЫЙ",
      delivery_type_source: "PVZ",
      delivered_at: Time.zone.parse("2026-06-04 10:00:00"),
      raw_source_type: "RawOzon::PostingFbo",
      raw_source_id: 123_456,
      synced_at: Time.zone.parse("2026-06-02 04:00:00")
    )

    @item = @order.items.create!(
      fulfillment: @fulfillment,
      platform: "ozon",
      store: @store,
      external_item_id: "0128619527-0157-1:3902460130",
      platform_sku_id: "3902460130",
      offer_id: "CTR-#{@token}",
      product_name_source: "Пылесос вертикальный с очень длинным названием для проверки обрезки строки",
      quantity: 1,
      unit_price: 140,
      old_unit_price: 553.96,
      currency_code: "BYN",
      commission_amount: 0,
      discount_amount: 413.96,
      discount_percent: 75,
      item_payload: { "offer_id" => "CTR-#{@token}" },
      synced_at: Time.zone.parse("2026-06-02 04:00:00")
    )

    @source_link = @order.source_links.create!(
      fulfillment: @fulfillment,
      item: @item,
      platform: "ozon",
      source_type: "RawOzon::PostingFbo",
      source_id: 123_456,
      source_key: "0128619527-0157-1",
      source_role: "primary",
      synced_at: Time.zone.parse("2026-06-02 04:00:00")
    )

    @wb_store = Ec::Store.create!(
      platform: "wb",
      store_name: "订单中心 WB 店",
      company_type: "small"
    )

    @wb_order = Ec::Order.create!(
      platform: "wb",
      store: @wb_store,
      external_order_id: "WB-SRID-#{@token}",
      external_order_number: "WB-G-#{@token}",
      order_key: "wb:#{@wb_store.id}:WB-G-#{@token}",
      order_status: "processing",
      ordered_at: Time.zone.parse("2026-06-02 03:54:10"),
      synced_at: Time.zone.parse("2026-06-02 04:00:00")
    )

    @later_processed_order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      external_order_id: "LATER-PROCESSED-#{@token}",
      external_order_number: "LATER-PROCESSED-#{@token}",
      order_key: "ozon:#{@store.id}:LATER-PROCESSED-#{@token}",
      order_status: "processing",
      ordered_at: Time.zone.parse("2026-06-02 05:00:00"),
      in_process_at: Time.zone.parse("2026-06-03 00:00:00"),
      synced_at: Time.zone.parse("2026-06-03 00:05:00")
    )

    @older_orders = 21.times.map do |index|
      Ec::Order.create!(
        platform: "ozon",
        store: @store,
        external_order_id: "OLDER-#{@token}-#{index}",
        external_order_number: "OLDER-#{@token}-#{index}",
        order_key: "ozon:#{@store.id}:OLDER-#{@token}-#{index}",
        order_status: "processing",
        ordered_at: Time.zone.parse("2026-05-01 00:00:00") + index.minutes,
        synced_at: Time.zone.parse("2026-05-01 00:00:00") + index.minutes
      )
    end

    @raw_product = RawOzon::Product.create!(
      account: @ozon_account,
      ozon_product_id: 9_876_543_210,
      offer_id: "CTR-#{@token}",
      name: "Ozon 原始商品超长名称用于验证详情页 SKU 具体情况名称截断展示",
      currency_code: "BYN",
      barcodes: ["4600000000012"],
      images: ["https://cdn.example.test/ozon-product.jpg"],
      raw_json: { "sku" => 3_902_460_130 },
      synced_at: Time.zone.parse("2026-06-02 05:00:00")
    )

    @raw_price = RawOzon::ProductPrice.create!(
      account: @ozon_account,
      ozon_product_id: @raw_product.ozon_product_id,
      offer_id: @raw_product.offer_id,
      price: 159.90,
      old_price: 199.90,
      marketing_price: 149.90,
      currency_code: "BYN",
      raw_json: { "product_id" => @raw_product.ozon_product_id },
      synced_at: Time.zone.parse("2026-06-02 05:05:00")
    )

    @raw_stock = RawOzon::ProductStock.create!(
      account: @ozon_account,
      ozon_product_id: @raw_product.ozon_product_id,
      offer_id: @raw_product.offer_id,
      present_fbo: 12,
      reserved_fbo: 2,
      present_fbs: 7,
      reserved_fbs: 1,
      raw_json: { "product_id" => @raw_product.ozon_product_id },
      synced_at: Time.zone.parse("2026-06-02 05:10:00")
    )
  end

  teardown do
    RawOzon::ProductStock.where(account_id: @ozon_account&.id).delete_all
    RawOzon::ProductPrice.where(account_id: @ozon_account&.id).delete_all
    RawOzon::Product.where(account_id: @ozon_account&.id).delete_all
    @ozon_account&.destroy
    @older_orders&.each(&:destroy)
    @later_processed_order&.destroy
    @wb_order&.destroy
    @wb_store&.destroy
    Ec::OrderSourceLink.where(order_id: @order&.id).delete_all
    Ec::OrderItem.where(order_id: @order&.id).delete_all
    Ec::OrderFulfillment.where(order_id: @order&.id).delete_all
    @order&.destroy
    @store&.destroy
    @sku&.destroy
    UserRole.joins(:user).where("users.email LIKE ?", "orders-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "orders-#{@token.downcase}%").delete_all
  end

  test "index renders unified order center with filters and sku summary" do
    get "/orders", params: { platform: "ozon", q: "0128619527" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "订单中心"
    assert_select "form[action=?][method=?]", "/orders", "get"
    assert_select "td", "Ozon"
    assert_select "td", "订单中心 Ozon 店"
    assert_select "td", "配送中"
    assert_select "th", { text: "源状态", count: 0 }
    assert_select "th", { text: "源子状态", count: 0 }
    assert_select "td", { text: "delivering", count: 0 }
    assert_select "td", { text: "posting_on_way_to_city", count: 0 }
    assert_select "td", "配送中" do |elements|
      assert_equal "源状态: delivering\n源子状态: posting_on_way_to_city", elements.first["title"]
    end
    assert_select "a[href=?][target=?][rel=?]",
                  "https://seller.ozon.ru/app/postings/crossborder/fbo/0128619527-0157-1",
                  "_blank",
                  "noopener",
                  "0128619527-0157-LONG"
    assert_select "a", { text: "0128619527-0157-LONG-ORDER", count: 0 }
    assert_select "th", { text: "履约单号", count: 0 }
    assert_select "td", { text: "0128619527-0157-1", count: 0 }
    assert_select "td", "Орск"
    assert_select "td" do
      assert_select "a[href=?]", "/erp/skus/#{@sku.id}", "CTR-#{@token}"
    end
    assert_select "a[href=?]", "/orders/#{@order.id}"
  end

  test "index links wb order number to seller order feed" do
    get "/orders", params: { platform: "wb", q: "WB-G-#{@token}" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a[href=?][target=?][rel=?]",
                  "https://seller.wildberries.ru/order-feed?orderId=WB-SRID-#{@token}",
                  "_blank",
                  "noopener",
                  "WB-G-#{@token}"
  end

  test "index filters orders with ransack params" do
    search_key = "external_order_number_or_external_order_id_or_fulfillments_external_fulfillment_id_or_items_offer_id_or_items_platform_sku_id_or_items_sku_code_cont"
    get "/orders", params: { q: { platform_eq: "wb", search_key => "WB-G-#{@token}" } }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "form[action=?][method=?]", "/orders", "get"
    assert_select "select[name=?]", "q[platform_eq]"
    assert_select "input[name=?][value=?]", "q[external_order_number_or_external_order_id_or_fulfillments_external_fulfillment_id_or_items_offer_id_or_items_platform_sku_id_or_items_sku_code_cont]", "WB-G-#{@token}"
    assert_select "td", "WB"
    assert_select "td", "订单中心 WB 店"
    assert_select "td", { text: "订单中心 Ozon 店", count: 0 }
  end

  test "index filters orders by processing date range" do
    get "/orders",
        params: { q: { platform_eq: "ozon", in_process_at_lteq_end_of_day: "2026-06-02" } },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name=?][value=?]", "q[in_process_at_lteq_end_of_day]", "2026-06-02"
    assert_select "td", "0128619527-0157-LONG"
    assert_select "td", { text: "LATER-PROCESSED-#{@token}", count: 0 }
    assert_select "td", { text: "OLDER-#{@token}-20", count: 0 }
  end

  test "index filters order dates in selected timezone and defaults to shanghai" do
    boundary_order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      external_order_id: "SHANGHAI-DAY-#{@token}",
      external_order_number: "SHANGHAI-DAY-#{@token}",
      order_key: "ozon:#{@store.id}:SHANGHAI-DAY-#{@token}",
      order_status: "processing",
      ordered_at: Time.zone.parse("2026-06-01 16:30:00"),
      synced_at: Time.zone.parse("2026-06-01 16:35:00")
    )

    get "/orders",
        params: {
          q: {
            platform_eq: "ozon",
            ordered_at_gteq: "2026-06-02",
            ordered_at_lteq_end_of_day: "2026-06-02"
          }
        },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "select[name=?]", "timezone" do
      assert_select "option[value=?][selected]", "shanghai", "上海"
      assert_select "option[value=?]", "utc", "UTC"
      assert_select "option[value=?]", "russia", "俄区"
    end
    assert_select "a[href=?]", "/orders/#{boundary_order.id}"
    assert_select "td", "2026-06-02 00:30"

    sign_in @current_user

    get "/orders",
        params: {
          timezone: "utc",
          q: {
            platform_eq: "ozon",
            ordered_at_gteq: "2026-06-02",
            ordered_at_lteq_end_of_day: "2026-06-02"
          }
        },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "option[value=?][selected]", "utc", "UTC"
    assert_select "a[href=?]", "/orders/#{boundary_order.id}", count: 0
  ensure
    boundary_order&.destroy
  end

  test "index paginates order list" do
    get "/orders", params: { q: { platform_eq: "ozon" }, page: 2 }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "nav.pagination"
    assert_select "span.page.current", "2"
    assert_select "td", "订单中心 Ozon 店"
  end

  test "show renders order detail with fulfillments items and source links" do
    get "/orders/#{@order.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "订单 0128619527-0157-LONG-ORDER"
    assert_select "h2", "履约与追踪"
    assert_select "th", { text: "履约单号", count: 0 }
    assert_select "td", { text: "0128619527-0157-1", count: 0 }
    assert_select "td", "FBO"
    assert_select "td", "ЕКАТЕРИНБУРГ_РФЦ_НОВЫЙ"
    assert_select "h2", "商品明细"
    assert_select "td", "3902460130"
    assert_select "td", "CTR-#{@token}"
    assert_select "td[title=?]", @sku.product_name, "订单中心商品超长名称用于验证详情页商品名称..."
    assert_select "td[title=?]", @item.product_name_source, "Пылесос вертикальный ..."
    assert_select "td", { text: @sku.product_name, count: 0 }
    assert_select "td", { text: @item.product_name_source, count: 0 }
    assert_select "td", "140.00"
    assert_select "h2", "SKU 具体情况"
    assert_select "td[title=?]", @raw_product.name, "Ozon 原始商品超长名称用于验证详情页 ..."
    assert_select "td", { text: @raw_product.name, count: 0 }
    assert_select "td", "9876543210"
    assert_select "td", "159.90"
    assert_select "td", "149.90"
    assert_select "td", "12 / 2"
    assert_select "td", "7 / 1"
    assert_select "img[src=?][alt=?]", "https://cdn.example.test/ozon-product.jpg", @raw_product.name
    assert_select "h2", "原始数据关联"
    assert_select "td", "RawOzon::PostingFbo"
    assert_select "td", "123456"
    assert_select "th", { text: "来源 Key", count: 0 }
    assert_select "details", { text: /查看订单源片段/, count: 0 }
  end
end
