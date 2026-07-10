require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @admin = create_user_with_roles("admin-#{@token}@example.com", "super_admin")
    @viewer = create_user_with_roles("viewer-#{@token}@example.com", "auditor")
  end

  teardown do
    Sub2UserApiKey.joins(:user).where("users.email LIKE ?", "%#{@token}%").delete_all if defined?(Sub2UserApiKey)
    UserApiKey.joins(:user).where("users.email LIKE ?", "%#{@token}%").delete_all if defined?(UserApiKey)
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

    with_stubbed_sub2_provisioning do
      assert_difference ["User.count", "Sub2UserApiKey.count"], 1 do
        post "/admin/users", params: {
          user: {
            name: "新用户 #{@token}",
            email: "created-#{@token}@example.com",
            password: "password123",
            password_confirmation: "password123",
            active: "1",
            role_ids: [Role.find_by!(code: "purchaser").id, Role.find_by!(code: "finance").id]
          }
        }
      end
    end

    created = User.find_by!(email: "created-#{@token}@example.com")
    assert_redirected_to "/admin/users/#{created.id}"
    assert_equal "新用户 #{@token}", created.name
    assert created.has_role?("purchaser")
    assert created.has_role?("finance")
    assert_equal "remote-#{created.id}", created.sub2_user_api_key.remote_key_id
  end

  test "Sub2 provisioning failure rolls back user creation" do
    sign_in_as(@admin)
    original_call = Sub2UserApiKeyProvisioner.method(:call)
    Sub2UserApiKeyProvisioner.define_singleton_method(:call) do |**|
      raise Sub2UserApiKeyProvisioner::Error, "remote unavailable"
    end

    assert_no_difference ["User.count", "Sub2UserApiKey.count"] do
      post "/admin/users", params: {
        user: {
          name: "失败用户 #{@token}",
          email: "failed-#{@token}@example.com",
          password: "password123",
          password_confirmation: "password123",
          active: "1",
          role_ids: [Role.find_by!(code: "auditor").id]
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Sub2 API Key 创建失败，用户未保存。"
  ensure
    Sub2UserApiKeyProvisioner.define_singleton_method(:call, original_call) if original_call
  end

  test "super admin can update user name" do
    sign_in_as(@admin)

    patch "/admin/users/#{@viewer.id}", params: {
      user: {
        name: "审计用户 #{@token}",
        email: @viewer.email,
        active: "1",
        role_ids: [Role.find_by!(code: "auditor").id]
      }
    }

    assert_redirected_to "/admin/users/#{@viewer.id}"
    assert_equal "审计用户 #{@token}", @viewer.reload.name
  end

  test "super admin can generate and revoke user api key" do
    sign_in_as(@admin)

    assert_difference "UserApiKey.where(user: @viewer).count", 1 do
      post "/admin/users/#{@viewer.id}/api_keys", params: { api_key: { name: "AI" } }, headers: { "Accept" => "text/html" }
    end

    api_key = UserApiKey.where(user: @viewer).order(:created_at).last
    assert_redirected_to "/admin/users/#{@viewer.id}"
    assert_match(/mcp_/, flash[:notice])
    assert_nil api_key.revoked_at

    sign_in_as(@admin)
    patch "/admin/users/#{@viewer.id}/api_keys/#{api_key.id}/revoke", headers: { "Accept" => "text/html" }

    assert_redirected_to "/admin/users/#{@viewer.id}"
    assert UserApiKey.find(api_key.id).revoked_at.present?
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

  def with_stubbed_sub2_provisioning
    original_call = Sub2UserApiKeyProvisioner.method(:call)
    Sub2UserApiKeyProvisioner.define_singleton_method(:call) do |user:, **|
      Sub2UserApiKey.create!(
        user: user,
        remote_key_id: "remote-#{user.id}",
        encrypted_api_key: Sub2UserApiKey.encrypt("sk-sub2-#{user.id}"),
        name: "eshop-user-#{user.id}"
      )
    end
    yield
  ensure
    Sub2UserApiKeyProvisioner.define_singleton_method(:call, original_call)
  end
end
