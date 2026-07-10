require "test_helper"

class Sub2AIServiceTest < ActiveSupport::TestCase
  test "requests usage stats with ISO dates and the access token" do
    service = Sub2AIService.new(host: "https://sub2.example.com")
    captured = nil
    service.define_singleton_method(:get_json) do |path, params:, bearer_token:|
      captured = { path:, params:, bearer_token: }
      { "total_requests" => 2 }
    end

    result = service.usage_stats(
      access_token: "access-token",
      start_date: Date.new(2026, 7, 9),
      end_date: Date.new(2026, 7, 10)
    )

    assert_equal({ "total_requests" => 2 }, result)
    assert_equal "/api/v1/usage/stats", captured[:path]
    assert_equal({ start_date: "2026-07-09", end_date: "2026-07-10" }, captured[:params])
    assert_equal "access-token", captured[:bearer_token]
  end
end
