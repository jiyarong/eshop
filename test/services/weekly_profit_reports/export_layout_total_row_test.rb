require "test_helper"

class WeeklyProfitReports::ExportLayoutTotalRowTest < ActiveSupport::TestCase
  test "wsu_deep export total row is as wide as the table and keeps each total under its header" do
    report = {
      report_type: "wsu_deep", period: { from_date: "2026-06-01", to_date: "2026-06-07" },
      summary: { total_after_tax: 130, total_dest_pending_count: 2, total_dest_pending_sale: 35.5 },
      rows: [
        { sku: "TOTAL-A", net_sales: 2, revenue: 200, after_tax: 100, commission_fee: 30, payment_fee: 4, delivery_fee: 6,
          dest_pending_count: 2, dest_pending_sale: 35.5 },
        { sku: "TOTAL-B", net_sales: 1, revenue: 100, after_tax: 30, commission_fee: 12, payment_fee: 1.5, delivery_fee: 2,
          dest_pending_count: 0, dest_pending_sale: 0.0 }
      ]
    }

    section = WeeklyProfitReports::ExportLayoutBuilder.build(report: report)[:sections].first
    headers = section[:rows][0]
    total_row = section[:rows].last

    assert_equal "合计 / Итого", total_row[0]
    assert_equal headers.size, total_row.size
    assert_equal section[:rows][2].size, total_row.size, "total row and data rows must have the same number of cells"
    assert_in_delta 42.0, total_row[headers.index("销售佣金(CNY)")], 0.001
    assert_in_delta 5.5, total_row[headers.index("收单费(CNY)")], 0.001
    assert_in_delta 8.0, total_row[headers.index("物流费(CNY)")], 0.001
    assert_equal 2, total_row[headers.index(I18n.t("weekly_profit_reports.columns.wsu_deep.dest_pending_count", locale: :zh))]
    assert_equal 35.5, total_row[headers.index(I18n.t("weekly_profit_reports.columns.wsu_deep.dest_pending_sale", locale: :zh))]
  end
end
