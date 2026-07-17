require "test_helper"

module ErpAI
  module Mcp
  end
end

class ErpAI::Mcp::ToolAdapterTest < ActiveSupport::TestCase
  test "prefixes MCP tools with server namespace and preserves schema metadata" do
    tools = [
      {
        "name" => "web_search",
        "description" => "Search the web",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "query" => { "type" => "string" }
          }
        }
      }
    ]

    adapted = ErpAI::Mcp::ToolAdapter.adapt(server_name: "search", tools: tools)

    assert_equal 1, adapted.size
    tool = adapted.first
    assert_equal "search__web_search", tool.fetch(:name)
    assert_equal "Search the web", tool.fetch(:description)
    assert_equal "web_search", tool.fetch(:mcp_tool_name)
    assert_equal "search", tool.fetch(:mcp_server_name)
    assert_equal "object", tool.fetch(:parameters).fetch("type")
  end

  test "parses model tool names back into server and MCP tool names" do
    parsed = ErpAI::Mcp::ToolAdapter.parse_model_tool_name("docs__lookup_article")

    assert_equal({ server_name: "docs", tool_name: "lookup_article" }, parsed)
  end

  test "returns nil for non MCP model tool names" do
    assert_nil ErpAI::Mcp::ToolAdapter.parse_model_tool_name("query_inventory_data")
  end
end
