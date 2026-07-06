require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("profile-#{@token}@example.com", "manager")
    sign_in @user
  end

  teardown do
    UserApiKey.where(user_id: @user&.id).delete_all if defined?(UserApiKey)
    UserRole.joins(:user).where("users.email = ?", @user.email).delete_all
    @user.destroy
  end

  test "user can edit profile time zone" do
    get "/profile/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "个人设置"
    assert_select "select[name=?]", "user[time_zone]" do
      assert_select "option[value=?][selected]", "Asia/Shanghai", "上海 (UTC+08:00)"
      assert_select "option[value=?]", "UTC", "UTC (UTC+00:00)"
      assert_select "option[value=?]", "Europe/Moscow", "莫斯科 (UTC+03:00)"
    end
  end

  test "user can update profile time zone" do
    patch "/profile", params: { user: { time_zone: "Europe/Moscow" } }, headers: { "Accept" => "text/html" }

    assert_redirected_to "/profile/edit"
    assert_equal "Europe/Moscow", @user.reload.time_zone
  end

  test "user can update profile time zone with plain post fallback" do
    post "/profile", params: { user: { time_zone: "UTC" } }, headers: { "Accept" => "text/html" }

    assert_redirected_to "/profile/edit"
    assert_equal "UTC", @user.reload.time_zone
  end

  test "user can generate own api key and copy the raw token once" do
    assert_difference "UserApiKey.where(user: @user).count", 1 do
      post "/profile/api_keys", params: { api_key: { name: "AI" } }, headers: { "Accept" => "text/html" }
    end

    assert_redirected_to "/profile/edit"
    assert_match(/\Amcp_/, flash[:api_key_token])

    sign_in @user
    get "/profile/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "[data-controller='clipboard']"
    assert_select "[data-clipboard-text-value^='mcp_']"
    assert_select "button[data-action='clipboard#copy']", text: "复制"
    assert_select "[data-clipboard-text-value*='\"mcpServers\"']"
    assert_select "button[data-action='clipboard#copy']", text: "复制MCP配置"
    assert_select "code.api-key-token", /mcp_.+…/
    assert_select "tbody [data-controller='clipboard'][data-clipboard-text-value^='mcp_']"
    assert_select "tbody [data-clipboard-text-value*='https://eshop.evexport.cn/mcp']"
  end

  test "user can revoke own api key" do
    _raw_token, api_key = UserApiKey.generate_for!(@user, name: "AI")

    patch "/profile/api_keys/#{api_key.id}/revoke", headers: { "Accept" => "text/html" }

    assert_redirected_to "/profile/edit"
    assert UserApiKey.find(api_key.id).revoked_at.present?
  end

  test "user cannot create duplicate api key name" do
    UserApiKey.generate_for!(@user, name: "AI")

    assert_no_difference "UserApiKey.where(user: @user).count" do
      post "/profile/api_keys", params: { api_key: { name: "AI" } }, headers: { "Accept" => "text/html" }
    end

    assert_redirected_to "/profile/edit"
    assert flash[:alert].present?
  end
end
