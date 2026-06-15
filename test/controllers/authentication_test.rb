require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
  end

  teardown do
    if defined?(UserRole)
      UserRole.joins(:user).where("users.email LIKE ?", "%#{@token}%").delete_all
    end
    User.where("email LIKE ?", "%#{@token}%").delete_all if defined?(User)
  end

  test "html reports require login" do
    get "/reports/skus", headers: { "Accept" => "text/html" }

    assert_redirected_to "/users/sign_in"
  end

  test "json accounts endpoint remains available without login" do
    get "/weekly_profit_reports/accounts.json"

    assert_response :success
  end

  test "html sign out accepts post form submission" do
    user = create_user_with_roles("sign-out-#{@token}@example.com", "manager")
    sign_in user

    post destroy_user_session_path, headers: { "Accept" => "text/html" }

    assert_redirected_to root_path
    assert_equal "已退出登录。", flash[:notice]
  end

  test "invalid html sign in displays failure reason" do
    user = create_user_with_roles("invalid-sign-in-#{@token}@example.com", "manager")

    post user_session_path,
      params: { user: { email: user.email, password: "wrong-password" } },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "body.auth-shell"
    assert_select ".auth-alert[role='alert']", text: "邮箱或密码错误。"
  end
end
