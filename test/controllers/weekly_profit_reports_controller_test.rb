require "test_helper"

class WeeklyProfitReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    unique = SecureRandom.hex(4)
    @current_user = create_user_with_roles("weekly-profit-#{unique}@example.com", "manager")
    sign_in @current_user

    @wb_account = RawWb::SellerAccount.create!(
      name: "WB Test Shop",
      api_token: "wb-token-#{unique}",
      is_active: true,
      company_type: :small
    )

    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Ozon Test Shop",
      client_id: "ozon-client-#{unique}",
      api_key: "ozon-key-#{unique}",
      is_active: true,
      company_type: :general
    )
  end

  teardown do
    Ec::WeeklyRate.where(week_start: Date.parse("2026-05-18")).delete_all
    @ozon_account&.destroy
    @wb_account&.destroy
    UserRole.joins(:user).where("users.email = ?", @current_user.email).delete_all
    @current_user.destroy
  end

  test "accounts returns active wb and ozon shops" do
    get "/weekly_profit_reports/accounts"

    assert_response :success
    body = JSON.parse(response.body)
    wb_account = body.dig("data", "wb").find { |account| account["id"] == @wb_account.id }
    ozon_account = body.dig("data", "ozon").find { |account| account["id"] == @ozon_account.id }

    assert_equal true, body["success"]
    assert_equal "WB Test Shop", wb_account["name"]
    assert_equal "Ozon Test Shop", ozon_account["name"]
  end

  test "index renders weekly profit report page as html" do
    get "/weekly_profit_reports", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_includes response.media_type, "text/html"
    assert_select "h1", "周利润报表"
    assert_select "form[action=?][method=?]", "/weekly_profit_reports", "get"
    assert_select "turbo-frame#weekly_profit_report_results"
    assert_select "option[value=?]", "wb"
    assert_select "option[value=?]", "ozon"
    assert_select "option[value=?]", @wb_account.id.to_s, text: "WB Test Shop"
    assert_select "option[value=?]", @ozon_account.id.to_s, text: "Ozon Test Shop"
  end

  test "show renders weekly profit report result for turbo frame request" do
    rate = Ec::WeeklyRate.find_or_initialize_by(week_start: Date.parse("2026-05-18"))
    rate.update!(rate_cny_rub: 10.93, rate_byn_rub: 26.41)

    service = Struct.new(:results, :unallocated, :summary).new(
      [{ nm_id: 123, vendor_code: "KJ-228", region: "Moscow", after_tax: 88.5 }],
      { "未归属费用" => 12.3 },
      { total_after_tax: 88.5, total_goods_cost: 20.0 }
    )

    original_new = Ec::WbProfitAttribution.method(:new)
    Ec::WbProfitAttribution.define_singleton_method(:new) { |**_kwargs| service }
    service.define_singleton_method(:call) { service }

    begin
      get "/weekly_profit_reports", params: {
        platform: "wb",
        account_id: @wb_account.id,
        from_date: "2026-05-18",
        to_date: "2026-05-24"
      }, headers: {
        "Accept" => "text/html",
        "Turbo-Frame" => "weekly_profit_report_results"
      }
    ensure
      Ec::WbProfitAttribution.define_singleton_method(:new, original_new)
      service.singleton_class.remove_method(:call)
    end

    assert_response :success
    assert_select "turbo-frame#weekly_profit_report_results" do
      assert_select ".weekly-profit-summary-card", minimum: 1
      assert_select "td", "KJ-228"
      assert_select "td", "88.50"
      assert_select "td", "未归属费用"
    end
  end

  test "show requires platform account and dates" do
    get "/weekly_profit_reports.json"

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_match(/platform/, body["message"])
  end

  test "show rejects unsupported platform" do
    get "/weekly_profit_reports.json", params: {
      platform: "amazon",
      account_id: @wb_account.id,
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_match(/platform/, body["message"])
  end

  test "show returns 422 when weekly rate is missing" do
    Ec::WeeklyRate.where(week_start: Date.parse("2026-05-18")).delete_all
    original_resolve = Ec::WeeklyRate.method(:resolve)
    Ec::WeeklyRate.define_singleton_method(:resolve) { |*_args| raise "weekly rate should not be resolved" }

    begin
      get "/weekly_profit_reports.json", params: {
        platform: "wb",
        account_id: @wb_account.id,
        from_date: "2026-05-18",
        to_date: "2026-05-24"
      }
    ensure
      Ec::WeeklyRate.define_singleton_method(:resolve, original_resolve)
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_match(/汇率/, body["message"])
  end

  test "show returns 404 for missing shop without resolving weekly rate" do
    original_resolve = Ec::WeeklyRate.method(:resolve)
    Ec::WeeklyRate.define_singleton_method(:resolve) { |*_args| raise "weekly rate should not be resolved" }

    begin
      get "/weekly_profit_reports.json", params: {
        platform: "wb",
        account_id: @wb_account.id + 1_000_000,
        from_date: "2026-05-18",
        to_date: "2026-05-24"
      }
    ensure
      Ec::WeeklyRate.define_singleton_method(:resolve, original_resolve)
    end

    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_match(/店铺/, body["message"])
  end

  test "show returns 500 when attribution service raises argument error" do
    rate = Ec::WeeklyRate.find_or_initialize_by(week_start: Date.parse("2026-05-18"))
    rate.update!(rate_cny_rub: 10.93, rate_byn_rub: 26.41)
    service = Object.new

    original_new = Ec::WbProfitAttribution.method(:new)

    Ec::WbProfitAttribution.define_singleton_method(:new) { |**_kwargs| service }
    service.define_singleton_method(:call) { raise ArgumentError, "sensitive service details" }

    begin
      get "/weekly_profit_reports.json", params: {
        platform: "wb",
        account_id: @wb_account.id,
        from_date: "2026-05-18",
        to_date: "2026-05-24"
      }
    ensure
      Ec::WbProfitAttribution.define_singleton_method(:new, original_new)
      service.singleton_class.remove_method(:call)
    end

    assert_response :internal_server_error
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_equal "internal server error", body["message"]
  end

  test "show returns wb weekly profit payload" do
    rate = Ec::WeeklyRate.find_or_initialize_by(week_start: Date.parse("2026-05-18"))
    rate.update!(rate_cny_rub: 10.93, rate_byn_rub: 26.41)

    service = Struct.new(:results, :unallocated, :summary).new(
      [{ nm_id: 123, vendor_code: "KJ-228", after_tax: 88.5 }],
      { "未归属费用" => 12.3 },
      { total_after_tax: 88.5, tax_regime: "usn" }
    )

    original_new = Ec::WbProfitAttribution.method(:new)
    test_case = self
    account_id = @wb_account.id

    Ec::WbProfitAttribution.define_singleton_method(:new) do |**kwargs|
      test_case.assert_equal account_id, kwargs[:account_id]
      test_case.assert_equal Date.parse("2026-05-18"), kwargs[:from_date]
      test_case.assert_equal Date.parse("2026-05-24"), kwargs[:to_date]
      test_case.assert_equal rate.rate_cny_rub, kwargs[:rate_cny_rub]
      test_case.assert_equal rate.rate_byn_rub, kwargs[:rate_byn_rub]
      service
    end
    service.define_singleton_method(:call) { service }

    begin
      get "/weekly_profit_reports.json", params: {
        platform: "wb",
        account_id: @wb_account.id,
        from_date: "2026-05-18",
        to_date: "2026-05-24"
      }
    ensure
      Ec::WbProfitAttribution.define_singleton_method(:new, original_new)
      service.singleton_class.remove_method(:call)
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal "wb", body.dig("data", "platform")
    assert_equal "WB Test Shop", body.dig("data", "account", "name")
    assert_equal 88.5, body.dig("data", "summary", "total_after_tax")
    assert_equal 123, body.dig("data", "rows", 0, "nm_id")
    assert_equal 12.3, body.dig("data", "unallocated", "未归属费用")
  end

  test "show returns ozon weekly profit payload" do
    rate = Ec::WeeklyRate.find_or_initialize_by(week_start: Date.parse("2026-05-18"))
    rate.update!(rate_cny_rub: 10.93, rate_byn_rub: 26.41)

    service = Struct.new(:results, :unallocated, :summary).new(
      [{ ozon_sku_id: "111", sku_code: "KJ-228", after_tax_profit: 150.0 }],
      { total: -20.0, rows: [{ type_id: 96, type_name: "Fine", amount: -20.0 }] },
      { total_after_tax_profit: 150.0, sku_count: 1 }
    )

    original_new = Ec::OzonProfitAttribution.method(:new)
    test_case = self
    account_id = @ozon_account.id

    Ec::OzonProfitAttribution.define_singleton_method(:new) do |**kwargs|
      test_case.assert_equal account_id, kwargs[:account_id]
      test_case.assert_equal Date.parse("2026-05-18"), kwargs[:from_date]
      test_case.assert_equal Date.parse("2026-05-24"), kwargs[:to_date]
      test_case.assert_equal 10.93, kwargs[:rate_cny_rub]
      test_case.assert_equal false, kwargs[:sync_missing_ad_costs]
      service
    end
    service.define_singleton_method(:call) { service }

    begin
      get "/weekly_profit_reports.json", params: {
        platform: "ozon",
        account_id: @ozon_account.id,
        from_date: "2026-05-18",
        to_date: "2026-05-24"
      }
    ensure
      Ec::OzonProfitAttribution.define_singleton_method(:new, original_new)
      service.singleton_class.remove_method(:call)
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal "ozon", body.dig("data", "platform")
    assert_equal "Ozon Test Shop", body.dig("data", "account", "name")
    assert_equal 150.0, body.dig("data", "summary", "total_after_tax_profit")
    assert_equal "111", body.dig("data", "rows", 0, "ozon_sku_id")
    assert_equal(-20.0, body.dig("data", "unallocated", "total"))
  end
end
