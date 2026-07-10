require "test_helper"

class Admin::Sub2UsagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(6)
    @admin = create_user_with_roles("sub2-usage-admin-#{@token}@example.com", "super_admin")
    @viewer = create_user_with_roles("sub2-usage-viewer-#{@token}@example.com", "auditor")
    @binding = Sub2UserApiKey.create!(
      user: @admin,
      remote_key_id: "remote-#{@token}",
      encrypted_api_key: Sub2UserApiKey.encrypt("sk-sub2-#{@token}"),
      name: "eshop-user-#{@admin.id}"
    )
  end

  teardown do
    Sub2UserApiKey.where(user: [@admin, @viewer]).delete_all
    UserRole.where(user: [@admin, @viewer]).delete_all
    User.where(id: [@admin.id, @viewer.id]).delete_all
  end

  test "admin can view overview and usage by user key" do
    result = Sub2UsageDashboard::Result.new(
      stats: {
        "total_requests" => 2,
        "total_input_tokens" => 1_100,
        "total_output_tokens" => 91,
        "total_cache_tokens" => 7_680,
        "total_tokens" => 8_871,
        "total_cost" => 0.006035,
        "total_actual_cost" => 0.006035,
        "average_duration_ms" => 29_832.5,
        "endpoints" => [{
          "endpoint" => "/v1/responses",
          "requests" => 2,
          "total_tokens" => 8_871,
          "cost" => 0.006035,
          "actual_cost" => 0.006035
        }]
      },
      user_rows: [{
        user: @admin,
        binding: @binding,
        requests: 2,
        input_tokens: 1_100,
        output_tokens: 91,
        cache_tokens: 7_680,
        cache_creation_tokens: 0,
        cache_read_tokens: 7_680,
        total_tokens: 8_871,
        cost: 0.006035,
        actual_cost: 0.006035,
        average_duration_ms: 29_832.5
      }]
    )

    with_stubbed_dashboard(result) do
      sign_in @admin
      get "/admin/sub2_usage", params: { start_date: "2026-07-09", end_date: "2026-07-10" },
        headers: { "Accept" => "text/html" }
    end

    assert_response :success
    assert_select "h1", "AI 用量看板"
    assert_select ".erp-nav__link[href='/admin/sub2_usage'][aria-current='page']"
    assert_select "input[name='start_date'][value='2026-07-09']"
    assert_includes response.body, @admin.email
    assert_includes response.body, @binding.masked_api_key
    assert_includes response.body, "/v1/responses"
    assert_not_includes response.body, @binding.api_key
  end

  test "non admin cannot view the dashboard" do
    sign_in @viewer
    get "/admin/sub2_usage", headers: { "Accept" => "text/html" }

    assert_response :forbidden
  end

  test "invalid date range is rejected without loading remote usage" do
    original_call = Sub2UsageDashboard.method(:call)
    Sub2UsageDashboard.define_singleton_method(:call) { |**| flunk("dashboard should not be called") }
    sign_in @admin

    get "/admin/sub2_usage", params: { start_date: "2026-07-10", end_date: "2026-07-09" },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_includes response.body, "开始日期不能晚于结束日期。"
  ensure
    Sub2UsageDashboard.define_singleton_method(:call, original_call) if original_call
  end

  private

  def with_stubbed_dashboard(result)
    original_call = Sub2UsageDashboard.method(:call)
    Sub2UsageDashboard.define_singleton_method(:call) { |**| result }
    yield
  ensure
    Sub2UsageDashboard.define_singleton_method(:call, original_call)
  end
end
