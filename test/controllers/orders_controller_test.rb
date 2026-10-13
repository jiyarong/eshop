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
      completed_at: Time.zone.parse("2026-06-04 10:00:00"),
      cancelled_at: Time.zone.parse("2026-06-05 11:30:00"),
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
      buyer_paid_unit_price: 95.5,
      buyer_currency_code: "RUB",
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

    @sku_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @store,
      product_id: @raw_product.ozon_product_id.to_s,
      offer_id: @raw_product.offer_id,
      platform_sku_id: @raw_product.raw_json["sku"].to_s,
      product_name: @raw_product.name
    )
  end

  teardown do
    Ec::SkuProduct.where(id: @sku_product&.id).delete_all if defined?(Ec::SkuProduct)
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
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "orders-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "orders-#{@token.downcase}%").delete_all
  end

  test "index renders unified order center with filters, amount, and currency" do
    get "/orders", params: { platform: "ozon", q: "0128619527" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "订单中心"
    assert_select "form[action=?][method=?]", "/orders", "get"
    assert_select "td", "Ozon"
    assert_select "td", "订单中心 Ozon 店"
    assert_select "td", "配送中"
    assert_select "th", { text: "源状态", count: 0 }
    assert_select "th", { text: "源子状态", count: 0 }
    assert_select "th", { text: "处理时间", count: 0 }
    assert_select "th", { text: "SKU已关联？", count: 0 }
    assert_select "th", { text: "同步时间", count: 0 }
    assert_select "th", "订单金额"
    assert_select "th", "币种"
    assert_select "th", "履约模式"
    assert_select "td", { text: "delivering", count: 0 }
    assert_select "td", { text: "posting_on_way_to_city", count: 0 }
    assert_select "td", "140.00"
    assert_select "td", "BYN"
    assert_select "td", "FBO"
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

  test "index localizes visible chrome in english" do
    get "/orders", params: { locale: "en", platform: "ozon", q: "0128619527" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "Orders"
    assert_select "label", "Platform"
    assert_select "option", "All platforms"
    assert_select "label", "Search"
    assert_select "input[placeholder=?]", "Order number / Fulfillment / SKU"
    assert_select ".summary-label", "Orders"
    assert_select ".summary-label", "Processing"
    assert_select "th", "Platform"
    assert_select "th", "Fulfillment mode"
    assert_select "th", "Platform order number"
    assert_select "th", { text: "SKU linked?", count: 0 }
    assert_select "th", { text: "Synced at", count: 0 }
    assert_select "th", "Order amount"
    assert_select "th", "Currency"
    assert_select "td", "Shipped"
    assert_select "td", "FBO"
    assert_select "a[href=?]", "/orders/#{@order.id}", "View details"
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
    assert_select "td", { text: "否", count: 0 }
    assert_select "td", { text: "订单中心 Ozon 店", count: 0 }
  end

  test "index renders order time in the current user time zone" do
    get "/orders", params: { q: { platform_eq: "ozon" } }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", "2026-06-02 11:54"

    @current_user.update!(time_zone: "UTC")
    sign_in @current_user

    get "/orders", params: { q: { platform_eq: "ozon" } }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", "2026-06-02 03:54"
  end

  test "index no longer renders time range or date picker filters" do
    get "/orders", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "[data-controller='time-range-selector']", count: 0
    assert_select "[data-controller='date-picker']", count: 0
    assert_select "input[name='from_date']", count: 0
    assert_select "input[name='to_date']", count: 0
    assert_select "input[name='q[in_process_at_gteq]']", count: 0
    assert_select "input[name='q[in_process_at_lteq_end_of_day]']", count: 0
    assert_select "input[name='q[ordered_at_gteq]']", count: 0
    assert_select "input[name='q[ordered_at_lteq_end_of_day]']", count: 0
    assert_select "label[for=?]", "orders-time-range-trigger", count: 0
  end

  test "index ignores legacy date params in the url" do
    get "/orders",
        params: {
          platform: "ozon",
          from_date: "2030-01-01",
          to_date: "2030-01-02",
          process_from_date: "2030-01-01",
          process_to_date: "2030-01-02",
          q: {
            ordered_at_gteq: "2030-01-01",
            ordered_at_lteq_end_of_day: "2030-01-02",
            in_process_at_gteq: "2030-01-01",
            in_process_at_lteq_end_of_day: "2030-01-02"
          }
        },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a[href=?]", "/orders/#{@order.id}"
    assert_select "a[href=?]", "/orders/#{@later_processed_order.id}"
    assert_select "td", "订单中心 Ozon 店"
  end

  test "index renders business and return status columns with order level values" do
    @order.update_columns(business_status: "in_delivery", return_business_status: "returning_to_seller")

    get "/orders", params: { q: { platform_eq: "ozon", order_status_eq: "shipped" } },
                   headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "th", "业务状态"
    assert_select "th", "退货状态"
    headers = css_select("thead th").map { |th| th.text.strip }
    assert_equal headers.index("状态") + 1, headers.index("业务状态")
    assert_equal headers.index("业务状态") + 1, headers.index("退货状态")

    row = css_select("tbody tr").find { |tr| tr.at_css("a[href='/orders/#{@order.id}']") }
    cells = row.css("td").map { |td| td.text.strip }
    assert_equal "配送中", cells[headers.index("业务状态")]
    assert_equal "返回卖家途中", cells[headers.index("退货状态")]
  end

  test "index renders business and return status columns in english" do
    @order.update_columns(business_status: "delivered", return_business_status: "none")

    get "/orders", params: { locale: "en", q: { order_status_eq: "shipped" } }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "th", "Business status"
    assert_select "th", "Return status"
    assert_select "label", "Business status"
    assert_select "label", "Return status"
    assert_select "label", "Fulfillment mode"
    assert_select ".popover-multiselect__trigger span", "All business statuses"
    assert_select ".popover-multiselect__trigger span", "All return statuses"
    assert_select ".popover-multiselect__trigger span", "All fulfillment modes"
    assert_select "td", "Delivered"
    assert_select "td", "No return"
  end

  test "index business status multi-select returns the union of selected statuses and keeps them selected" do
    @order.update_columns(business_status: "in_delivery")
    @wb_order.update_columns(business_status: "awaiting_assembly")
    @later_processed_order.update_columns(business_status: "delivered")

    get "/orders",
        params: { q: { business_status_in: %w[in_delivery awaiting_assembly] } },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a[href=?]", "/orders/#{@order.id}"
    assert_select "a[href=?]", "/orders/#{@wb_order.id}"
    assert_select "a[href=?]", "/orders/#{@later_processed_order.id}", count: 0
    assert_select "input[type=checkbox][name=?][value=?][checked]", "q[business_status_in][]", "in_delivery"
    assert_select "input[type=checkbox][name=?][value=?][checked]", "q[business_status_in][]", "awaiting_assembly"
    assert_select "input[type=checkbox][name=?][value=?][checked]", "q[business_status_in][]", "delivered", count: 0
    assert_select "#orders-business-status-filter-trigger span", "已选 2 项"
  end

  test "index business status filter offers the returned status and filters by it" do
    @order.update_columns(business_status: "returned", return_business_status: "received_by_seller")
    @wb_order.update_columns(business_status: "delivered")

    get "/orders",
        params: { q: { business_status_in: %w[returned] } },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a[href=?]", "/orders/#{@order.id}"
    assert_select "a[href=?]", "/orders/#{@wb_order.id}", count: 0
    assert_select "input[type=checkbox][name=?][value=?][checked]", "q[business_status_in][]", "returned"
    assert_select "input[type=checkbox][name=?][value=?]", "q[business_status_in][]", "delivered"
    row = css_select("tbody tr").find { |tr| tr.at_css("a[href='/orders/#{@order.id}']") }
    assert_includes row.css("td").map { |td| td.text.strip }, "已退货"
  end

  test "index return status multi-select filters by order level return status" do
    @order.update_columns(return_business_status: "expected")
    @wb_order.update_columns(return_business_status: "received_by_seller")

    get "/orders",
        params: { q: { return_business_status_in: %w[expected] } },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a[href=?]", "/orders/#{@order.id}"
    assert_select "a[href=?]", "/orders/#{@wb_order.id}", count: 0
    assert_select "input[type=checkbox][name=?][value=?][checked]", "q[return_business_status_in][]", "expected"
    assert_select "input[type=checkbox][name=?][value=?][checked]", "q[return_business_status_in][]", "received_by_seller", count: 0

    sign_in @current_user

    get "/orders",
        params: { q: { return_business_status_in: %w[expected received_by_seller] } },
        headers: { "Accept" => "text/html" }

    assert_select "a[href=?]", "/orders/#{@order.id}"
    assert_select "a[href=?]", "/orders/#{@wb_order.id}"
  end

  test "index fulfillment mode multi-select matches any selected mode and does not duplicate orders" do
    @order.fulfillments.create!(
      platform: "ozon",
      store: @store,
      external_fulfillment_id: "0128619527-0157-2",
      fulfillment_key: "ozon:#{@store.id}:0128619527-0157-2",
      fulfillment_type: "fbs",
      status: "shipped",
      synced_at: Time.zone.parse("2026-06-02 04:00:00")
    )
    fbs_only_order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      external_order_id: "FBS-ONLY-#{@token}",
      external_order_number: "FBS-ONLY-#{@token}",
      order_key: "ozon:#{@store.id}:FBS-ONLY-#{@token}",
      order_status: "processing",
      ordered_at: Time.zone.parse("2026-06-02 06:00:00"),
      synced_at: Time.zone.parse("2026-06-02 06:05:00")
    )
    fbs_only_order.fulfillments.create!(
      platform: "ozon",
      store: @store,
      external_fulfillment_id: "FBS-ONLY-#{@token}-1",
      fulfillment_key: "ozon:#{@store.id}:FBS-ONLY-#{@token}-1",
      fulfillment_type: "fbs",
      status: "processing",
      synced_at: Time.zone.parse("2026-06-02 06:05:00")
    )

    get "/orders",
        params: { q: { fulfillments_fulfillment_type_in: %w[fbs fbo] } },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a[href=?]", "/orders/#{@order.id}", count: 1
    assert_select "a[href=?]", "/orders/#{fbs_only_order.id}", count: 1
    assert_select "a[href=?]", "/orders/#{@wb_order.id}", count: 0
    assert_select "td", "FBO / FBS"
    assert_select "input[type=checkbox][name=?][value=?][checked]", "q[fulfillments_fulfillment_type_in][]", "fbs"
    assert_select "input[type=checkbox][name=?][value=?][checked]", "q[fulfillments_fulfillment_type_in][]", "fbo"
    assert_select "input[type=checkbox][name=?][value=?][checked]", "q[fulfillments_fulfillment_type_in][]", "fbw", count: 0
    assert_select "label", "履约模式"

    # Status summary counts every matching order once, even with two fulfillments.
    totals = css_select(".weekly-profit-summary-card .summary-value").map { |node| node.text.strip.to_i }
    assert_equal 2, totals.first

    sign_in @current_user

    get "/orders",
        params: { q: { fulfillments_fulfillment_type_in: %w[fbs] } },
        headers: { "Accept" => "text/html" }

    assert_select "a[href=?]", "/orders/#{@order.id}", count: 1
    assert_select "a[href=?]", "/orders/#{fbs_only_order.id}", count: 1

    sign_in @current_user

    get "/orders",
        params: { q: { fulfillments_fulfillment_type_in: %w[fbw] } },
        headers: { "Accept" => "text/html" }

    assert_select "a[href=?]", "/orders/#{@order.id}", count: 0
  ensure
    Ec::OrderFulfillment.where(order_id: fbs_only_order&.id).delete_all
    fbs_only_order&.destroy
  end

  test "index drops unknown multi-select values silently" do
    @order.update_columns(business_status: "in_delivery")

    get "/orders",
        params: {
          q: {
            business_status_in: %w[in_delivery bogus],
            return_business_status_in: %w[bogus],
            fulfillments_fulfillment_type_in: [""]
          }
        },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a[href=?]", "/orders/#{@order.id}"
    assert_select "a[href=?]", "/orders/#{@wb_order.id}", count: 0
    assert_select "input[type=checkbox][name=?][checked]", "q[business_status_in][]", count: 1
    assert_select "input[type=checkbox][name=?][checked]", "q[return_business_status_in][]", count: 0
    assert_select "input[type=checkbox][name=?][checked]", "q[fulfillments_fulfillment_type_in][]", count: 0

    sign_in @current_user

    get "/orders",
        params: { q: { business_status_in: %w[bogus] } },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a[href=?]", "/orders/#{@order.id}"
    assert_select "a[href=?]", "/orders/#{@wb_order.id}"
  end

  test "index combines multi-select statuses with the platform filter" do
    @order.update_columns(business_status: "in_delivery")
    @wb_order.update_columns(business_status: "in_delivery")

    get "/orders",
        params: { q: { platform_eq: "wb", business_status_in: %w[in_delivery] } },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "a[href=?]", "/orders/#{@wb_order.id}"
    assert_select "a[href=?]", "/orders/#{@order.id}", count: 0
    assert_select "select[name=?] option[selected][value=?]", "q[platform_eq]", "wb"
  end

  test "index paginates with the shared pagination bar and keeps filters" do
    @order.update_columns(business_status: "in_delivery")
    @older_orders.each { |order| order.update_columns(business_status: "in_delivery") }

    get "/orders",
        params: { q: { platform_eq: "ozon", business_status_in: %w[in_delivery] } },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "nav.pagination", count: 0
    assert_select ".table-list-card > .inventory-pagination-bar", count: 1
    assert_select ".inventory-pagination-bar nav.pagination-nav[aria-label=?]", "订单列表分页"
    assert_select ".inventory-pagination-bar .pg-btn.on", "1"
    assert_select ".inventory-pagination-bar a.pg-btn" do |links|
      page_two = links.find { |link| link.text.strip == "2" }
      assert page_two, "expected a link to page 2"
      query = Rack::Utils.parse_nested_query(URI.parse(page_two["href"]).query)
      assert_equal "2", query["page"]
      assert_equal "ozon", query.dig("q", "platform_eq")
      assert_equal %w[in_delivery], query.dig("q", "business_status_in")
    end
    assert_select ".inventory-pagination-bar form.pagination-jump input[name=?]", "jump_page"
    assert_select ".inventory-pagination-bar form.pagination-jump input[type=hidden][name=?][value=?]", "q[platform_eq]", "ozon"
    assert_select ".inventory-pagination-bar form.pagination-jump input[type=hidden][name=?][value=?]", "q[business_status_in][]", "in_delivery"
  end

  test "index jump_page selects the requested page" do
    get "/orders",
        params: { q: { platform_eq: "ozon" }, jump_page: 2, current_page: 1 },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-pagination-bar .pg-btn.on", "2"
    assert_select "td", "订单中心 Ozon 店"
    assert_select "a[href=?]", "/orders/#{@later_processed_order.id}", count: 0

    sign_in @current_user

    get "/orders",
        params: { q: { platform_eq: "ozon" }, page: 1, jump_page: "" },
        headers: { "Accept" => "text/html" }

    assert_select ".inventory-pagination-bar .pg-btn.on", "1"
  end

  test "index clamps an out-of-range jump_page to the last page and keeps the pagination bar" do
    get "/orders", params: { q: { platform_eq: "ozon" }, jump_page: 99 }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-pagination-bar", count: 1
    assert_select ".inventory-pagination-bar .pg-btn.on", "2"
    assert_select "td", "订单中心 Ozon 店"
    assert_select ".empty-state", count: 0

    sign_in @current_user

    get "/orders", params: { q: { platform_eq: "ozon" }, page: 99 }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-pagination-bar .pg-btn.on", "2"
  end

  test "index treats non numeric or nested page params as page 1" do
    get "/orders",
        params: { q: { platform_eq: "ozon" }, jump_page: { x: "1" }, page: { x: "1" } },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-pagination-bar .pg-btn.on", "1"
    assert_select "a[href=?]", "/orders/#{@later_processed_order.id}"

    sign_in @current_user

    get "/orders",
        params: { q: { platform_eq: "ozon" }, jump_page: "abc", page: "-3" },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-pagination-bar .pg-btn.on", "1"
  end

  test "index hides the pagination bar when everything fits on one page" do
    get "/orders", params: { q: { platform_eq: "wb" } }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-pagination-bar", count: 0
    assert_select "a[href=?]", "/orders/#{@wb_order.id}"
  end

  test "show renders order detail with fulfillments items and source links" do
    get "/orders/#{@order.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "订单 0128619527-0157-LONG-ORDER"
    assert_select "th", "完成时间"
    assert_select "td", "2026-06-04 18:00"
    assert_select "th", "取消时间"
    assert_select "td", "2026-06-05 19:30"
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

  test "show labels the commission base price and the buyer-paid price separately" do
    get "/orders/#{@order.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "th", "佣金基准价"
    assert_select "th", "买家实付价"
    assert_select "td", "140.00"
    assert_select "td", "95.50 RUB"
  end

  test "show labels the commission base price and the buyer-paid price in english" do
    get "/orders/#{@order.id}", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "th", "Commission base price"
    assert_select "th", "Buyer-paid price"
  end

  test "show localizes visible chrome in english" do
    get "/orders/#{@order.id}", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "Order 0128619527-0157-LONG-ORDER"
    assert_select "a[href=?]", "/orders", "Back to orders"
    assert_select ".summary-label", "Platform / Store"
    assert_select ".summary-label", "Unified status"
    assert_select "h2", "Order information"
    assert_select "th", "Platform order ID"
    assert_select "h2", "Fulfillment and tracking"
    assert_select "th", "Tracking number"
    assert_select "h2", "Items"
    assert_select "th", "Internal SKU"
    assert_select "h2", "SKU details"
    assert_select "th", "FBO available / reserved"
    assert_select "h2", "Source links"
    assert_select "th", "Source type"
    assert_select "td", "Shipped"
  end
end
