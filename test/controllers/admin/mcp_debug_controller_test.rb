require "test_helper"

class Admin::McpDebugControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @admin = create_user_with_roles("mcp-debug-admin-#{@token}@example.com", "super_admin")
    @operator = create_user_with_roles("mcp-debug-operator-#{@token}@example.com", "operator")
    @viewer = create_user_with_roles("mcp-debug-viewer-#{@token}@example.com", "auditor")
  end

  teardown do
    UserRole.joins(:user).where("users.email LIKE ?", "%mcp-debug-%#{@token}%").delete_all
    User.where("email LIKE ?", "%mcp-debug-%#{@token}%").delete_all
  end

  test "admin can see mcp debug page with all tools and users" do
    sign_in @admin

    get "/admin/mcp_debug", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "MCP调试"
    assert_select "select[name='user_id'] option[value='#{@operator.id}']", text: @operator.email
    assert_select "select[name='tool_name'] option[value='list_my_skus']", text: /list_my_skus/
    assert_select "textarea[name='arguments_json']", false
    assert_select "input[name='tool_arguments[query]']"
    assert_select "select[name='tool_arguments[platform]'] option[value='wb']"
    assert_select "input[name='tool_arguments[limit]']"
  end

  test "non admin cannot see mcp debug page" do
    sign_in @viewer

    get "/admin/mcp_debug", headers: { "Accept" => "text/html" }

    assert_response :forbidden
  end

  test "admin can execute mcp tool as selected user" do
    sign_in @admin

    get "/admin/mcp_debug",
      params: {
        user_id: @operator.id,
        tool_name: "operation_context",
        run: "1"
      },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "section.mcp-debug-result"
    assert_select "section.mcp-debug-result .json-viewer--scroll"
    assert_select "code", /#{@operator.email}/
  end

  test "admin sees only selected mcp tool parameters" do
    sign_in @admin

    get "/admin/mcp_debug", params: { tool_name: "sku_sales" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='tool_arguments[sku_code]']"
    assert_select "select[name='tool_arguments[period]'] option[value='week']"
    assert_select "input[name='tool_arguments[ended_on]']"
    assert_select "input[name='tool_arguments[query]']", false
  end

  test "tool switching refreshes inputs without running previous tool" do
    sign_in @admin

    get "/admin/mcp_debug", params: { tool_name: "sku_sales" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "select[name='tool_name'] option[value='sku_sales'][selected]"
    assert_select "section.mcp-debug-result", false
    assert_select "input[name='tool_arguments[sku_code]']"
    assert_select "input[name='tool_arguments[query]']", false
  end

  test "post redirects to get execution for turbo-safe rendering" do
    sign_in @admin

    post "/admin/mcp_debug",
      params: {
        user_id: @operator.id,
        tool_name: "operation_context",
        tool_arguments: {}
      },
      headers: { "Accept" => "text/html" }

    assert_redirected_to /\/admin\/mcp_debug/
    assert_match(/run=1/, response.location)
  end

  test "selected tool panel is scroll constrained" do
    sign_in @admin

    get "/admin/mcp_debug", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".mcp-debug-tool-schema .json-viewer--scroll"
  end
end
