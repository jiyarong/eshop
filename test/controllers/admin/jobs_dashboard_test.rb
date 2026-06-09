require "test_helper"
require "propshaft/assembly"

class Admin::JobsDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @admin = create_user_with_roles("jobs-admin-#{@token}@example.com", "super_admin")
    @viewer = create_user_with_roles("jobs-viewer-#{@token}@example.com", "auditor")
    use_dynamic_asset_resolver
  end

  teardown do
    UserRole.joins(:user).where("users.email LIKE ?", "%#{@token}%").delete_all if defined?(UserRole)
    User.where("email LIKE ?", "%#{@token}%").delete_all if defined?(User)
  end

  test "guest cannot access jobs dashboard" do
    get "/admin/jobs", headers: { "Accept" => "text/html" }

    assert_response :redirect
    assert_match "/users/sign_in", response.location
  end

  test "non admin cannot access jobs dashboard" do
    sign_in @viewer

    get "/admin/jobs", headers: { "Accept" => "text/html" }

    assert_response :forbidden
  end

  test "super admin can access jobs dashboard" do
    sign_in @admin

    get "/admin/jobs", headers: { "Accept" => "text/html" }

    assert_response :success
  end

  private

  def use_dynamic_asset_resolver
    Rails.application.config.assets.manifest_path = Rails.root.join("tmp/test-assets/.manifest.json")
    Rails.application.assets = Propshaft::Assembly.new(Rails.application.config.assets)
  end
end
