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
end
