require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    sign_in create_user_with_roles("orders-#{@token.downcase}@example.com", "manager")

    @sku = Ec::Sku.create!(
      sku_code: "CTR-#{@token}",
      product_name: "订单中心商品",
      product_name_ru: "Центр заказов",
      is_active: true
    )

    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "订单中心 Ozon 店",
      company_type: "general"
    )

    @order = Ec::Order.create!(
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
      sku_code: @sku.sku_code,
      product_name_source: "Пылесос вертикальный",
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
  end

  teardown do
    Ec::OrderSourceLink.where(order_id: @order&.id).delete_all
    Ec::OrderItem.where(order_id: @order&.id).delete_all
    Ec::OrderFulfillment.where(order_id: @order&.id).delete_all
    @order&.destroy
    @store&.destroy
    @sku&.destroy
    UserRole.joins(:user).where("users.email LIKE ?", "orders-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "orders-#{@token.downcase}%").delete_all
  end

  test "index renders unified order center with filters and tracking summary" do
    get "/orders", params: { platform: "ozon", q: "0128619527" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "订单中心"
    assert_select "form[action=?][method=?]", "/orders", "get"
    assert_select "td", "Ozon"
    assert_select "td", "订单中心 Ozon 店"
    assert_select "td", "配送中"
    assert_select "td", "delivering"
    assert_select "td", "0128619527-0157"
    assert_select "td", "0128619527-0157-1"
    assert_select "td", "Орск"
    assert_select "td", "1 / 1"
    assert_select "a[href=?]", "/orders/#{@order.id}"
  end

  test "show renders order detail with fulfillments items and source links" do
    get "/orders/#{@order.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "订单 0128619527-0157"
    assert_select "h2", "履约与追踪"
    assert_select "td", "0128619527-0157-1"
    assert_select "td", "FBO"
    assert_select "td", "ЕКАТЕРИНБУРГ_РФЦ_НОВЫЙ"
    assert_select "h2", "商品明细"
    assert_select "td", "3902460130"
    assert_select "td", "CTR-#{@token}"
    assert_select "td", "订单中心商品"
    assert_select "td", "140.00"
    assert_select "h2", "原始数据关联"
    assert_select "td", "RawOzon::PostingFbo"
    assert_select "td", "123456"
    assert_select "pre", /posting_number/
  end
end
