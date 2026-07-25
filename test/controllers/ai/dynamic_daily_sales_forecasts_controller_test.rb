require "test_helper"

class ErpAI::DynamicDailySalesForecastsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("ai-daily-forecast-#{@token.downcase}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "Daily Forecast Agent")
    @sku = Ec::Sku.create!(sku_code: "AI-FORECAST-#{@token}", product_name: "AI forecast #{@token}")
    @sku.marketing_states.create!(
      grade: "A",
      stage: "grw",
      effective_at: 1.day.ago,
      changed_by: @user
    )
  end

  teardown do
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all
    Ec::SkuMarketingState.where(sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserApiKey.where(user: @user).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "returns dynamic daily sales forecast" do
    date_to = Ec::Snapshot.current_date - 1
    rows = 7.times.map do |index|
      {
        snapshot_type: Ec::InventorySnapshot.snapshot_type,
        snapshot_date: date_to - (6 - index).days,
        sku_id: @sku.id,
        content: { overview: { daily_sales: 4, out_of_stock: false } }
      }
    end
    Ec::Snapshot.insert_all!(rows)

    get "/ai/skus/dynamic_daily_sales_forecast",
      params: { sku: @sku.sku_code.downcase },
      headers: bearer_headers

    assert_response :success
    data = response.parsed_body.fetch("data")
    assert_equal @sku.sku_code, data.fetch("sku")
    assert_equal "GRW", data.fetch("marketing_stage")
    assert_equal 4.0, data.fetch("forecast_daily_sales")
    assert_equal "cold_start", data.dig("calculation", "path")
    assert_match "S7", response.parsed_body.fetch("description")
  end

  test "requires sku parameter" do
    get "/ai/skus/dynamic_daily_sales_forecast", headers: bearer_headers

    assert_response :bad_request
    assert_equal({ "error" => "sku is required" }, response.parsed_body)
  end

  test "returns not found for unknown sku" do
    get "/ai/skus/dynamic_daily_sales_forecast",
      params: { sku: "MISSING-#{@token}" },
      headers: bearer_headers

    assert_response :not_found
    assert_equal({ "error" => "SKU not found" }, response.parsed_body)
  end

  test "requires api key" do
    get "/ai/skus/dynamic_daily_sales_forecast", params: { sku: @sku.sku_code }

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end
end
