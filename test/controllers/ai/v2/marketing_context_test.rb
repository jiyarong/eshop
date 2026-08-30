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

  test "returns the requested recent weeks and normalizes the SKU code" do
    travel_to Time.utc(2026, 8, 13, 12) do
      get "/ai/v2/skus/marketing_context",
        params: { sku_code: "  #{@sku.sku_code.downcase}  ", weeks: 1 },
        headers: bearer_headers
    end

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

  test "accepts up to twelve completed natural weeks" do
    travel_to Time.utc(2026, 8, 27, 12) do
      get "/ai/v2/skus/marketing_context",
        params: { sku_code: @sku.sku_code, weeks: 12 },
        headers: bearer_headers
    end

    assert_response :success
    data = response.parsed_body.fetch("data")
    assert_equal({ "from" => "2026-06-01", "to" => "2026-08-23" }, data.fetch("period").slice("from", "to"))
    assert_equal 12, data.dig("profitability", "weekly").size
    assert_equal 12, data.dig("channel_performance", "weekly").size
    assert_equal 12, data.dig("inventory", "weekly_snapshots").size
  end

  test "rejects invalid week counts" do
    [ 0, 13, "1.5", "bad", "" ].each do |weeks|
      get "/ai/v2/skus/marketing_context",
        params: { sku_code: @sku.sku_code, weeks: weeks },
        headers: bearer_headers

      assert_response :unprocessable_entity
      assert_equal "invalid_weeks", response.parsed_body.fetch("error")
    end
  end

  test "requires a SKU" do
    get "/ai/v2/skus/marketing_context", headers: bearer_headers

    assert_response :bad_request
    assert_equal "sku_code is required", response.parsed_body.fetch("error")

    get "/ai/v2/skus/marketing_context",
      params: { sku_code: "   " },
      headers: bearer_headers

    assert_response :bad_request
    assert_equal "sku_code is required", response.parsed_body.fetch("error")
  end

  test "rejects the removed period parameters" do
    get "/ai/v2/skus/marketing_context",
      params: { sku_code: @sku.sku_code, period_from: "2026-08-03", period_to: "2026-08-09" },
      headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "unsupported_period_parameters", response.parsed_body.fetch("error")
  end

  test "reports unknown SKUs" do
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
