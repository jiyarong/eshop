require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @admin = create_user_with_roles("admin-#{@token}@example.com", "super_admin")
    @viewer = create_user_with_roles("viewer-#{@token}@example.com", "auditor")
  end

  teardown do
    if defined?(UserRole)
      UserRole.joins(:user).where("users.email LIKE ?", "%#{@token}%").delete_all
    end
    User.where("email LIKE ?", "%#{@token}%").delete_all if defined?(User)
  end

  test "super admin can render user management" do
    sign_in_as(@admin)

    get "/admin/users", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "用户管理"
  end

  test "non admin cannot manage users" do
    sign_in_as(@viewer)

    get "/admin/users", headers: { "Accept" => "text/html" }

    assert_response :forbidden
  end

  test "super admin can create user with multiple roles" do
    sign_in_as(@admin)

    assert_difference "User.count", 1 do
      post "/admin/users", params: {
        user: {
          email: "created-#{@token}@example.com",
          password: "password123",
          password_confirmation: "password123",
          active: "1",
          role_ids: [Role.find_by!(code: "purchaser").id, Role.find_by!(code: "finance").id]
        }
      }
    end

    created = User.find_by!(email: "created-#{@token}@example.com")
    assert_redirected_to "/admin/users/#{created.id}"
    assert created.has_role?("purchaser")
    assert created.has_role?("finance")
  end

  private

  def create_user_with_roles(email, *role_codes)
    user = User.create!(email: email, password: "password123", password_confirmation: "password123")
    role_codes.each { |code| user.roles << Role.find_by!(code: code) }
    user
  end

  def sign_in_as(user)
    sign_in user
  end
end
