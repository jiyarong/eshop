require "test_helper"

class ErpAI::StageInspectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("stage-score-api-#{@token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "Stage Inspector")
  end

  teardown do
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "returns server-calculated stage scores" do
    observations = (1..6).map do |index|
      { status: "valid", net_sales: index * 10, after_tax: index * 100,
        annualized_return_pct: 80, average_profit_per_order: 10,
        ad_ratio_pct: 10, margin_pct: 10 }
    end

    post "/ai/stage_inspections", params: { window_type: "standard", observations: observations }, headers: bearer_headers, as: :json

    assert_response :success
    assert_equal "GRW", response.parsed_body.dig("data", "diagnosed_stage")
    assert response.parsed_body.dig("data", "g").is_a?(Numeric)
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end
end
