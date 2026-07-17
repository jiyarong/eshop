require "test_helper"

class Gbrain::ClientTest < ActiveSupport::TestCase
  class FakeMcpClient
    attr_reader :calls

    def initialize(result = { "content" => [{ "type" => "text", "text" => "ok" }] })
      @result = result
      @calls = []
    end

    def call_tool(name, arguments)
      calls << [name, arguments]
      @result
    end
  end

  FakeRegistry = Data.define(:clients)

  test "calls page write and search tools with normalized arguments" do
    mcp_client = FakeMcpClient.new
    client = build_client(mcp_client)

    client.put_page(slug: "ops/sku", content: "# SKU")
    client.list_pages(limit: 25)
    client.delete_page("ops/obsolete")
    client.query("库存", limit: 5)
    client.search("利润", limit: 8)

    assert_equal [
      ["put_page", { "slug" => "ops/sku", "content" => "# SKU" }],
      ["list_pages", { "limit" => 25, "sort" => "updated_desc" }],
      ["delete_page", { "slug" => "ops/obsolete" }],
      ["query", { "query" => "库存", "limit" => 5 }],
      ["search", { "query" => "利润", "limit" => 8 }]
    ], mcp_client.calls
  end

  test "raises a useful error when an MCP tool reports an error result" do
    result = { "isError" => true, "content" => [{ "type" => "text", "text" => "write rejected" }] }
    client = build_client(FakeMcpClient.new(result))

    error = assert_raises(Gbrain::Client::Error) { client.delete_page("ops/sku") }

    assert_equal "write rejected", error.message
  end

  test "raises when gbrain is not configured" do
    client = Gbrain::Client.new(registry: FakeRegistry.new({}))

    assert_raises(Gbrain::Client::Error) { client.list_pages }
  end

  private

  def build_client(mcp_client)
    Gbrain::Client.new(registry: FakeRegistry.new({ "gbrain" => mcp_client }))
  end
end
