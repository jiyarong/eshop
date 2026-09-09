require "test_helper"

class Ec::SkuOperationTrendQueryTest < ActiveSupport::TestCase
  test "smooths weekly unit profit across each day of the completed week" do
    sku = Struct.new(:sku_code).new("TREND-PROFIT")
    account = Struct.new(:name).new("Profit Shop")
    store = Struct.new(:id, :wb_raw_account_id, :raw_wb_account) do
      def wb? = true
      def platform = "wb"
    end.new(12, 34, account)
    calls = []
    runner = lambda do |from_date:, to_date:, sku_codes:|
      calls << { from_date: from_date, to_date: to_date, sku_codes: sku_codes }
      { rows: [{ sku: "TREND-PROFIT", platform: "WB", shop: "Profit Shop", net_sales: 4, after_tax: 100 }] }
    end
    query = Ec::SkuOperationTrendQuery.new(
      sku: sku,
      store: store,
      from_date: Date.new(2026, 8, 3),
      to_date: Date.new(2026, 8, 9),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      profit_query_runner: runner
    )

    rows = query.send(:daily_unit_profit_rows)

    assert_equal 7, rows.size
    assert_equal [25.0], rows.map { |row| row[:unit_profit] }.uniq
    assert_equal((Date.new(2026, 8, 3)..Date.new(2026, 8, 9)).to_a, rows.map { |row| row[:date] })
    assert_equal Date.new(2026, 8, 3), calls.first[:from_date]
    assert_equal Date.new(2026, 8, 9), calls.first[:to_date]
    assert_equal ["TREND-PROFIT"], calls.first[:sku_codes]
  end

  test "hides net sales and unit profit series by default" do
    query = Ec::SkuOperationTrendQuery.new(
      sku: Struct.new(:sku_code).new("TREND-LEGEND"),
      store: Struct.new(:platform).new("wb"),
      from_date: Date.new(2026, 8, 3),
      to_date: Date.new(2026, 8, 9),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
    )

    option = query.send(:chart_option, [], [], [], [], [])

    assert_equal false, option.dig(:legend, :selected, I18n.t("erp.operation_actions.trends.metrics.net_sales"))
    assert_equal false, option.dig(:legend, :selected, I18n.t("erp.operation_actions.trends.metrics.unit_profit"))
  end
end
