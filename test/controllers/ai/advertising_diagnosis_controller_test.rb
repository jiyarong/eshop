require "test_helper"

class ErpAI::AdvertisingDiagnosisControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("advertising-diagnosis-#{@token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "Advertising Inspector")
    @sku = Ec::Sku.create!(sku_code: "AD-API-#{@token}", product_name: "Advertising API", is_active: true)
  end

  teardown do
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "returns read only advertising diagnosis data" do
    assert_no_changes -> { Ec::Sku.find(@sku.id).updated_at } do
      get "/ai/skus/advertising_diagnosis",
        params: { sku: @sku.sku_code, from_date: "2026-08-03", to_date: "2026-08-09" },
        headers: bearer_headers
    end

    assert_response :success
    assert_equal @sku.sku_code, response.parsed_body.dig("data", "sku")
    assert_equal({ "from_date" => "2026-08-03", "to_date" => "2026-08-09" }, response.parsed_body.dig("data", "period"))
    assert_match "只读数据", response.parsed_body.fetch("description")
  end

  test "rejects invalid dates" do
    get "/ai/skus/advertising_diagnosis", params: { sku: @sku.sku_code, from_date: "bad" }, headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "invalid_date", response.parsed_body.fetch("error")
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end
end
