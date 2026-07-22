require "test_helper"

class ErpAI::WeeklyProfitReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("ai-weekly-profit-#{@token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "Weekly Profit Agent")
    @master_sku = Ec::MasterSku.create!(
      master_sku_code: "AI-WPR-SPU-#{@token.upcase}",
      product_name: "AI Weekly Profit SPU #{@token}"
    )
    @master_sku_child = Ec::Sku.create!(
      sku_code: "AI-WPR-SKU-A-#{@token.upcase}",
      master_sku: @master_sku,
      product_name: "AI Weekly Profit SKU A #{@token}"
    )
    @direct_sku = Ec::Sku.create!(
      sku_code: "AI-WPR-SKU-B-#{@token.upcase}",
      product_name: "AI Weekly Profit SKU B #{@token}"
    )
  end

  teardown do
    Ec::Sku.with_deleted.where(sku_code: [@master_sku_child&.sku_code, @direct_sku&.sku_code].compact).delete_all
    Ec::MasterSku.where(id: @master_sku&.id).delete_all
    UserApiKey.where(user: @user).delete_all
    UserRole.where(user: @user).delete_all
    User.where(id: @user.id).delete_all
  end

  test "requires api key" do
    post "/ai/weekly_profit_reports.json", params: {
      report_type: "wsu",
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }

    assert_response :unauthorized
  end

  test "creates a weekly profit report through shared query runner" do
    payload = {
      report_type: "wsu",
      period: { from_date: "2026-05-18", to_date: "2026-05-24" },
      meta: {},
      summary: { total_sales_revenue: 100.0 },
      rows: [{ sku: @direct_sku.sku_code }],
      extras: {}
    }
    query_class = Ec::WeeklySummaryQuery
    original_run = query_class.method(:run)
    test_case = self
    query_class.define_singleton_method(:run) do |**kwargs|
      test_case.assert_equal Date.parse("2026-05-18"), kwargs[:from_date]
      test_case.assert_equal Date.parse("2026-05-24"), kwargs[:to_date]
      test_case.assert_equal [
        test_case.instance_variable_get(:@direct_sku).sku_code,
        test_case.instance_variable_get(:@master_sku_child).sku_code
      ], kwargs[:sku_codes]
      payload
    end

    post "/ai/weekly_profit_reports.json",
      params: {
        report_type: "wsu",
        from_date: "2026-05-18",
        to_date: "2026-05-24",
        master_sku_ids: [@master_sku.id],
        sku_codes: [@direct_sku.sku_code.downcase]
      },
      headers: bearer_headers(@raw_api_token)

    assert_response :success
    body = response.parsed_body
    assert_equal true, body.fetch("success")
    assert_equal "ok", body.fetch("message")
    assert_equal "wsu", body.dig("data", "report_type")
    assert_equal @direct_sku.sku_code, body.dig("data", "rows").first.fetch("sku")
  ensure
    query_class.define_singleton_method(:run, original_run)
  end

  test "returns shared validation errors" do
    post "/ai/weekly_profit_reports.json",
      params: {
        report_type: "wr",
        from_date: "2026-05-18",
        to_date: "2026-05-24"
      },
      headers: bearer_headers(@raw_api_token)

    assert_response :bad_request
    body = response.parsed_body
    assert_equal false, body.fetch("success")
    assert_match "store_ref", body.fetch("message")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
