require "test_helper"

class Erp::SkuMarketingStatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @manager = create_user_with_roles("marketing-manager-#{@token.downcase}@example.com", "sku_manager")
    @viewer = create_user_with_roles("marketing-viewer-#{@token.downcase}@example.com", "operator")
    @sku = Ec::Sku.create!(sku_code: "MARKETING-PAGE-#{@token}", product_name: "营销状态页面 SKU")
  end

  teardown do
    state_ids = Ec::SkuMarketingState.where(sku_id: @sku.id).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuMarketingState", record_id: state_ids).delete_all
    Ec::SkuMarketingState.where(id: state_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    UserRole.where(user_id: [ @manager.id, @viewer.id ]).delete_all
    User.where(id: [ @manager.id, @viewer.id ]).delete_all
  end

  test "new renders turbo form and history" do
    sign_in @manager
    existing = create_state(grade: "B", stage: "new", note: "验证需求")

    get new_erp_sku_marketing_state_path(@sku), params: { return_to: "/erp/skus?status=active" }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select "h2", "调整 #{@sku.sku_code} 营销状态"
    assert_select "form[action=?][data-turbo-frame='_top']", erp_sku_marketing_states_path(@sku)
    assert_select "input[type='hidden'][name='return_to'][value=?]", "/erp/skus?status=active"
    assert_select "select[name='ec_sku_marketing_state[grade]'] option[selected='selected'][value='B']"
    assert_select "select[name='ec_sku_marketing_state[stage]'] option[selected='selected'][value='new']"
    assert_select ".sku-marketing-history__table tbody tr", 1
    assert_select ".marketing-grade--b", "B"
    assert_select "td", existing.note
  end

  test "create records current state and redirects to safe return path" do
    sign_in @manager
    assert_difference "Ec::SkuMarketingState.count", 1 do
      post erp_sku_marketing_states_path(@sku), params: {
        return_to: "/erp/skus?status=active",
        ec_sku_marketing_state: { grade: "A", stage: "grw", note: "开始增长" }
      }
    end

    state = @sku.reload.current_marketing_state
    assert_redirected_to "/erp/skus?status=active"
    assert_equal [ "A", "grw", "开始增长" ], [ state.grade, state.stage, state.note ]
    assert_equal @manager, state.changed_by
  end

  test "invalid create rerenders modal without closing current state" do
    sign_in @manager
    existing = create_state(grade: "A", stage: "new")

    post erp_sku_marketing_states_path(@sku), params: {
      ec_sku_marketing_state: { grade: "D", stage: "grw" }
    }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#erp_modal"
    assert_select ".error-box"
    assert_nil existing.reload.ended_at
  end

  test "viewer can read history" do
    create_state(grade: "C", stage: "clr")
    sign_in @viewer

    get erp_sku_marketing_states_path(@sku), headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select ".marketing-grade--c", "C"
    assert_select "td", "清库"
  end

  test "viewer cannot open adjustment" do
    sign_in @viewer

    get new_erp_sku_marketing_state_path(@sku), headers: { "Accept" => "text/html" }
    assert_response :forbidden
  end

  test "viewer cannot submit adjustment" do
    sign_in @viewer

    post erp_sku_marketing_states_path(@sku), params: { ec_sku_marketing_state: { grade: "S", stage: "new" } }
    assert_response :forbidden
  end

  test "exceptional combination renders a warning" do
    sign_in @manager
    create_state(grade: "S", stage: "clr")

    get erp_sku_marketing_states_path(@sku), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td.sku-marketing-history__warning", "原则上不存在"
  end

  private

  def create_state(grade:, stage:, note: nil)
    Ec::SkuMarketingStateChange.new(
      sku: @sku, grade: grade, stage: stage, changed_by: @manager, note: note
    ).call
  end
end
