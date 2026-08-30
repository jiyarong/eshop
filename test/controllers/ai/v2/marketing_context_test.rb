require "test_helper"

class ErpAI::V2::MarketingContextControllerTest < ActionDispatch::IntegrationTest
  setup do
    token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("ai-v2-marketing-context-#{token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "V2 Marketing Context")
    @sku = Ec::Sku.create!(
      sku_code: "V2-MARKETING-#{token}",
      product_name: "Marketing context SKU",
      product_name_ru: "Маркетинговый SKU"
    )
  end

  teardown do
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "returns a compact marketing context for a completed week and normalizes the SKU code" do
    get "/ai/v2/skus/marketing_context",
      params: {
        sku_code: "  #{@sku.sku_code.downcase}  ",
        period_from: "2026-08-03",
        period_to: "2026-08-09"
      },
      headers: bearer_headers

    assert_response :success

    data = response.parsed_body.fetch("data")
    assert_equal 1, data.fetch("schema_version")
    assert_equal(
      {
        "from" => "2026-08-03",
        "to" => "2026-08-09",
        "week_starts_on" => "monday"
      },
      data.fetch("period").slice("from", "to", "week_starts_on")
    )
    assert_equal @sku.sku_code, data.dig("sku", "sku_code")
    assert_equal "Marketing context SKU", data.dig("sku", "product_name")
    assert_equal "Маркетинговый SKU", data.dig("sku", "product_name_ru")
    assert_equal [], data.dig("sku", "listings")
    assert_equal 1, data.dig("profitability", "weekly").size
    assert_equal "2026-08-03", data.dig("profitability", "weekly", 0, "period_from")
    assert_equal "2026-08-09", data.dig("profitability", "weekly", 0, "period_to")
    assert_equal 1, data.dig("channel_performance", "weekly").size
    assert_equal [], data.dig("channel_performance", "weekly", 0, "channels")
    assert_equal [], data.dig("inventory", "by_channel")
    assert_equal 1, data.dig("inventory", "weekly_snapshots").size
    assert_equal 0, data.dig("operations", "summary", "total_count")
    assert_equal [], data.dig("operations", "recent")

    assert_not data.key?("ec_orders_full_period")
    assert_not data.key?("supply_orders_full_period")
    assert_not data.key?("current_inventory_info")
    assert_not data.key?("history_inventory_info")
  end

  test "defaults to the last four completed natural weeks" do
    travel_to Time.utc(2026, 8, 27, 12) do
      get "/ai/v2/skus/marketing_context",
        params: { sku_code: @sku.sku_code },
        headers: bearer_headers
    end

    assert_response :success

    data = response.parsed_body.fetch("data")
    assert_equal "2026-08-27", data.dig("period", "as_of")
    assert_equal({ "from" => "2026-07-27", "to" => "2026-08-23" }, data.fetch("period").slice("from", "to"))
    assert_equal 4, data.dig("profitability", "weekly").size
    assert_equal 4, data.dig("channel_performance", "weekly").size
    assert_equal 4, data.dig("inventory", "weekly_snapshots").size
  end

  test "requires authentication" do
    get "/ai/v2/skus/marketing_context", params: { sku_code: @sku.sku_code }

    assert_response :unauthorized
  end

  test "uses the API user's time zone for the default completed weeks" do
    @user.update!(time_zone: "UTC")

    travel_to Time.utc(2026, 8, 30, 23) do
      get "/ai/v2/skus/marketing_context",
        params: { sku_code: @sku.sku_code },
        headers: bearer_headers
    end

    assert_response :success
    assert_equal "2026-08-30", response.parsed_body.dig("data", "period", "as_of")
    assert_equal "2026-08-23", response.parsed_body.dig("data", "period", "to")
  end

  test "treats the current Sunday as an incomplete week" do
    travel_to Time.utc(2026, 8, 23, 3) do
      get "/ai/v2/skus/marketing_context",
        params: {
          sku_code: @sku.sku_code,
          period_from: "2026-08-17",
          period_to: "2026-08-23"
        },
        headers: bearer_headers
    end

    assert_response :success
    data = response.parsed_body.fetch("data")
    assert_equal true, data.dig("channel_performance", "weekly", 0, "is_partial")
    assert_equal "partial_week", data.dig("profitability", "weekly", 0, "data_status")
  end

  test "rejects a period longer than twelve weeks" do
    get "/ai/v2/skus/marketing_context",
      params: { sku_code: @sku.sku_code, period_from: "2026-05-25", period_to: "2026-08-23" },
      headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "period_too_long", response.parsed_body.fetch("error")
  end

  test "rejects periods extending beyond the current natural week" do
    travel_to Time.utc(2026, 8, 27, 12) do
      get "/ai/v2/skus/marketing_context",
        params: {
          sku_code: @sku.sku_code,
          period_from: "2026-08-24",
          period_to: "2026-09-06"
        },
        headers: bearer_headers
    end

    assert_response :unprocessable_entity
    assert_equal "future_period_unsupported", response.parsed_body.fetch("error")
  end

  test "rejects a future complete week" do
    travel_to Time.utc(2026, 8, 27, 12) do
      get "/ai/v2/skus/marketing_context",
        params: {
          sku_code: @sku.sku_code,
          period_from: "2026-08-31",
          period_to: "2026-09-06"
        },
        headers: bearer_headers
    end

    assert_response :unprocessable_entity
    assert_equal "future_period_unsupported", response.parsed_body.fetch("error")
  end

  test "requires a SKU and both period dates when either date is provided" do
    get "/ai/v2/skus/marketing_context", headers: bearer_headers

    assert_response :bad_request
    assert_equal "sku_code is required", response.parsed_body.fetch("error")

    get "/ai/v2/skus/marketing_context",
      params: { sku_code: @sku.sku_code, period_from: "2026-08-03" },
      headers: bearer_headers

    assert_response :bad_request
    assert_equal "period_to is required", response.parsed_body.fetch("error")

    get "/ai/v2/skus/marketing_context",
      params: { sku_code: @sku.sku_code, period_from: "", period_to: "" },
      headers: bearer_headers

    assert_response :bad_request
    assert_equal "period_from is required", response.parsed_body.fetch("error")

    get "/ai/v2/skus/marketing_context",
      params: { sku_code: "   " },
      headers: bearer_headers

    assert_response :bad_request
    assert_equal "sku_code is required", response.parsed_body.fetch("error")
  end

  test "reports invalid dates and unknown SKUs" do
    get "/ai/v2/skus/marketing_context",
      params: { sku_code: @sku.sku_code, period_from: "bad", period_to: "2026-08-09" },
      headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "invalid_date", response.parsed_body.fetch("error")

    get "/ai/v2/skus/marketing_context",
      params: { sku_code: "MISSING-#{SecureRandom.hex(4)}" },
      headers: bearer_headers

    assert_response :not_found
    assert_equal "SKU not found", response.parsed_body.fetch("error")
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end
end
