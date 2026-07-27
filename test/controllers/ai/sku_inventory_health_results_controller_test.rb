require "test_helper"

class ErpAI::SkuInventoryHealthResultsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("ai-inventory-health-#{@token}@example.com", "manager")
    @user.update!(name: "AI health submitter #{@token}")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "Inventory Health Agent")
    @sku = Ec::Sku.create!(
      sku_code: "AI-HEALTH-#{@token.upcase}",
      product_name: "AI health test #{@token}",
      is_active: true
    )
  end

  teardown do
    Rails.cache = @previous_cache
    Ec::SkuInventoryHealthResult.where(sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "locks repeated structured inventory health submissions for five seconds" do
    payload = {
      sku: @sku.sku_code.downcase,
      analyzed_at: "2026-07-26T00:00:00+08:00",
      classification: { sabc: "B", staging: "MAT" },
      metrics: { daily_sales: 2.2167, sellable_inventory: 1117 },
      events: [
        {
          type: "insight",
          severity: "info",
          scope: "data_gap",
          message: "缺少下一批预计到达日期",
          details: { missing_field: "next_in_transit_arrival_date" }
        },
        {
          type: "inventory_sufficient",
          severity: "green",
          scope: "total",
          message: "总库存充足",
          details: { turnover_days: 503.9 }
        }
      ]
    }

    assert_difference -> { Ec::SkuInventoryHealthResult.where(sku: @sku).count }, 1 do
      post "/ai/skus/inventory_health_result",
        params: payload,
        headers: bearer_headers,
        as: :json
    end
    assert_response :created

    result = Ec::SkuInventoryHealthResult.where(sku: @sku).recent_first.first
    assert_equal @user, result.submitted_by
    assert_equal Time.iso8601("2026-07-26T00:00:00+08:00"), result.analyzed_at
    assert_equal({ "sabc" => "B", "staging" => "MAT" }, result.classification)
    assert_equal 2.2167, result.metrics.fetch("daily_sales")
    assert_equal "insight", result.events.first.fetch("event_type")
    assert_equal "next_in_transit_arrival_date", result.events.first.dig("details", "missing_field")
    assert_equal 2, response.parsed_body.dig("data", "event_count")
    assert_equal @user.display_name, response.parsed_body.dig("data", "submitted_by")

    assert_no_difference -> { Ec::SkuInventoryHealthResult.where(sku: @sku).count } do
      post "/ai/skus/inventory_health_result",
        params: payload,
        headers: bearer_headers,
        as: :json
    end
    assert_response :too_many_requests
    assert_equal "5", response.headers["Retry-After"]

    travel 6.seconds do
      assert_difference -> { Ec::SkuInventoryHealthResult.where(sku: @sku).count }, 1 do
        post "/ai/skus/inventory_health_result",
          params: payload,
          headers: bearer_headers,
          as: :json
      end
      assert_response :created
    end
  end

  test "locks submissions independently for each sku" do
    other_sku = Ec::Sku.create!(sku_code: "AI-HEALTH-OTHER-#{@token.upcase}", product_name: "Other", is_active: true)

    assert_difference -> { Ec::SkuInventoryHealthResult.count }, 2 do
      [@sku, other_sku].each do |sku|
        post "/ai/skus/inventory_health_result",
          params: event_payload(sku.sku_code),
          headers: bearer_headers,
          as: :json
        assert_response :created
      end
    end
    assert_equal 2, Ec::SkuInventoryHealthResult.where(sku: [@sku, other_sku]).where.not(analyzed_at: nil).count
  ensure
    Ec::SkuInventoryHealthResult.where(sku_id: other_sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: other_sku&.id).delete_all
  end

  test "stores a top level event array as one submission" do
    payload = [
      {
        event_type: "data_missing",
        severity: "info",
        sku: @sku.sku_code.downcase,
        message: "缺少下一批在途预计到达日期",
        details: { missing_fields: ["next_in_transit_arrival_date"] }
      },
      {
        event_type: "inventory_sufficient",
        severity: "green",
        sku: @sku.sku_code,
        message: "未来90天内无预测断货风险",
        details: { turnover_days_with_transit: 503.9 }
      }
    ]

    analyzed_at = Time.zone.parse("2026-07-26 12:34:56")
    travel_to analyzed_at do
      assert_difference -> { Ec::SkuInventoryHealthResult.where(sku: @sku).count }, 1 do
        post "/ai/skus/inventory_health_result",
          params: payload,
          headers: bearer_headers,
          as: :json
      end
    end

    assert_response :created
    result = Ec::SkuInventoryHealthResult.where(sku: @sku).recent_first.first
    assert_equal analyzed_at, result.analyzed_at
    assert_equal({}, result.classification)
    assert_equal ["data_missing", "inventory_sufficient"], result.events.pluck("event_type")
    assert_equal 2, response.parsed_body.dig("data", "event_count")
  end

  test "rejects event arrays containing multiple skus" do
    payload = [
      { event_type: "insight", severity: "info", sku: @sku.sku_code, message: "first" },
      { event_type: "insight", severity: "info", sku: "OTHER-SKU", message: "second" }
    ]

    assert_no_difference -> { Ec::SkuInventoryHealthResult.count } do
      post "/ai/skus/inventory_health_result",
        params: payload,
        headers: bearer_headers,
        as: :json
    end

    assert_response :bad_request
    assert_equal "all events must use the same sku", response.parsed_body.fetch("error")
  end

  test "requires an authenticated api key" do
    post "/ai/skus/inventory_health_result", params: {}, as: :json

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end

  def event_payload(sku_code)
    {
      sku: sku_code,
      events: [{ event_type: "insight", severity: "info", message: "message" }]
    }
  end
end
