require "test_helper"

class Gbrain::McpResultTest < ActiveSupport::TestCase
  test "parses a page list from MCP text content" do
    pages = [ { "slug" => "concepts/stock", "title" => "Stock" } ]
    result = { "content" => [ { "type" => "text", "text" => JSON.generate(pages) } ] }

    assert_equal pages, Gbrain::McpResult.pages(result)
  end

  test "parses a page object from MCP text content" do
    page = { "slug" => "concepts/stock", "content" => "# Stock" }
    result = { "content" => [ { "type" => "text", "text" => JSON.generate(page) } ] }

    assert_equal page, Gbrain::McpResult.payload(result)
  end

  test "uses compiled truth as page content without repeating it in metadata" do
    page = {
      "slug" => "concepts/stock",
      "title" => "Stock",
      "compiled_truth" => "# Stock truth"
    }

    assert_equal "# Stock truth", Gbrain::McpResult.page_content(page)
    assert_equal({ "slug" => "concepts/stock", "title" => "Stock" }, Gbrain::McpResult.page_metadata(page))
  end

  test "keeps the original result when text content is not JSON" do
    result = { "content" => [ { "type" => "text", "text" => "plain text" } ] }

    assert_same result, Gbrain::McpResult.payload(result)
    assert_empty Gbrain::McpResult.pages(result)
  end
end
