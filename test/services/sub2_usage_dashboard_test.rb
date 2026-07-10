require "test_helper"

class Sub2UsageDashboardTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6)
    @bound_user = create_user("sub2-dashboard-bound-#{@token}@example.com")
    @unbound_user = create_user("sub2-dashboard-unbound-#{@token}@example.com")
    @binding = Sub2UserApiKey.create!(
      user: @bound_user,
      remote_key_id: "remote-#{@token}",
      encrypted_api_key: Sub2UserApiKey.encrypt("sk-sub2-#{@token}"),
      name: "eshop-user-#{@bound_user.id}"
    )
  end

  teardown do
    Sub2UserApiKey.where(user: [@bound_user, @unbound_user]).delete_all
    User.where(id: [@bound_user.id, @unbound_user.id]).delete_all
  end

  test "loads overview and maps per-key usage while retaining unbound users" do
    calls = []
    binding = @binding
    service = Object.new
    service.define_singleton_method(:login) { { "access_token" => "admin-token" } }
    service.define_singleton_method(:usage_stats) do |**args|
      calls << [:stats, args]
      { "total_requests" => 2, "endpoints" => [] }
    end
    service.define_singleton_method(:api_key_usage) do |**args|
      calls << [:keys, args]
      [{ "api_key_id" => binding.remote_key_id, "total_requests" => 3, "total_tokens" => 99 }]
    end

    result = Sub2UsageDashboard.call(
      start_date: Date.new(2026, 7, 9),
      end_date: Date.new(2026, 7, 10),
      service: service
    )

    bound_row = result.user_rows.find { |row| row[:user] == @bound_user }
    unbound_row = result.user_rows.find { |row| row[:user] == @unbound_user }
    assert_equal 2, result.stats["total_requests"]
    assert_equal 3, bound_row[:requests]
    assert_equal 99, bound_row[:total_tokens]
    assert_nil unbound_row[:binding]
    assert_equal 0, unbound_row[:requests]
    key_call = calls.find { |type, _args| type == :keys }
    assert_includes key_call.last[:api_key_ids], @binding.remote_key_id
    assert_includes calls, [:stats, {
      access_token: "admin-token",
      start_date: Date.new(2026, 7, 9),
      end_date: Date.new(2026, 7, 10)
    }]
  end

  private

  def create_user(email)
    User.create!(email:, password: "password123", password_confirmation: "password123")
  end
end
