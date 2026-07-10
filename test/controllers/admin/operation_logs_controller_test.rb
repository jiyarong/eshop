require "test_helper"

class Admin::OperationLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @admin = create_user_with_roles("operation-log-admin-#{@token}@example.com", "super_admin")
    @viewer = create_user_with_roles("operation-log-viewer-#{@token}@example.com", "auditor")
    @other_user = create_user_with_roles("operation-log-other-#{@token}@example.com", "manager")
    @admin.update!(name: "操作管理员 #{@token}")
    @other_user.update!(name: "操作用户 #{@token}")
    @sku_log = Ec::OperationLog.create!(
      user: @admin,
      record_type: "Ec::Sku",
      record_id: 10_001,
      action: "update",
      changeset: [
        { field: "product_name", from: "旧商品 #{@token}", to: "新商品 #{@token}" },
        { field: "memo", from: nil, to: "补充备注 #{@token}" }
      ],
      created_at: Time.zone.parse("2026-06-30 10:00:00")
    )
    @store_log = Ec::OperationLog.create!(
      user: @other_user,
      record_type: "Ec::Store",
      record_id: 10_002,
      action: "update",
      changeset: [
        { field: "store_name", from: "旧店铺 #{@token}", to: "新店铺 #{@token}" }
      ],
      created_at: Time.zone.parse("2026-06-29 10:00:00")
    )
  end

  teardown do
    Ec::OperationLog.where(id: [@sku_log&.id, @store_log&.id]).delete_all if defined?(Ec::OperationLog)
    UserRole.where(user: [@admin, @viewer, @other_user]).delete_all
    User.where(id: [@admin.id, @viewer.id, @other_user.id]).delete_all
  end

  test "super admin can view operation history from administration navigation" do
    sign_in @admin

    get "/admin/operation_logs", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "操作历史"
    assert_select ".erp-nav__link[href='/admin/operation_logs'][aria-current='page']", text: "操作历史"
    assert_select "form[action='/admin/operation_logs'][method='get']"
    assert_select "select[name='user_id'] option[value='#{@admin.id}']", text: @admin.name
    assert_select "select[name='record_type'] option[value='Ec::Sku']", text: "SKU"
    assert_select "input[name='from_date'][type='date']"
    assert_select "input[name='to_date'][type='date']"
    assert_includes response.body, @admin.name
    assert_includes response.body, "SKU"
    assert_includes response.body, "更新"
    assert_select ".operation-log-change", text: /product_name/
    assert_includes response.body, "旧商品 #{@token}"
    assert_includes response.body, "新商品 #{@token}"
  end

  test "filters operation history by user model and date" do
    sign_in @admin

    get "/admin/operation_logs", params: {
      user_id: @admin.id,
      record_type: "Ec::Sku",
      from_date: "2026-06-30",
      to_date: "2026-06-30"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_match "新商品 #{@token}", response.body
    assert_no_match "新店铺 #{@token}", response.body
    assert_select "select[name='user_id'] option[selected='selected'][value='#{@admin.id}']"
    assert_select "select[name='record_type'] option[selected='selected'][value='Ec::Sku']"
    assert_select "input[name='from_date'][value='2026-06-30']"
    assert_select "input[name='to_date'][value='2026-06-30']"
  end

  test "non admin cannot view operation history" do
    sign_in @viewer

    get "/admin/operation_logs", headers: { "Accept" => "text/html" }

    assert_response :forbidden
  end
end
