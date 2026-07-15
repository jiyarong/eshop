require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("mcp-#{@token}@example.com", "operator")
    @raw_api_token, @api_key = UserApiKey.generate_for!(@user, name: "MCP")
    @store = Ec::Store.create!(platform: "wb", store_name: "MCP Store #{@token}", company_type: "small", is_active: true)
    @sku = Ec::Sku.create!(sku_code: "MCP-CTRL-#{@token.upcase}", product_name: "MCP 控制器商品 #{@token}")
    @sku_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @store,
      product_id: "MCP-CTRL-P-#{@token}",
      platform_sku_id: "MCP-CTRL-PS-#{@token}",
      product_name: "MCP 控制器平台商品 #{@token}"
    )
    Ec::SkuProductOperator.create!(sku_product: @sku_product, user: @user)
  end

  teardown do
    Ec::OrderItem.joins(:order).where(ec_orders: { store_id: @store&.id }).delete_all
    Ec::OrderFulfillment.joins(:order).where(ec_orders: { store_id: @store&.id }).delete_all
    Ec::Order.where(store_id: @store&.id).delete_all
    Ec::SkuProductOperator.where(user_id: @user&.id).delete_all
    Ec::SkuProduct.where(id: @sku_product&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    UserApiKey.where(user_id: @user&.id).delete_all if defined?(UserApiKey)
    UserRole.joins(:user).where(users: { email: @user&.email }).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "rejects missing bearer token" do
    post "/mcp", params: rpc_request("tools/list"), as: :json

    assert_response :unauthorized
  end

  test "lists MCP tools for an authenticated user" do
    post "/mcp",
      params: rpc_request("tools/list"),
      headers: bearer_headers(@raw_api_token),
      as: :json

    assert_response :success
    body = JSON.parse(response.body)
    tool_names = body.fetch("result").fetch("tools").map { |tool| tool.fetch("name") }

    assert_includes tool_names, "list_my_skus"
    assert_includes tool_names, "sku_sales"
    assert_includes tool_names, "sku_profile"
    assert_includes tool_names, "sku_inventory"
    assert_includes tool_names, "sql_query"
    assert_includes tool_names, "operation_context"
  end

  test "lists SQL query tool schema" do
    post "/mcp",
      params: rpc_request("tools/list"),
      headers: bearer_headers(@raw_api_token),
      as: :json

    tool = response.parsed_body.fetch("result").fetch("tools").find { |item| item.fetch("name") == "sql_query" }
    schema = tool.fetch("inputSchema")

    assert_equal ["sql"], schema.fetch("required")
    assert_equal %w[sql limit offset], schema.fetch("properties").keys
  end

  test "calls MCP tools for an authenticated user" do
    post "/mcp",
      params: rpc_request("tools/call", { name: "list_my_skus", arguments: {} }),
      headers: bearer_headers(@raw_api_token),
      as: :json

    assert_response :success
    body = JSON.parse(response.body)
    content = body.fetch("result").fetch("content")
    result = JSON.parse(content.first.fetch("text"))

    assert_equal [@sku.sku_code], result.fetch("items").map { |item| item.fetch("sku_code") }
  end

  test "calls sku_sales over MCP tools call" do
    create_order("MCP-CTRL-SALE-#{@token}", Date.new(2026, 7, 2), 2)

    post "/mcp",
      params: rpc_request("tools/call", {
        name: "sku_sales",
        arguments: {
          sku_code: @sku.sku_code,
          period: "week",
          ended_on: "2026-07-03"
        }
      }),
      headers: bearer_headers(@raw_api_token),
      as: :json

    assert_response :success
    body = JSON.parse(response.body)
    result = JSON.parse(body.fetch("result").fetch("content").first.fetch("text"))

    assert_equal @sku.sku_code, result.fetch("sku_code")
    assert_equal 2, result.fetch("current_period").fetch("summary").fetch("net_quantity")
  end

  test "calls sql_query over MCP tools call" do
    post "/mcp",
      params: rpc_request("tools/call", {
        name: "sql_query",
        arguments: {
          sql: "SELECT sku_code FROM ec_skus WHERE sku_code = '#{@sku.sku_code}'",
          limit: 10,
          offset: 0
        }
      }),
      headers: bearer_headers(@raw_api_token),
      as: :json

    assert_response :success
    body = JSON.parse(response.body)
    result = JSON.parse(body.fetch("result").fetch("content").first.fetch("text"))

    assert_equal true, result.fetch("success")
    assert_equal @sku.sku_code, result.fetch("rows").first.fetch("sku_code")
    assert_equal 10, result.fetch("pagination").fetch("limit")
  end

  private

  def rpc_request(method, params = {})
    {
      jsonrpc: "2.0",
      id: "test-#{@token}",
      method: method,
      params: params
    }
  end

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_order(external_id, ordered_on, quantity)
    ordered_at = ActiveSupport::TimeZone["Asia/Shanghai"].parse("#{ordered_on} 10:00:00")
    order = Ec::Order.create!(
      platform: "wb",
      store: @store,
      external_order_id: external_id,
      external_order_number: external_id,
      order_key: "wb:#{@store.id}:#{external_id}",
      order_status: "delivered",
      ordered_at: ordered_at,
      synced_at: ordered_at + 5.minutes
    )
    fulfillment = order.fulfillments.create!(
      platform: "wb",
      store: @store,
      external_fulfillment_id: "#{external_id}-F",
      fulfillment_key: "wb:#{@store.id}:#{external_id}-F",
      fulfillment_type: "fbw",
      status: "delivered",
      synced_at: ordered_at + 5.minutes
    )
    order.items.create!(
      fulfillment: fulfillment,
      platform: "wb",
      store: @store,
      external_item_id: "#{external_id}-I",
      platform_sku_id: "MCP-CTRL-P-#{@token}",
      product_name_source: "mcp controller sale",
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
