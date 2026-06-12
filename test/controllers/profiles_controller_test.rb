require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("profile-#{@token}@example.com", "manager")
    sign_in @user
  end

  teardown do
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
end
