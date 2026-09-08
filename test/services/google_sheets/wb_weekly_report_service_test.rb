require "test_helper"

class GoogleSheets::WbWeeklyReportServiceTest < ActiveSupport::TestCase
  test "exports finance-only rows with the same width as the headers" do
    service = GoogleSheets::WbWeeklyReportService.allocate
    service.instance_variable_set(:@name_map, {})
    row = Hash.new(0).merge(
      nm_id: 123,
      vendor_code: "WB-FINANCE-ONLY",
      region: "出口",
      sales_qty: 0,
      return_qty: 0,
      net_qty: 0,
      additional_payment: 20,
      net: 20
    )
    service.instance_variable_set(:@results, [row])

    assert service.send(:reportable_result?, row)
    assert_equal GoogleSheets::WbWeeklyReportService::SKU_HDR_ZH.size,
      service.send(:sku_row, row).size
    assert_equal GoogleSheets::WbWeeklyReportService::SKU_HDR_ZH.size,
      service.send(:build_sku_total_row).size
    assert_equal GoogleSheets::WbWeeklyReportService::SKU_HDR_ZH.size,
      GoogleSheets::WbWeeklyReportService::SKU_COL_TYPES.size
    assert_equal GoogleSheets::WbWeeklyReportService::SKU_HDR_ZH.size,
      GoogleSheets::WbWeeklyReportService::SKU_COL_WIDTHS.size
  end

  test "prints platform settlement and reconciliation difference" do
    service = GoogleSheets::WbWeeklyReportService.allocate
    service.instance_variable_set(:@results, [])
    service.instance_variable_set(:@unallocated, {})
    service.instance_variable_set(:@summary, {
      tax_regime: "usn",
      platform_settlement: 21_229.66,
      reconciliation_difference: 0.0
    })
    service.instance_variable_set(:@from_date, Date.new(2026, 8, 31))
    service.instance_variable_set(:@to_date, Date.new(2026, 9, 6))
    service.instance_variable_set(:@rate_cny_rub, 10.0)
    service.instance_variable_set(:@rate_byn_rub, 3.0)

    rows = service.send(:build_summary_rows)

    assert_equal 21_229.66, rows.find { |row| row[:label].include?("平台结算总额") }[:value]
    assert_equal 0.0, rows.find { |row| row[:label].include?("对账差额") }[:value]
  end
end
