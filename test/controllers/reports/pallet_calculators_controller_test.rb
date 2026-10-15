require "test_helper"

class Reports::PalletCalculatorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    token = SecureRandom.hex(5)
    @user = create_user_with_roles("pallet-#{token}@example.com", "manager")
    @sku = Ec::Sku.create!(sku_code: "PALLET-#{token}", product_name: "Pallet test")
    @hidden_sku = Ec::Sku.create!(sku_code: "PALLET-HIDDEN-#{token}")
    @assignment = Ec::SkuOperatorAssignment.create!(user: @user, sku_code: @sku.sku_code)
    @dimension = Ec::SkuDimension.create!(sku_code: @sku.sku_code,
      outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 10, outer_box_pcs: 4,
      inner_length_cm: 10, inner_width_cm: 10, inner_height_cm: 10)
    sign_in @user
  end

  teardown do
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: [@sku.id, @hidden_sku.id]).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuDimension", record_id: @dimension.id).delete_all
    @assignment.destroy!
    @dimension.delete
    @sku.delete
    @hidden_sku.delete
    UserRole.where(user_id: @user.id).delete_all
    @user.destroy!
  end

  test "renders independent tool with shared picker in every supported language" do
    %w[zh en ru].each do |locale|
      sign_in @user
      get reports_pallet_calculator_path, params: { locale: locale }
      assert_response :success
      assert_select "[data-controller=spu-sku-filter]", 1
      assert_select "select#pallet-profile option", 4
      assert_select "template[data-pallet-calculator-target=rowTemplate]", 1
      assert_select "turbo-frame#pallet_calculator_results", 1
      assert_no_match(/translation missing/i, response.body)
      assert_not_includes response.body, @hidden_sku.sku_code
    end
  end

  test "catalogue exposes only visible SKU packaging and does not write data" do
    assert_no_difference("Ec::SkuDimension.count") do
      get reports_pallet_calculator_path(format: :json)
    end
    assert_response :success
    rows = response.parsed_body.fetch("skus")
    assert_equal [@sku.sku_code], rows.map { |row| row["sku_code"] }
    assert_equal "40.0", rows.first["length"]
    assert_equal 4, rows.first["pcs"]
    assert_equal "1.0", rows.first["unit_volume_l"]
  end

  test "returns calculated JSON without updating SKU packaging" do
    post calculate_reports_pallet_calculator_path(format: :json), params: calculation_params
    assert_response :success
    assert_equal 2, response.parsed_body["total_boxes"]
    assert_equal 8, response.parsed_body["total_units"]
    assert_equal 40, @dimension.reload.outer_length_cm
  end

  test "renders visual result and warehouse handoff in every locale" do
    %w[zh en ru].each do |locale|
      sign_in @user
      post calculate_reports_pallet_calculator_path, params: calculation_params.merge(locale: locale, format: :html)
      assert_response :success
      assert_select "svg[role=img]", 2
      assert_select "[data-controller=clipboard] pre", text: /#{Regexp.escape(@sku.sku_code)}/
      assert_no_match(/translation missing/i, response.body)
    end
  end

  test "rejects inaccessible SKU and invalid measurements with a useful 422" do
    params = calculation_params
    params[:items][0][:sku_code] = @hidden_sku.sku_code
    post calculate_reports_pallet_calculator_path(format: :json), params: params
    assert_response :unprocessable_entity
    assert response.parsed_body["error"].present?

    params = calculation_params
    params[:items][0][:weight] = 0
    sign_in @user
    post calculate_reports_pallet_calculator_path(format: :html), params: params
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /#{Regexp.escape(@sku.sku_code)}/
  end

  test "requires report permission for catalogue and calculation" do
    sign_out @user
    get reports_pallet_calculator_path(format: :json)
    assert_response :forbidden
    post calculate_reports_pallet_calculator_path(format: :json), params: calculation_params
    assert_response :forbidden
  end

  private

  def calculation_params
    { profile: "ozon_fbo", settings: { route_rate: 8 }, items: [{ sku_code: @sku.sku_code, length: 40, width: 30, height: 20, weight: 10, pcs: 4, unit_volume_l: 1, quantity: 2 }] }
  end
end
