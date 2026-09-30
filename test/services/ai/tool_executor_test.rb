require "test_helper"

class ErpAI::ToolExecutorTest < ActiveSupport::TestCase
  class FakeMcpClient
    attr_reader :tool_name, :arguments

    def call_tool(tool_name, arguments)
      @tool_name = tool_name
      @arguments = arguments
      { "content" => [{ "type" => "text", "text" => "found" }] }
    end
  end

  test "dispatches namespaced MCP tool calls to matching client" do
    client = FakeMcpClient.new
    executor = ErpAI::ToolExecutor.new(mcp_clients: { "search" => client })

    result = executor.call(
      id: "call_1",
      name: "search__web_search",
      arguments: { "query" => "sku" }
    )

    assert_equal "web_search", client.tool_name
    assert_equal({ "query" => "sku" }, client.arguments)
    assert_equal "call_1", result.fetch(:tool_call_id)
    assert_equal "search__web_search", result.fetch(:name)
    assert_equal "found", result.fetch(:result).fetch("content").first.fetch("text")
  end

  test "dispatches erp ai requests with the current user" do
    result = ErpAI::ToolExecutor.new(mcp_clients: {}, current_user: User.new).call(
      id: "call_local",
      name: "erp_ai_request",
      arguments: {
        "method" => "post",
        "url" => "/ai/sql_queries.json",
        "params" => { "sql" => "SELECT 1 AS value", "limit" => 1 }
      }
    )

    assert_equal "call_local", result.fetch(:tool_call_id)
    assert_equal "erp_ai_request", result.fetch(:name)
    assert_equal true, result.dig(:result, :success)
    assert_equal({ "value" => 1 }, result.dig(:result, :body, "rows").first)
  end

  test "dispatches SKU context requests and returns only description and markdown" do
    user = User.create!(email: "sku-context-tool-#{SecureRandom.hex(4)}@example.com", password: "password123", password_confirmation: "password123")
    sku = Ec::Sku.create!(sku_code: "SKU-1-#{SecureRandom.hex(4)}")
    user.roles << Role.find_by!(code: "super_admin")

    result = ErpAI::ToolExecutor.new(mcp_clients: {}, current_user: user).call(
      id: "call_context",
      name: "get_sku_context",
      arguments: { "sku_code" => sku.sku_code, "module" => "base" }
    )

    assert_equal "call_context", result.fetch(:tool_call_id)
    assert_equal "get_sku_context", result.fetch(:name)
    assert_equal sku.sku_code, result.dig(:result, :sku_code)
    assert_equal "base", result.dig(:result, :module)
    assert result.dig(:result, :description).present?
    assert_includes result.dig(:result, :markdown), "## base"
    assert_nil result.dig(:result, :raw_json)
  ensure
    Ec::Sku.where(id: sku&.id).delete_all
    UserRole.where(user_id: user&.id).delete_all
    User.where(id: user&.id).delete_all
  end

  test "returns structured error for unknown tool names" do
    executor = ErpAI::ToolExecutor.new(mcp_clients: {})

    result = executor.call(id: "call_2", name: "query_inventory_data", arguments: {})

    assert_equal "call_2", result.fetch(:tool_call_id)
    assert_equal "unknown_tool", result.fetch(:error).fetch(:code)
  end

  test "returns structured error for unknown MCP server names" do
    executor = ErpAI::ToolExecutor.new(mcp_clients: {})

    result = executor.call(id: "call_3", name: "missing__web_search", arguments: {})

    assert_equal "unknown_mcp_server", result.fetch(:error).fetch(:code)
  end

  test "returns structured error for MCP tools outside configured allowlist" do
    client = FakeMcpClient.new
    executor = ErpAI::ToolExecutor.new(
      mcp_clients: { "search" => client },
      mcp_tool_filters: { "search" => ["web_search"] }
    )

    result = executor.call(id: "call_4", name: "search__fetch_page", arguments: {})

    assert_nil client.tool_name
    assert_equal "mcp_tool_not_allowed", result.fetch(:error).fetch(:code)
  end
end
