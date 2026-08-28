require "test_helper"

class ErpAI::V2::SkusControllerTest < ActionDispatch::IntegrationTest
  setup do
    token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("ai-v2-full-context-#{token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "V2 Full Context")
    @master_sku = Ec::MasterSku.create!(master_sku_code: "V2-SPU-#{token}")
    @sku = Ec::Sku.create!(
      sku_code: "V2-CONTEXT-#{token}",
      product_name: "V2 full context",
      master_sku: @master_sku
    )
    @related_sku = Ec::Sku.create!(
      sku_code: "V2-RELATED-#{token}",
      product_name: "V2 related SKU",
      master_sku: @master_sku
    )
    @marketing_state = @sku.marketing_states.create!(
      grade: "A",
      stage: "grw",
      effective_at: 1.day.ago,
      changed_by: @user
    )
    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "V2 full context #{token}",
      company_type: "general"
    )
    @sku_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @store,
      product_id: "V2-PRODUCT-#{token}",
      offer_id: "V2-OFFER-#{token}"
    )
    @inventory_snapshot = Ec::Snapshot.create!(
      sku: @sku,
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: Date.new(2026, 8, 8),
      content: {
        overview: { book_stock: 12, platform_stock: 7, raw_payload: { oversized: true } },
        raw_json: { oversized: true }
      }
    )
    @outside_inventory_snapshot = Ec::Snapshot.create!(
      sku: @sku,
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: Date.new(2026, 7, 31),
      content: { overview: { book_stock: 99 } }
    )
    @created_weekly_rates = %w[2026-07-27 2026-08-03 2026-08-10 2026-08-17].filter_map do |week_start|
      next if Ec::WeeklyRate.exists?(week_start: week_start)

      Ec::WeeklyRate.create!(week_start: week_start, rate_cny_rub: 12.0, rate_byn_rub: 27.0)
    end
  end

  teardown do
    Ec::Snapshot.where(id: [@inventory_snapshot&.id, @outside_inventory_snapshot&.id]).delete_all
    Ec::WeeklyRate.where(id: @created_weekly_rates&.map(&:id)).delete_all
    Ec::SkuProduct.where(id: @sku_product&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::SkuMarketingState.where(id: @marketing_state&.id).delete_all
    Ec::Sku.with_deleted.where(id: @related_sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    Ec::MasterSku.where(id: @master_sku&.id).delete_all
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "returns an empty context for a complete natural-week period" do
    get "/ai/v2/skus/full_context",
      params: {
        sku_code: @sku.sku_code.downcase,
        period_from: "2026-08-03",
        period_to: "2026-08-16"
      },
      headers: bearer_headers

    assert_response :success
    assert_equal @sku.sku_code, response.parsed_body.dig("data", "sku_code")
    assert_equal({ "from" => "2026-08-03", "to" => "2026-08-16" }, response.parsed_body.dig("data", "period"))
    assert_equal(
      {
        "spu_code" => @master_sku.master_sku_code,
        "spu_id" => @master_sku.id,
        "related_spu_sku_codes" => [@related_sku.sku_code],
        "current_stage" => "GRW",
        "current_grade" => "A",
        "sku_products" => [
          {
            "store_id" => @store.id,
            "platform" => "ozon",
            "product_id" => @sku_product.product_id,
            "offer_id" => @sku_product.offer_id,
            "product_info" => nil,
            "price_info" => nil
          }
        ]
      },
      response.parsed_body.dig("data", "context", "base")
    )
    weekly_profit = response.parsed_body.dig("data", "context", "weekly_profit_per_week")
    assert_equal 2, weekly_profit.fetch("wr").size
    assert_equal 2, weekly_profit.fetch("wsu").size
    assert_equal 2, weekly_profit.fetch("wsu_deep").size
    assert_equal(
      { "period_from" => "2026-07-27", "period_to" => "2026-08-02" },
      weekly_profit.fetch("wsu").first.slice("period_from", "period_to")
    )
    assert_equal(
      { "period_from" => "2026-08-03", "period_to" => "2026-08-09" },
      weekly_profit.fetch("wsu").last.slice("period_from", "period_to")
    )
    sales_funnel = response.parsed_body.dig("data", "context", "sales_funnel_per_week")
    assert_equal 2, sales_funnel.size
    assert_equal(
      { "period_from" => "2026-08-03", "period_to" => "2026-08-09" },
      sales_funnel.first.slice("period_from", "period_to")
    )
    assert_equal(
      { "period_from" => "2026-08-10", "period_to" => "2026-08-16" },
      sales_funnel.last.slice("period_from", "period_to")
    )
    advertising = response.parsed_body.dig("data", "context", "advertise_per_week")
    assert_equal 2, advertising.size
    assert_equal(
      { "period_from" => "2026-08-03", "period_to" => "2026-08-09" },
      advertising.first.slice("period_from", "period_to")
    )
    assert_equal(
      { "period_from" => "2026-08-10", "period_to" => "2026-08-16" },
      advertising.last.slice("period_from", "period_to")
    )
    assert_equal [], response.parsed_body.dig("data", "context", "ec_orders_full_period")
    assert_equal [], response.parsed_body.dig("data", "context", "supply_orders_full_period")
    assert_equal [], response.parsed_body.dig("data", "context", "operation_actions_full_period")
    search_terms = response.parsed_body.dig("data", "context", "search_terms_per_week")
    assert_equal 2, search_terms.size
    assert_equal(
      { "period_from" => "2026-08-03", "period_to" => "2026-08-09" },
      search_terms.first.slice("period_from", "period_to")
    )
    assert_equal(
      { "period_from" => "2026-08-10", "period_to" => "2026-08-16" },
      search_terms.last.slice("period_from", "period_to")
    )
    current_inventory = response.parsed_body.dig("data", "context", "current_inventory_info")
    assert_equal @sku.sku_code, current_inventory.dig("list", "sku_code")
    assert_equal @sku.sku_code, current_inventory.dig("detail", "sku_code")
    assert_equal(
      [
        {
          "snapshot_date" => "2026-08-08",
          "content" => { "overview" => { "book_stock" => 12, "platform_stock" => 7 } }
        }
      ],
      response.parsed_body.dig("data", "context", "history_inventory_info")
    )
  end

  test "defaults to the current and previous three natural weeks" do
    travel_to Time.utc(2026, 8, 27, 12) do
      get "/ai/v2/skus/full_context",
        params: { sku_code: @sku.sku_code },
        headers: bearer_headers
    end

    assert_response :success
    assert_equal({ "from" => "2026-08-03", "to" => "2026-08-30" }, response.parsed_body.dig("data", "period"))
    profit_weeks = response.parsed_body.dig("data", "context", "weekly_profit_per_week", "wsu")
    assert_equal 4, profit_weeks.size
    assert_equal "2026-07-27", profit_weeks.first.fetch("period_from")
    assert_equal "2026-08-23", profit_weeks.last.fetch("period_to")
    funnel_weeks = response.parsed_body.dig("data", "context", "sales_funnel_per_week")
    assert_equal 4, funnel_weeks.size
    assert_equal "2026-08-03", funnel_weeks.first.fetch("period_from")
    assert_equal "2026-08-30", funnel_weeks.last.fetch("period_to")
    advertising_weeks = response.parsed_body.dig("data", "context", "advertise_per_week")
    assert_equal 4, advertising_weeks.size
    assert_equal "2026-08-03", advertising_weeks.first.fetch("period_from")
    assert_equal "2026-08-30", advertising_weeks.last.fetch("period_to")
    assert_equal true, advertising_weeks.last.fetch("is_partial")
  end

  test "requires authentication" do
    get "/ai/v2/skus/full_context",
      params: { sku_code: @sku.sku_code, period_from: "2026-08-03", period_to: "2026-08-09" }

    assert_response :unauthorized
  end

  test "requires period_to when period_from is provided" do
    get "/ai/v2/skus/full_context",
      params: { sku_code: @sku.sku_code, period_from: "2026-08-03" },
      headers: bearer_headers

    assert_response :bad_request
    assert_equal "period_to is required", response.parsed_body.fetch("error")
  end

  test "rejects a period that does not start on Monday" do
    get "/ai/v2/skus/full_context",
      params: { sku_code: @sku.sku_code, period_from: "2026-08-04", period_to: "2026-08-09" },
      headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "period_from_must_be_monday", response.parsed_body.fetch("error")
  end

  test "rejects a period that does not end on Sunday" do
    get "/ai/v2/skus/full_context",
      params: { sku_code: @sku.sku_code, period_from: "2026-08-03", period_to: "2026-08-15" },
      headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "period_to_must_be_sunday", response.parsed_body.fetch("error")
  end

  test "rejects an invalid date" do
    get "/ai/v2/skus/full_context",
      params: { sku_code: @sku.sku_code, period_from: "bad", period_to: "2026-08-09" },
      headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "invalid_date", response.parsed_body.fetch("error")
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end

end
