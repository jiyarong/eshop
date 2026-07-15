require "test_helper"

class UserRolePermissionsTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4)
  end

  teardown do
    if defined?(UserRole)
      UserRole.joins(:user).where(users: { email: ["multi-#{@token}@example.com", "viewer-#{@token}@example.com"] }).delete_all
    end
    User.where(email: ["multi-#{@token}@example.com", "viewer-#{@token}@example.com"]).delete_all if defined?(User)
  end

  test "user can hold multiple business roles and inherits permissions from all roles" do
    user = User.create!(email: "multi-#{@token}@example.com", password: "password123", password_confirmation: "password123")
    user.roles << Role.find_by!(code: "sku_manager")
    user.roles << Role.find_by!(code: "finance")

    assert user.has_role?("sku_manager")
    assert user.has_role?("finance")
    assert user.can?(:manage_skus)
    assert user.can?(:manage_finance)
    assert_not user.can?(:manage_users)
  end

  test "unknown role has no permissions" do
    role = Role.new(code: "product_dev")

    assert_empty role.permissions
    assert_not role.allows?(:view_reports)
  end

  test "inactive user cannot authenticate" do
    user = User.create!(
      email: "viewer-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123",
      active: false
    )

    assert_not user.active_for_authentication?
  end
end
