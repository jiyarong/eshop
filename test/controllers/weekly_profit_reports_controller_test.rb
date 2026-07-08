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
    Ec::WeeklyRate.where(week_start: [Date.parse("2026-05-18"), Date.parse("2026-05-25")]).delete_all
    @ozon_account&.destroy
    @wb_account&.destroy
    UserRole.joins(:user).where("users.email = ?", @current_user.email).delete_all
    @current_user.destroy
  end

  test "accounts returns flat active wb and ozon shop options" do
    get "/weekly_profit_reports/accounts"

    assert_response :success
    body = JSON.parse(response.body)
    wb_account = body.fetch("data").find { |account| account["ref"] == "wb:#{@wb_account.id}" }
    ozon_account = body.fetch("data").find { |account| account["ref"] == "ozon:#{@ozon_account.id}" }

    assert_equal true, body["success"]
    assert_equal "wb", wb_account["platform"]
    assert_equal "WB Test Shop", wb_account["name"]
    assert_equal "WB · WB Test Shop", wb_account["label"]
    assert_equal "ozon", ozon_account["platform"]
    assert_equal "Ozon Test Shop", ozon_account["name"]
    assert_equal "Ozon · Ozon Test Shop", ozon_account["label"]
  end

  test "index renders weekly profit report page with report type and store filters" do
    payload = {
      report_type: "wr",
      period: { from_date: (Date.current.beginning_of_week(:monday) - 7.days).iso8601, to_date: (Date.current.beginning_of_week(:monday) - 1.day).iso8601 },
      comparison: {
        period: { from_date: (Date.current.beginning_of_week(:monday) - 14.days).iso8601, to_date: (Date.current.beginning_of_week(:monday) - 8.days).iso8601 },
        summary: {
          total_after_tax: { current: 88.5, previous: 70.0, delta_value: 18.5, delta_pct: 26.43, trend: "up", semantic: "positive" }
        },
        rows: {},
        extras: {}
      },
      meta: { platform: "wb", account: { name: "WB Test Shop" } },
      summary: { total_after_tax: 88.5, total_goods_cost: 20.0, total_sales_qty: 3, total_return_qty: 1, total_net: 100.0, total_pre_tax: 90.0, total_tax: 1.5, unallocated_rows: 1 },
      rows: [{ nm_id: 123, vendor_code: "KJ-228", region: "Moscow", sales_qty: 3, return_qty: 1, net_qty: 2, settlement: 100.0, delivery: 10.0, storage: 5.0, ad: 2.0, goods_cost: 20.0, pre_tax: 90.0, tax: 1.5, after_tax: 88.5 }],
      extras: { unallocated: { "未归属费用" => 12.3 } }
    }
    query_class = Ec::WeeklyProfitReportQuery
    original_run = query_class.method(:run)
    query_class.define_singleton_method(:run) { |**_kwargs| payload }

    get "/weekly_profit_reports", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_includes response.media_type, "text/html"
    assert_select "h1", "周利润报表"
    assert_select "form[action=?][method=?]", "/weekly_profit_reports", "get"
    assert_select "[data-controller='time-range-selector']", count: 1
    assert_select ".field--time-range" do
      assert_select "label[for=?]", "weekly-profit-time-range-trigger", "时间范围"
      assert_select "input[name='from_date'][type='hidden'][value=?]", (Date.current.beginning_of_week(:monday) - 7.days).iso8601
      assert_select "input[name='to_date'][type='hidden'][value=?]", (Date.current.beginning_of_week(:monday) - 1.day).iso8601
      assert_select "button[type='submit']", text: "查询"
      assert_select "button[type='submit'][formaction='/weekly_profit_reports'][name='format'][value='xlsx']", text: "导出 XLSX"
    end
    assert_select "input[name='report_type'][type='hidden'][value='wr']", count: 1
    assert_select "input[name='store_ref'][type='hidden'][value=?]", "wb:#{@wb_account.id}"
    assert_select "[data-weekly-profit-tag-group='report-type']", count: 1
    assert_select "button[data-weekly-profit-tag][data-value='wr'].is-active[aria-pressed='true']", text: "WR"
    assert_select "button[data-weekly-profit-tag][data-value='wsu']", text: "WSU"
    assert_select "button[data-weekly-profit-tag][data-value='wsu_deep']", text: "WSU-DEEP"
    assert_select "[data-weekly-profit-store-field]:not(.is-disabled)[aria-disabled='false']", count: 1
    assert_select "[data-weekly-profit-tag-group='store']", count: 1
    assert_select "button[data-weekly-profit-store-tag][data-value=?].is-active[aria-pressed='true']", "wb:#{@wb_account.id}", text: "WB · WB Test Shop"
    assert_select "button[data-weekly-profit-store-tag][data-value=?]", "ozon:#{@ozon_account.id}", text: "Ozon · Ozon Test Shop"
    assert_select "turbo-frame#weekly_profit_report_results"
    assert_select ".weekly-profit-summary-card", minimum: 1
    assert_select ".weekly-profit-table-value", text: "KJ-228"
  ensure
    query_class.define_singleton_method(:run, original_run)
  end

  test "index keeps empty state when there is no default store to query" do
    @wb_account.destroy!
    @ozon_account.destroy!

    get "/weekly_profit_reports", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "turbo-frame#weekly_profit_report_results .empty-state", text: /请选择周期和归集类型后查询/
  end

  test "show requires store ref for wr" do
    get "/weekly_profit_reports.json", params: {
      report_type: "wr",
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_match(/store_ref/, body["message"])
  end

  test "show rejects non natural week range" do
    get "/weekly_profit_reports.json", params: {
      report_type: "wsu",
      from_date: "2026-05-19",
      to_date: "2026-05-24"
    }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
  end

  test "show rejects current week range" do
    monday = Date.current.beginning_of_week(:monday)
    sunday = monday + 6.days

    get "/weekly_profit_reports.json", params: {
      report_type: "wsu",
      from_date: monday.iso8601,
      to_date: sunday.iso8601
    }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
  end

  test "show dispatches wr query for wb store ref" do
    payload = {
      report_type: "wr",
      period: { from_date: "2026-05-18", to_date: "2026-05-24" },
      comparison: {
        period: { from_date: "2026-05-11", to_date: "2026-05-17" },
        summary: {
          total_after_tax: { current: 88.5, previous: 70.0, delta_value: 18.5, delta_pct: 26.43, trend: "up", semantic: "positive" }
        },
        rows: {},
        extras: {}
      },
      meta: { platform: "wb", account: { name: "WB Test Shop" } },
      summary: { total_after_tax: 88.5 },
      rows: [{ nm_id: 123 }],
      extras: { unallocated: { "未归属费用" => 12.3 } }
    }

    query_class = Ec::WeeklyProfitReportQuery
    original_run = query_class.method(:run)
    test_case = self
    query_class.define_singleton_method(:run) do |**kwargs|
      test_case.assert_equal "wb:#{test_case.instance_variable_get(:@wb_account).id}", kwargs[:store_ref]
      test_case.assert_equal Date.parse("2026-05-18"), kwargs[:from_date]
      test_case.assert_equal Date.parse("2026-05-24"), kwargs[:to_date]
      payload
    end

    get "/weekly_profit_reports.json", params: {
      report_type: "wr",
      store_ref: "wb:#{@wb_account.id}",
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal "wr", body.dig("data", "report_type")
    assert_equal "wb", body.dig("data", "meta", "platform")
    assert_equal "2026-05-11", body.dig("data", "comparison", "period", "from_date")
    assert_equal "positive", body.dig("data", "comparison", "summary", "total_after_tax", "semantic")
  ensure
    query_class.define_singleton_method(:run, original_run)
  end

  test "show renders wr result for turbo frame request" do
    payload = {
      report_type: "wr",
      period: { from_date: "2026-05-18", to_date: "2026-05-24" },
      comparison: {
        period: { from_date: "2026-05-11", to_date: "2026-05-17" },
        summary: {
          total_after_tax: { current: 88.5, previous: 70.0, delta_value: 18.5, delta_pct: 26.43, trend: "up", semantic: "positive" }
        },
        rows: {
          "KJ-228" => {
            after_tax: { current: 88.5, previous: 70.0, delta_value: 18.5, delta_pct: 26.43, trend: "up", semantic: "positive" }
          }
        },
        extras: {
          unallocated: {
            "未归属费用" => {
              amount: { current: 12.3, previous: 15.0, delta_value: -2.7, delta_pct: -18.0, trend: "down", semantic: "positive" }
            }
          }
        }
      },
      meta: {
        platform: "wb",
        account: { name: "WB Test Shop" },
        rates: { rate_cny_rub: 10.93, rate_byn_rub: 26.41 }
      },
      summary: { total_after_tax: 88.5, total_goods_cost: 20.0, total_sales_qty: 3, total_return_qty: 1, total_net: 100.0, total_pre_tax: 90.0, total_tax: 1.5, unallocated_rows: 1 },
      rows: [{ nm_id: 123, vendor_code: "KJ-228", region: "Moscow", sales_qty: 3, return_qty: 1, net_qty: 2, settlement: 100.0, delivery: 10.0, storage: 5.0, ad: 2.0, goods_cost: 20.0, pre_tax: 90.0, tax: 1.5, after_tax: 88.5 }],
      extras: { unallocated: { "未归属费用" => 12.3 } }
    }

    query_class = Ec::WeeklyProfitReportQuery
    original_run = query_class.method(:run)
    query_class.define_singleton_method(:run) { |**_kwargs| payload }

    get "/weekly_profit_reports", params: {
      report_type: "wr",
      store_ref: "wb:#{@wb_account.id}",
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }, headers: {
      "Accept" => "text/html",
      "Turbo-Frame" => "weekly_profit_report_results"
    }

    assert_response :success
    assert_select "turbo-frame#weekly_profit_report_results" do
      assert_select ".weekly-profit-comparison-note", text: /上一等长自然周范围/
      assert_select ".weekly-profit-summary-card", minimum: 1
      assert_select ".weekly-profit-comparison-trend", minimum: 1
      assert_select ".weekly-profit-table-value", minimum: 1
      assert_select ".weekly-profit-table-comparison", minimum: 1
      assert_select ".weekly-profit-table-value", text: "KJ-228"
      assert_select ".weekly-profit-table-value", text: "88.50"
      assert_select ".weekly-profit-table-value", text: "未归属费用"
    end
  ensure
    query_class.define_singleton_method(:run, original_run)
  end

  test "show dispatches wsu query" do
    payload = {
      report_type: "wsu",
      period: { from_date: "2026-05-18", to_date: "2026-05-24" },
      meta: { rates: { rate_cny_rub: 10.93, rate_byn_rub: 26.41 } },
      summary: { total_sales_revenue: 100.0 },
      rows: [{ sku: "KJ-228", platform: "WB" }],
      extras: {}
    }

    query_class = Ec::WeeklySummaryQuery
    original_run = query_class.method(:run)
    test_case = self
    query_class.define_singleton_method(:run) do |**kwargs|
      test_case.assert_equal Date.parse("2026-05-18"), kwargs[:from_date]
      test_case.assert_equal Date.parse("2026-05-24"), kwargs[:to_date]
      payload
    end

    get "/weekly_profit_reports.json", params: {
      report_type: "wsu",
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal "wsu", body.dig("data", "report_type")
  ensure
    query_class.define_singleton_method(:run, original_run)
  end

  test "show renders wsu result for turbo frame request" do
    payload = {
      report_type: "wsu",
      period: { from_date: "2026-05-18", to_date: "2026-05-24" },
      comparison: {
        period: { from_date: "2026-05-11", to_date: "2026-05-17" },
        summary: {
          total_after_tax: { current: 30.0, previous: 20.0, delta_value: 10.0, delta_pct: 50.0, trend: "up", semantic: "positive" }
        },
        rows: {
          "KJ-228|WB|WB Test Shop" => {
            revenue: { current: 100.0, previous: 50.0, delta_value: 50.0, delta_pct: 100.0, trend: "up", semantic: "positive" },
            ads: { current: 10.0, previous: 5.0, delta_value: 5.0, delta_pct: 100.0, trend: "up", semantic: "negative" },
            margin_pct: { current: 30.0, previous: 20.0, delta_value: 10.0, delta_pct: 50.0, trend: "up", semantic: "positive" }
          }
        }
      },
      meta: { rates: { rate_cny_rub: 10.93, rate_byn_rub: 26.41 } },
      summary: { total_sales_revenue: 100.0, total_after_tax: 30.0, total_margin_pct: 30.0, unallocated_total: -5.0, after_tax_with_unallocated: 25.0 },
      rows: [{ sku: "KJ-228", platform: "WB", shop: "WB Test Shop", net_sales: 2, revenue: 100.0, ads: 10.0, goods_cost: 20.0, pre_tax: 35.0, tax: 5.0, after_tax: 30.0, margin_pct: 30.0 }],
      extras: {}
    }

    query_class = Ec::WeeklySummaryQuery
    original_run = query_class.method(:run)
    query_class.define_singleton_method(:run) { |**_kwargs| payload }

    get "/weekly_profit_reports", params: {
      report_type: "wsu",
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }, headers: {
      "Accept" => "text/html",
      "Turbo-Frame" => "weekly_profit_report_results"
    }

    assert_response :success
    assert_select "turbo-frame#weekly_profit_report_results" do
      assert_select ".weekly-profit-comparison-note", text: /上一等长自然周范围/
      assert_select ".weekly-profit-summary-card", minimum: 1
      assert_select ".weekly-profit-comparison-trend", minimum: 1
      assert_select ".weekly-profit-table-value", minimum: 1
      assert_select ".weekly-profit-table-comparison", minimum: 1
      assert_select ".weekly-profit-table-value", text: "KJ-228"
      assert_select ".weekly-profit-table-value", text: "WB Test Shop"
      assert_select ".weekly-profit-table-value", text: "30.00%"
    end
  ensure
    query_class.define_singleton_method(:run, original_run)
  end

  test "show dispatches wsu deep query" do
    payload = {
      report_type: "wsu_deep",
      period: { from_date: "2026-05-18", to_date: "2026-05-24" },
      meta: { rates: { rate_cny_rub: 10.93, rate_byn_rub: 26.41 } },
      summary: { total_after_tax: 50.0 },
      rows: [{ sku: "KJ-228", net_sales: 4 }],
      extras: {}
    }

    query_class = Ec::WeeklySummaryDeepQuery
    original_run = query_class.method(:run)
    test_case = self
    query_class.define_singleton_method(:run) do |**kwargs|
      test_case.assert_equal Date.parse("2026-05-18"), kwargs[:from_date]
      test_case.assert_equal Date.parse("2026-05-24"), kwargs[:to_date]
      payload
    end

    get "/weekly_profit_reports.json", params: {
      report_type: "wsu_deep",
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal "wsu_deep", body.dig("data", "report_type")
  ensure
    query_class.define_singleton_method(:run, original_run)
  end

  test "show renders wsu deep result for turbo frame request" do
    payload = {
      report_type: "wsu_deep",
      period: { from_date: "2026-05-18", to_date: "2026-05-24" },
      comparison: {
        period: { from_date: "2026-05-11", to_date: "2026-05-17" },
        summary: {
          total_after_tax: { current: 50.0, previous: 40.0, delta_value: 10.0, delta_pct: 25.0, trend: "up", semantic: "positive" }
        },
        rows: {
          "KJ-228" => {
            after_tax: { current: 50.0, previous: 40.0, delta_value: 10.0, delta_pct: 25.0, trend: "up", semantic: "positive" },
            ad_ratio_pct: { current: 10.0, previous: 12.0, delta_value: -2.0, delta_pct: -16.67, trend: "down", semantic: "positive" }
          }
        }
      },
      meta: { rates: { rate_cny_rub: 10.93, rate_byn_rub: 26.41 } },
      summary: { total_sku_count: 1, total_net_sales: 4, total_sales_revenue: 100.0, total_after_tax: 50.0, unallocated_total: -5.0, after_tax_with_unallocated: 45.0 },
      rows: [{ sku: "KJ-228", net_sales: 4, revenue: 100.0, ads: 10.0, goods_cost: 20.0, pre_tax: 60.0, tax: 10.0, after_tax: 50.0, margin_pct: 50.0, average_profit_per_order: 12.5, ad_ratio_pct: 10.0, cost_return_pct: 250.0, projected_roi_pct: 55.0, annualized_return_pct: 110.0, annualized_net_profit_cny: 800.0 }],
      extras: {}
    }

    query_class = Ec::WeeklySummaryDeepQuery
    original_run = query_class.method(:run)
    query_class.define_singleton_method(:run) { |**_kwargs| payload }

    get "/weekly_profit_reports", params: {
      report_type: "wsu_deep",
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }, headers: {
      "Accept" => "text/html",
      "Turbo-Frame" => "weekly_profit_report_results"
    }

    assert_response :success
    assert_select "turbo-frame#weekly_profit_report_results" do
      assert_select ".weekly-profit-comparison-note", text: /上一等长自然周范围/
      assert_select ".weekly-profit-summary-card", minimum: 1
      assert_select ".weekly-profit-comparison-trend", minimum: 1
      assert_select ".weekly-profit-table-value", minimum: 1
      assert_select ".weekly-profit-table-comparison", minimum: 1
      assert_select ".weekly-profit-table-value", text: "KJ-228"
      assert_select ".weekly-profit-table-value", text: "800.00"
    end
  ensure
    query_class.define_singleton_method(:run, original_run)
  end

  test "show renders readable comparison labels when previous values are negative" do
    payload = {
      report_type: "wsu_deep",
      period: { from_date: "2026-05-18", to_date: "2026-05-24" },
      comparison: {
        period: { from_date: "2026-05-11", to_date: "2026-05-17" },
        summary: {
          total_after_tax: { current: 50.0, previous: -40.0, delta_value: 90.0, delta_pct: -225.0, trend: "up", semantic: "positive" }
        },
        rows: {
          "TURN-POSITIVE" => {
            annualized_net_profit_cny: { current: 800.0, previous: -200.0, delta_value: 1000.0, delta_pct: -500.0, trend: "up", semantic: "positive" }
          },
          "WORSE-LOSS" => {
            annualized_net_profit_cny: { current: -300.0, previous: -100.0, delta_value: -200.0, delta_pct: 200.0, trend: "down", semantic: "negative" }
          },
          "BETTER-LOSS" => {
            annualized_net_profit_cny: { current: 0.0, previous: -120.0, delta_value: 120.0, delta_pct: -100.0, trend: "up", semantic: "positive" }
          }
        }
      },
      meta: { rates: { rate_cny_rub: 10.93, rate_byn_rub: 26.41 } },
      summary: { total_sku_count: 3, total_net_sales: 4, total_sales_revenue: 100.0, total_after_tax: 50.0, unallocated_total: -5.0, after_tax_with_unallocated: 45.0 },
      rows: [
        { sku: "TURN-POSITIVE", net_sales: 4, revenue: 100.0, ads: 10.0, goods_cost: 20.0, pre_tax: 60.0, tax: 10.0, after_tax: 50.0, margin_pct: 50.0, average_profit_per_order: 12.5, ad_ratio_pct: 10.0, cost_return_pct: 250.0, projected_roi_pct: 55.0, annualized_return_pct: 110.0, annualized_net_profit_cny: 800.0 },
        { sku: "WORSE-LOSS", net_sales: 1, revenue: 10.0, ads: 2.0, goods_cost: 3.0, pre_tax: -20.0, tax: 0.0, after_tax: -20.0, margin_pct: -200.0, average_profit_per_order: -20.0, ad_ratio_pct: 20.0, cost_return_pct: -666.0, projected_roi_pct: -50.0, annualized_return_pct: -100.0, annualized_net_profit_cny: -300.0 },
        { sku: "BETTER-LOSS", net_sales: 0, revenue: 0.0, ads: 0.0, goods_cost: 0.0, pre_tax: 0.0, tax: 0.0, after_tax: 0.0, margin_pct: nil, average_profit_per_order: nil, ad_ratio_pct: nil, cost_return_pct: nil, projected_roi_pct: nil, annualized_return_pct: nil, annualized_net_profit_cny: 0.0 }
      ],
      extras: {}
    }

    query_class = Ec::WeeklySummaryDeepQuery
    original_run = query_class.method(:run)
    query_class.define_singleton_method(:run) { |**_kwargs| payload }

    get "/weekly_profit_reports", params: {
      report_type: "wsu_deep",
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }, headers: {
      "Accept" => "text/html",
      "Turbo-Frame" => "weekly_profit_report_results"
    }

    assert_response :success
    assert_select "turbo-frame#weekly_profit_report_results" do
      assert_includes response.body, "↗ 转正"
      assert_includes response.body, "↘ 恶化"
      assert_includes response.body, "↗ 改善"
      refute_includes response.body, "↗ -500.00%"
      refute_includes response.body, "↘ 200.00%"
      refute_includes response.body, "↗ -100.00%"
    end
  ensure
    query_class.define_singleton_method(:run, original_run)
  end

  test "show exports xlsx for current filter" do
    payload = {
      report_type: "wsu",
      period: { from_date: "2026-05-18", to_date: "2026-05-24" },
      meta: { rates: { rate_cny_rub: 10.93, rate_byn_rub: 26.41 } },
      summary: { total_sales_revenue: 100.0 },
      rows: [{ sku: "KJ-228", platform: "WB", shop: "WB Test Shop" }],
      extras: {}
    }
    export_result = {
      filename: "weekly-profit-wsu-w21-2026-05-18_to_2026-05-24.xlsx",
      data: "xlsx-binary"
    }

    query_class = Ec::WeeklySummaryQuery
    export_class = WeeklyProfitReports::XlsxExportService
    original_query_run = query_class.method(:run)
    original_export_call = export_class.method(:call)
    captured_report = nil

    query_class.define_singleton_method(:run) { |**_kwargs| payload }
    export_class.define_singleton_method(:call) do |report:|
      captured_report = report
      export_result
    end

    get "/weekly_profit_reports", params: {
      format: "xlsx",
      report_type: "wsu",
      from_date: "2026-05-18",
      to_date: "2026-05-24"
    }, headers: {
      "Accept" => WeeklyProfitReports::XlsxExportService::MIME_TYPE
    }

    assert_response :success
    assert_equal payload, captured_report
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.media_type
    assert_equal "xlsx-binary", response.body
    assert_match(/attachment;.*weekly-profit-wsu-w21-2026-05-18_to_2026-05-24\.xlsx/, response.headers["Content-Disposition"])
  ensure
    query_class.define_singleton_method(:run, original_query_run)
    export_class.define_singleton_method(:call, original_export_call)
  end
end
