require "test_helper"

class Erp::RolePermissionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @viewer = create_user_with_roles("viewer-#{@token}@example.com", "auditor")
    @sku_manager = create_user_with_roles("sku-manager-#{@token}@example.com", "sku_manager")
  end

  teardown do
    Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token.upcase}%").delete_all
    if defined?(UserRole)
      UserRole.joins(:user).where("users.email LIKE ?", "%#{@token}%").delete_all
    end
    User.where("email LIKE ?", "%#{@token}%").delete_all if defined?(User)
  end

  test "read only role can view erp pages" do
    sign_in_as(@viewer)

    get "/erp/skus", headers: { "Accept" => "text/html" }

    assert_response :success
  end

  test "read only role cannot create sku" do
    sign_in_as(@viewer)

    post "/erp/skus", params: {
      ec_sku: {
        sku_code: "DENIED-#{@token}",
        product_name: "禁止创建"
      }
    }

    assert_response :forbidden
  end

  test "sku manager can create sku" do
    sign_in_as(@sku_manager)

    assert_difference "Ec::Sku.count", 1 do
      post "/erp/skus", params: {
        ec_sku: {
          sku_code: "ALLOWED-#{@token}",
          product_name: "允许创建"
        }
      }
    end
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
