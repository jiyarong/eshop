require "test_helper"

class WeeklyProfitReports::AccessScopeTest < ActiveSupport::TestCase
  setup do
    token = SecureRandom.hex(5).upcase
    @user = create_user("weekly-access-#{token}@example.com")
    @other_user = create_user("weekly-access-other-#{token}@example.com")
    @admin = create_user("weekly-access-admin-#{token}@example.com")
    @spu = Ec::MasterSku.create!(master_sku_code: "WEEKLY-ACCESS-SPU-#{token}", product_name: "Access SPU")
    @developer_sku = Ec::Sku.create!(sku_code: "WEEKLY-ACCESS-DEV-#{token}", master_sku: @spu)
    @operator_sku = Ec::Sku.create!(sku_code: "WEEKLY-ACCESS-OP-#{token}", master_sku: @spu)
    @hidden_sku = Ec::Sku.create!(sku_code: "WEEKLY-ACCESS-HIDDEN-#{token}")
    @user.roles << Role.find_by!(code: "manager")
    @admin.roles << Role.find_by!(code: "super_admin")
    Ec::SkuDeveloperAssignment.create!(sku_code: @developer_sku.sku_code, user: @user)
    Ec::SkuOperatorAssignment.create!(sku_code: @operator_sku.sku_code, user: @user)
    Ec::SkuOperatorAssignment.create!(sku_code: @hidden_sku.sku_code, user: @other_user)
  end

  teardown do
    codes = [@developer_sku, @operator_sku, @hidden_sku].filter_map { |sku| sku&.sku_code }
    Ec::SkuDeveloperAssignment.where(sku_code: codes).delete_all
    Ec::SkuOperatorAssignment.where(sku_code: codes).delete_all
    Ec::Sku.with_deleted.where(sku_code: codes).delete_all
    Ec::MasterSku.where(id: @spu&.id).delete_all
    UserRole.where(user_id: [@user, @other_user, @admin].filter_map(&:id)).delete_all
    User.where(id: [@user, @other_user, @admin].filter_map(&:id)).delete_all
  end

  test "returns the developer and operator SKU union for a regular user" do
    scope = WeeklyProfitReports::AccessScope.new(@user)

    assert scope.restricted?
    assert_equal [@developer_sku.sku_code, @operator_sku.sku_code].sort, scope.visible_sku_codes.sort
    assert_equal [@spu.id], scope.visible_master_skus.pluck(:id)
    assert_equal [], scope.visible_orphan_skus.pluck(:sku_code)
    assert_equal [@operator_sku.sku_code], scope.intersect_sku_codes([@operator_sku.sku_code, @hidden_sku.sku_code])
  end

  test "super admin access is unrestricted" do
    scope = WeeklyProfitReports::AccessScope.new(@admin)

    assert_not scope.restricted?
    assert_includes scope.visible_sku_codes, @hidden_sku.sku_code
    assert_equal [@hidden_sku.sku_code], scope.intersect_sku_codes([@hidden_sku.sku_code])
  end

  private

  def create_user(email)
    User.create!(email: email, password: "password123", password_confirmation: "password123")
  end
end
