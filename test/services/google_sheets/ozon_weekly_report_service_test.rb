require "test_helper"

class GoogleSheets::OzonWeeklyReportServiceTest < ActiveSupport::TestCase
  test "exports other platform fees and reconciles Nevastal W36 settlement" do
    service = GoogleSheets::OzonWeeklyReportService.allocate
    service.instance_variable_set(:@from_date, Date.new(2026, 8, 31))
    service.instance_variable_set(:@to_date, Date.new(2026, 9, 6))
    service.instance_variable_set(:@rate_cny_rub, 10.0)
    service.instance_variable_set(:@name_map, {})
    row = Hash.new(0).merge(
      ozon_sku_id: 123,
      sku_code: "DJ001",
      sales_revenue: 2_433_353.00,
      other_fee: -9_240.00,
      book_profit_after_ad: 1_098_549.41
    )
    service.instance_variable_set(:@results, [row])
    service.instance_variable_set(:@unallocated, {
      total: -15_502.37,
      rows: [
        { type_id: 96, type_name: nil, amount: -4_000.00 },
        { type_id: 94, type_name: nil, amount: -2_262.37 },
        { type_id: 101, type_name: nil, amount: -9_240.00 }
      ]
    })

    sku_row = service.send(:sku_row, row)
    summary = service.send(:build_report_rows)

    assert_equal GoogleSheets::OzonWeeklyReportService::SKU_HDR_ZH.size, sku_row.size
    assert_equal(-9_240.00, sku_row[13])
    assert_equal(-9_240.00, summary.find { |item| item[:label].start_with?("其他平台费用") }[:value])
    assert_equal(-15_502.37, summary.find { |item| item[:label].start_with?("未分摊合计") }[:value])
    assert_equal 1_083_047.04, summary.find { |item| item[:label].start_with?("平台结算总额") }[:value]
    assert_includes summary.map { |item| item[:label] }, "其他平台费用 / Прочие расходы Ozon (Ozon type 101)"
  end
end
