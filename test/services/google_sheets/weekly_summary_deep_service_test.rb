require "test_helper"

class GoogleSheets::WeeklySummaryDeepServiceTest < ActiveSupport::TestCase
  def setup
    @sku_codes = []
    @original_base_initialize = GoogleSheets::BaseService.instance_method(:initialize)
    GoogleSheets::BaseService.define_method(:initialize) { nil }
  end

  def teardown
    GoogleSheets::BaseService.define_method(:initialize, @original_base_initialize)
    Ec::SkuCost.where(sku_code: @sku_codes).delete_all
    Ec::Sku.where(sku_code: @sku_codes).delete_all
  end

  test "writes one aggregated row per sku with previous comparisons and derived metrics" do
    create_sku_with_cost("WSUDEEP-A", purchase_price_cny: 8, freight_to_by_cny: 2, pkg_volume_override_l: 1.0)
    create_sku_with_cost("WSUDEEP-B", purchase_price_cny: nil, freight_to_by_cny: nil, pkg_volume_override_l: nil)

    current_rows = [
      { sku: "WSUDEEP-A", platform: "WB", shop: "WB-1", net_sales: 5, revenue: 100, ads: 10, goods_cost: 30, pre_tax: 40, tax: 5, after_tax: 35 },
      { sku: "WSUDEEP-A", platform: "Ozon", shop: "OZ-1", net_sales: 3, revenue: 60, ads: 6, goods_cost: 18, pre_tax: 24, tax: 4, after_tax: 20 },
      { sku: "WSUDEEP-B", platform: "WB", shop: "WB-2", net_sales: 2, revenue: 20, ads: 2, goods_cost: 5, pre_tax: 8, tax: 1, after_tax: 7 }
    ]
    previous_rows = [
      { sku: "WSUDEEP-A", platform: "WB", shop: "WB-9", net_sales: 4, revenue: 80, ads: 8, goods_cost: 24, pre_tax: 30, tax: 4, after_tax: 26 },
      { sku: "WSUDEEP-A", platform: "Ozon", shop: "OZ-9", net_sales: 2, revenue: 40, ads: 4, goods_cost: 12, pre_tax: 16, tax: 3, after_tax: 13 },
      { sku: "WSUDEEP-B", platform: "WB", shop: "WB-8", net_sales: 1, revenue: 10, ads: 1, goods_cost: 2, pre_tax: 3, tax: 1, after_tax: 2 }
    ]

    writes = capture_sheet_writes(current_rows:, previous_rows:)
    sheet_writes = writes.fetch(:writes)

    data_write = sheet_writes.find { |entry| entry[:range] == "WSU-DEEP:W22!A1" }
    assert data_write, "expected main table write"

    values = data_write[:values]
    assert_equal "WSU-DEEP:W22", writes.fetch(:ensured_tab)
    assert_equal "WSU-DEEP:W22!A1:Z", writes.fetch(:cleared_range)

    assert_equal "SKU", values[0][0]
    assert_equal "ROI(按180天备货)", values[0][12]
    assert_equal "年化(按180天备货)", values[0][13]
    assert_equal "年化净利(按180天备货)", values[0][14]

    sku_a_row = values.find { |row| row[0] == "WSUDEEP-A" }
    sku_b_row = values.find { |row| row[0] == "WSUDEEP-B" }
    total_row = values.find { |row| row[0] == "合计 / Итого" }

    sku_a = Ec::Sku.find_by!(sku_code: "WSUDEEP-A")
    assert_equal 8, sku_a_row[1]
    assert_equal 160, sku_a_row[2]
    assert_equal 16, sku_a_row[3]
    assert_equal 48, sku_a_row[4]
    assert_equal 64, sku_a_row[5]
    assert_equal 9, sku_a_row[6]
    assert_equal 55, sku_a_row[7]
    assert_in_delta 34.38, sku_a_row[8].to_f, 0.1
    assert_in_delta 6.875, sku_a_row[9].to_f, 0.001
    assert_in_delta 10.0, sku_a_row[10].to_f, 0.001
    assert_in_delta 114.58, sku_a_row[11].to_f, 0.1
    assert_equal BigDecimal("12.5600"), sku_a.cost.goods_cost_cny
    assert_equal BigDecimal("1.0"), sku_a.cost.pkg_volume_l
    assert_in_delta 49.4, sku_a_row[12].to_f, 0.1
    assert_in_delta 99.85, sku_a_row[13].to_f, 0.1
    assert_in_delta 2581.33, sku_a_row[14].to_f, 0.1
    assert_equal 15, sku_a_row.size

    assert_equal 2, sku_b_row[1]
    assert_nil sku_b_row[12]
    assert_nil sku_b_row[13]
    assert_nil sku_b_row[14]

    assert_equal 10, total_row[1]
    assert_equal 180, total_row[2]

    summary_write = sheet_writes.find { |entry| entry[:range].start_with?("WSU-DEEP:W22!A") && entry[:range] != "WSU-DEEP:W22!A1" }
    assert summary_write, "expected summary write"
    assert summary_write[:values].flatten.include?("总销售额")
    assert summary_write[:values].flatten.include?(180)
    assert summary_write[:values].flatten.include?("未分摊合计")
    assert summary_write[:values].flatten.include?(-5.0)
    assert summary_write[:values].flatten.include?("税后净利（含未分摊）")
    assert summary_write[:values].flatten.include?(57.0)
  end

  private

  def capture_sheet_writes(current_rows:, previous_rows:)
    rate = Struct.new(:rate_cny_rub, :rate_byn_rub).new(BigDecimal("7.2"), BigDecimal("0.28"))
    original_resolve = Ec::WeeklyRate.method(:resolve)
    original_runner_run = WeeklyProfitReports::ReportQueryRunner.method(:run)
    service = GoogleSheets::WeeklySummaryDeepService.new(
      from_date: Date.new(2026, 5, 25),
      to_date: Date.new(2026, 5, 31),
      week_label: "W22"
    )
    writes = []
    ensured_tab = nil
    cleared_range = nil

    Ec::WeeklyRate.define_singleton_method(:resolve, ->(_date) { rate })
    query = Ec::WeeklySummaryDeepQuery.new(
      from_date: Date.new(2026, 5, 25),
      to_date: Date.new(2026, 5, 31),
      rate: rate
    )
    query.define_singleton_method(:collect_rows) do |from_date, _to_date, _rate|
      rows = from_date == Date.new(2026, 5, 25) ? current_rows : previous_rows
      [rows, { wb: -3.25, ozon: -1.75 }]
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

  def create_sku_with_cost(sku_code, purchase_price_cny:, freight_to_by_cny:, pkg_volume_override_l:)
    @sku_codes << sku_code
    Ec::Sku.create!(
      sku_code: sku_code,
      product_name: "Test #{sku_code}"
    )
    attributes = {
      sku_code: sku_code,
      effective_on: Date.new(2026, 5, 25),
      customs_misc_cny: BigDecimal("0")
    }
    attributes[:purchase_price_cny] = BigDecimal(purchase_price_cny.to_s) unless purchase_price_cny.nil?
    attributes[:freight_to_by_cny] = BigDecimal(freight_to_by_cny.to_s) unless freight_to_by_cny.nil?
    attributes[:pkg_volume_override_l] = BigDecimal(pkg_volume_override_l.to_s) unless pkg_volume_override_l.nil?
    Ec::SkuCost.create!(attributes)
  end
end
