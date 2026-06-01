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
end
