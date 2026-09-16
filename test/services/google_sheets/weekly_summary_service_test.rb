require "test_helper"

class GoogleSheets::WeeklySummaryServiceTest < ActiveSupport::TestCase
  def setup
    @sku_codes = []
    @original_base_initialize = GoogleSheets::BaseService.instance_method(:initialize)
    GoogleSheets::BaseService.define_method(:initialize) { nil }
  end

  def teardown
    GoogleSheets::BaseService.define_method(:initialize, @original_base_initialize)
    Ec::Sku.where(sku_code: @sku_codes).delete_all
  end

  test "writes store rows with average price and cost ratio columns matching sku detail metrics" do
    sku_code = "WSU-XLSX-#{SecureRandom.hex(4).upcase}"
    @sku_codes << sku_code
    Ec::Sku.create!(sku_code: sku_code, product_name: "Test #{sku_code}")

    current_rows = [
      { sku: sku_code, platform: "WB", shop: "WB-1", net_sales: 5, revenue: 100, ads: 10, goods_cost: 30, pre_tax: 40, tax: 5, after_tax: 35 }
    ]

    writes = capture_sheet_writes(current_rows:, previous_rows: [])
    values = writes.fetch(:writes).find { |entry| entry[:range] == "WSU:W22!A1" }.fetch(:values)

    assert_equal "销售均价", values[0][15]
    assert_equal "成本占比%", values[0][16]
    assert_equal "广告占比%", values[0][17]
    assert_equal "平均每单利润", values[0][18]
    assert_equal "年化收益率%", values[0][19]
    assert_equal "年化净利(CNY)", values[0][20]

    data_row = values.find { |row| row[0] == sku_code }
    assert_equal 20.0, data_row[15]
    assert_equal 30.0, data_row[16]
    assert_equal 10.0, data_row[17]
    assert_in_delta 7.0, data_row[18].to_f, 0.001
  end

  test "writes fee breakdown columns matching sku detail metrics" do
    sku_code = "WSU-XLSX-#{SecureRandom.hex(4).upcase}"
    @sku_codes << sku_code
    Ec::Sku.create!(sku_code: sku_code, product_name: "Test #{sku_code}")

    current_rows = [
      { sku: sku_code, platform: "WB", shop: "WB-1", net_sales: 5, revenue: 100, ads: 10, goods_cost: 30, pre_tax: 40, tax: 5, after_tax: 35,
        commission_fee: 3, payment_fee: 1, delivery_fee: 2, return_delivery_fee: 0.5, storage_fee: 1.5,
        dispatch_fee: 0.2, packing_fee: 0.3, defect_fee: 0.1, crossdock_fee: 0.4, other_platform_fee: 0.6 }
    ]

    writes = capture_sheet_writes(current_rows:, previous_rows: [])
    values = writes.fetch(:writes).find { |entry| entry[:range] == "WSU:W22!A1" }.fetch(:values)

    assert_equal "销售佣金(CNY)", values[0][21]
    assert_equal "支付手续费(CNY)", values[0][22]
    assert_equal "物流费(CNY)", values[0][23]
    assert_equal "退货物流费(CNY)", values[0][24]
    assert_equal "仓储费(CNY)", values[0][25]
    assert_equal "退件费(CNY)", values[0][26]
    assert_equal "包装费(CNY)", values[0][27]
    assert_equal "瑕疵处理费(CNY)", values[0][28]
    assert_equal "越库费(CNY)", values[0][29]
    assert_equal "其它平台费(CNY)", values[0][30]

    row = values.find { |r| r[0] == sku_code }
    assert_equal 3.0, row[21]
    assert_equal 1.0, row[22]
    assert_equal 2.0, row[23]
    assert_equal 0.5, row[24]
    assert_equal 1.5, row[25]
    assert_in_delta 0.2, row[26], 0.001
    assert_in_delta 0.3, row[27], 0.001
    assert_in_delta 0.1, row[28], 0.001
    assert_in_delta 0.4, row[29], 0.001
    assert_in_delta 0.6, row[30], 0.001
    assert_equal 31, row.size
  end

  private

  def capture_sheet_writes(current_rows:, previous_rows:)
    rate = Struct.new(:rate_cny_rub, :rate_byn_rub).new(BigDecimal("10"), BigDecimal("5"))
    original_resolve = Ec::WeeklyRate.method(:resolve)
    original_runner_run = WeeklyProfitReports::ReportQueryRunner.method(:run)
    service = GoogleSheets::WeeklySummaryService.new(
      from_date: Date.new(2026, 5, 25),
      to_date: Date.new(2026, 5, 31),
      week_label: "W22"
    )
    writes = []
    ensured_tab = nil
    cleared_range = nil

    Ec::WeeklyRate.define_singleton_method(:resolve, ->(_date) { rate })
    query = Ec::WeeklySummaryQuery.new(
      from_date: Date.new(2026, 5, 25),
      to_date: Date.new(2026, 5, 31),
      rate: rate
    )
    query.define_singleton_method(:collect_rows) do |from_date, _to_date, _rate|
      rows = from_date == Date.new(2026, 5, 25) ? current_rows : previous_rows
      [rows, { wb: 0, ozon: 0 }]
    end
    payload = query.run
    WeeklyProfitReports::ReportQueryRunner.define_singleton_method(:run) { |**_kwargs| payload }
    service.define_singleton_method(:ensure_sheet_exists) { |tab| ensured_tab = tab }
    service.define_singleton_method(:clear_sheet) { |range:| cleared_range = range }
    service.define_singleton_method(:sheet_id) { |_tab| 123 }
    service.define_singleton_method(:batch_update) { |_requests| nil }
    service.define_singleton_method(:write_to_sheet) do |range:, values:|
      writes << { range: range, values: values }
    end

    service.call
    { writes: writes, ensured_tab: ensured_tab, cleared_range: cleared_range }
  ensure
    Ec::WeeklyRate.define_singleton_method(:resolve, original_resolve)
    WeeklyProfitReports::ReportQueryRunner.define_singleton_method(:run, original_runner_run)
  end
end
