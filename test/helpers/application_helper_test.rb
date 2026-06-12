require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
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
