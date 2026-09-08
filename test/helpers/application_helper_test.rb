require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "table viewport renders a shared scroll container" do
    markup = table_viewport(id: "orders-table", class_name: "compact-table", max_height: "480px") do
      tag.table(tag.tbody(tag.tr(tag.td("Order"))))
    end

    fragment = Nokogiri::HTML.fragment(markup)
    viewport = fragment.at_css("#orders-table.table-viewport.table-scroll.compact-table")

    assert viewport
    assert_equal "--table-viewport-max-height: 480px", viewport["style"]
    assert_equal "Order", viewport.at_css("table td").text
  end

  test "table viewport opts into the sticky table header controller" do
    markup = table_viewport(sticky_header: true, data: { controller: "existing" }) do
      tag.table(tag.thead(tag.tr(tag.th("Order"))))
    end

    viewport = Nokogiri::HTML.fragment(markup).at_css(".table-viewport")

    assert_equal "existing sticky-table-header", viewport["data-controller"]
  end

  test "display_time renders values in current user profile time zone" do
    user = User.new(time_zone: "Europe/Moscow")
    singleton_class.define_method(:current_user) { user }

    value = Time.utc(2026, 6, 1, 21, 30)

    assert_equal "2026-06-02 00:30", display_time(value)
  end

  test "display_time defaults to shanghai without a configured user" do
    singleton_class.define_method(:current_user) { nil }

    value = Time.utc(2026, 6, 1, 16, 30)

    assert_equal "2026-06-02 00:30", display_time(value)
    assert_equal "-", display_time(nil)
  end

  test "conversation context renders the data summary without runtime state" do
    context = {
      "data_summary" => "## SKU context\n\nInventory: 3",
      "response_status" => "running"
    }

    assert_equal "## SKU context\n\nInventory: 3", ai_conversation_context_markdown(context)
  end

  test "conversation tool calls are extracted from assistant payloads" do
    tool_request = Message.new(
      role: "assistant",
      content: { tool_calls: [ { id: "call_1", name: "search" } ] }.to_json
    )

    assert_equal "call_1", ai_conversation_tool_call_id(ai_conversation_tool_calls(tool_request).first)
    assert_empty ai_conversation_tool_calls(Message.new(role: "assistant", content: "Answer"))
  end

  test "conversation tool responses expose their tool call id" do
    tool_response = Message.new(
      role: "tool",
      content: { tool_call_id: "call_1", result: { content: "found" } }.to_json
    )

    assert_equal "call_1", ai_conversation_tool_response_id(tool_response)
    assert_nil ai_conversation_tool_response_id(Message.new(role: "tool", content: "invalid"))
  end
end
