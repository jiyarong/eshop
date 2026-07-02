# Weekly Summary Deep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `WSU-DEEP:W{n}` weekly Google Sheets tab that aggregates weekly profit data to one row per SKU across all platforms and shops, and adds the approved unit-economics and 180-day ROI columns.

**Architecture:** Keep the existing `GoogleSheets::WeeklySummaryService` stable and add a new `GoogleSheets::WeeklySummaryDeepService` that reuses the same weekly attribution collection rules, then aggregates by `sku` only. Extract the 180-day holding-cost ROI math into a pure `Ec::ProjectedStockRoiCalculator` so both `Ec::SkuPeriodRoiQuery` and `WSU-DEEP` use the same formula and edge-case behavior.

**Tech Stack:** Rails 8, ActiveSupport, Minitest, existing `Ec::*` and `GoogleSheets::*` services, Google Sheets base writer helpers.

---

## File Structure

- Create: `app/services/ec/projected_stock_roi_calculator.rb`
  - Pure calculator for 180-day projected stock quantity, predicted storage fee, predicted capital interest, adjusted profit, and ROI.
- Create: `test/services/ec/projected_stock_roi_calculator_test.rb`
  - Covers valid ROI output and blank/invalid edge cases.
- Modify: `app/services/ec/sku_period_roi_query.rb`
  - Replace inline 180-day ROI math with the shared calculator.
- Modify: `test/services/ec/sku_period_roi_query_test.rb`
  - Add delegation coverage and keep the current ROI payload assertions green.
- Create: `app/services/google_sheets/weekly_summary_deep_service.rb`
  - New writer service for `WSU-DEEP:W{n}` with SKU-only aggregation and derived columns.
- Create: `test/services/google_sheets/weekly_summary_deep_service_test.rb`
  - Verifies aggregation, previous-week comparison, derived columns, blank ROI handling, and sheet output shape without hitting Google APIs.
- Modify: `app/services/google_sheets/weekly_profit_report_runner.rb`
  - Add `:wsu_deep` as a runnable weekly-report type and include it in default weekly execution.
- Create: `test/services/google_sheets/weekly_profit_report_runner_test.rb`
  - Verifies `:wsu_deep` dispatch and clear-prefix behavior.

### Task 1: Extract Shared 180-Day ROI Calculator

**Files:**
- Create: `app/services/ec/projected_stock_roi_calculator.rb`
- Create: `test/services/ec/projected_stock_roi_calculator_test.rb`

- [ ] **Step 1: Write the failing calculator tests**

Create `test/services/ec/projected_stock_roi_calculator_test.rb`:

```ruby
require "test_helper"

class Ec::ProjectedStockRoiCalculatorTest < ActiveSupport::TestCase
  test "returns projected holding-cost roi metrics for valid inputs" do
    result = Ec::ProjectedStockRoiCalculator.call(
      net_sales_quantity: 14,
      operating_profit_cny: BigDecimal("337.5"),
      days_count: 7,
      unit_goods_cost_cny: BigDecimal("10"),
      unit_volume_l: BigDecimal("1.0")
    )

    assert_equal true, result[:calculable]
    assert_in_delta 2.0, result[:average_daily_net_sales].to_f, 0.000001
    assert_in_delta 360.0, result[:projected_stock_qty_180d].to_f, 0.000001
    assert_in_delta 180.0, result[:average_inventory_qty].to_f, 0.000001
    assert_in_delta 5.9393, result[:projected_months_to_clear].to_f, 0.001
    assert_in_delta 106.9, result[:predicted_storage_cost_cny].to_f, 0.1
    assert_in_delta 106.9, result[:predicted_interest_cost_cny].to_f, 0.1
    assert_in_delta 3600.0, result[:cost_base_cny].to_f, 0.000001
    assert_in_delta 123.7, result[:adjusted_operating_net_profit_cny].to_f, 0.2
    assert_in_delta 0.0344, result[:roi].to_f, 0.001
  end

  test "returns blank roi when cost or volume inputs are unusable" do
    missing_volume = Ec::ProjectedStockRoiCalculator.call(
      net_sales_quantity: 14,
      operating_profit_cny: BigDecimal("337.5"),
      days_count: 7,
      unit_goods_cost_cny: BigDecimal("10"),
      unit_volume_l: BigDecimal("0")
    )

    assert_equal true, missing_volume[:missing_volume]
    assert_equal false, missing_volume[:calculable]
    assert_nil missing_volume[:predicted_storage_cost_cny]
    assert_nil missing_volume[:predicted_interest_cost_cny]
    assert_nil missing_volume[:adjusted_operating_net_profit_cny]
    assert_nil missing_volume[:roi]
  end
end
```

- [ ] **Step 2: Run the new calculator tests to verify they fail**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/projected_stock_roi_calculator_test.rb'
```

Expected:

- FAIL because `Ec::ProjectedStockRoiCalculator` does not exist yet

- [ ] **Step 3: Write the minimal shared calculator**

Create `app/services/ec/projected_stock_roi_calculator.rb`:

```ruby
module Ec
  class ProjectedStockRoiCalculator
    PROJECTED_DAYS = BigDecimal("180")
    DAYS_PER_WEEK = BigDecimal("7")
    WEEKS_PER_MONTH = BigDecimal("4.33")
    STORAGE_FEE_CNY_PER_M3_MONTH = BigDecimal("100")
    MONTHLY_INTEREST_RATE = BigDecimal("0.01")
    LITERS_PER_CUBIC_METER = BigDecimal("1000")

    def self.call(...)
      new(...).call
    end

    def initialize(net_sales_quantity:, operating_profit_cny:, days_count:, unit_goods_cost_cny:, unit_volume_l:)
      @net_sales_quantity = BigDecimal(net_sales_quantity.to_s)
      @operating_profit_cny = BigDecimal(operating_profit_cny.to_s)
      @days_count = days_count.to_i
      @unit_goods_cost_cny = unit_goods_cost_cny
      @unit_volume_l = unit_volume_l
    end

    def call
      return invalid_payload(missing_cost: true) if missing_or_non_positive?(@unit_goods_cost_cny)
      return invalid_payload(missing_volume: true) if missing_or_non_positive?(@unit_volume_l)
      return invalid_payload(invalid_date_range: true) if @days_count <= 0
      return invalid_payload(non_positive_net_sales: true) if @net_sales_quantity <= 0

      average_daily_net_sales = @net_sales_quantity / BigDecimal(@days_count.to_s)
      projected_stock_qty_180d = average_daily_net_sales * PROJECTED_DAYS
      average_inventory_qty = projected_stock_qty_180d / 2
      projected_weekly_sales = average_daily_net_sales * DAYS_PER_WEEK
      projected_months_to_clear = (projected_stock_qty_180d / projected_weekly_sales) / WEEKS_PER_MONTH
      unit_volume_m3 = BigDecimal(@unit_volume_l.to_s) / LITERS_PER_CUBIC_METER
      predicted_storage_cost_cny = average_inventory_qty * projected_months_to_clear * unit_volume_m3 * STORAGE_FEE_CNY_PER_M3_MONTH
      predicted_interest_cost_cny = average_inventory_qty * projected_months_to_clear * BigDecimal(@unit_goods_cost_cny.to_s) * MONTHLY_INTEREST_RATE
      cost_base_cny = projected_stock_qty_180d * BigDecimal(@unit_goods_cost_cny.to_s)
      adjusted_operating_net_profit_cny = @operating_profit_cny - predicted_storage_cost_cny - predicted_interest_cost_cny

      {
        average_daily_net_sales: average_daily_net_sales,
        projected_stock_qty_180d: projected_stock_qty_180d,
        average_inventory_qty: average_inventory_qty,
        projected_months_to_clear: projected_months_to_clear,
        predicted_storage_cost_cny: predicted_storage_cost_cny,
        predicted_interest_cost_cny: predicted_interest_cost_cny,
        cost_base_cny: cost_base_cny,
        adjusted_operating_net_profit_cny: adjusted_operating_net_profit_cny,
        roi: Ec::RoiCalculator.for_profit_and_cost_base(
          operating_profit: adjusted_operating_net_profit_cny,
          cost_base: cost_base_cny
        )[:roi],
        missing_cost: false,
        missing_volume: false,
        invalid_date_range: false,
        non_positive_net_sales: false,
        calculable: true
      }
    end

    private

    def invalid_payload(missing_cost: false, missing_volume: false, invalid_date_range: false, non_positive_net_sales: false)
      {
        average_daily_net_sales: nil,
        projected_stock_qty_180d: nil,
        average_inventory_qty: nil,
        projected_months_to_clear: nil,
        predicted_storage_cost_cny: nil,
        predicted_interest_cost_cny: nil,
        cost_base_cny: nil,
        adjusted_operating_net_profit_cny: nil,
        roi: nil,
        missing_cost: missing_cost,
        missing_volume: missing_volume,
        invalid_date_range: invalid_date_range,
        non_positive_net_sales: non_positive_net_sales,
        calculable: false
      }
    end

    def missing_or_non_positive?(value)
      value.blank? || BigDecimal(value.to_s) <= 0
    end
  end
end
```

- [ ] **Step 4: Run the calculator tests to verify they pass**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/projected_stock_roi_calculator_test.rb'
```

Expected:

- PASS for both calculator tests

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/projected_stock_roi_calculator.rb test/services/ec/projected_stock_roi_calculator_test.rb
git commit -m "Add projected stock roi calculator"
```

### Task 2: Refactor `Ec::SkuPeriodRoiQuery` To Reuse The Shared Calculator

**Files:**
- Modify: `app/services/ec/sku_period_roi_query.rb`
- Modify: `test/services/ec/sku_period_roi_query_test.rb`

- [ ] **Step 1: Add a failing delegation test**

Append this test to `test/services/ec/sku_period_roi_query_test.rb`:

```ruby
test "delegates bucket roi math to projected stock roi calculator" do
  sku = Ec::Sku.create!(sku_code: @sku_code)
  Ec::SkuCost.create!(
    sku_code: sku.sku_code,
    purchase_price_cny: BigDecimal("20"),
    freight_to_by_cny: BigDecimal("5"),
    customs_misc_cny: BigDecimal("3"),
    customs_duty_rate: BigDecimal("0.1"),
    import_vat_rate: BigDecimal("0.2"),
    pkg_length_cm: BigDecimal("10"),
    pkg_width_cm: BigDecimal("20"),
    pkg_height_cm: BigDecimal("6")
  )

  breakdown_payload = {
    total: { sales_quantity: 12, return_quantity: 2, net_sales_quantity: 10, operating_net_profit_cny: BigDecimal("500") },
    platforms: {
      wb: { sales_quantity: 9, return_quantity: 1, net_sales_quantity: 8, operating_net_profit_cny: BigDecimal("320") },
      ozon: { sales_quantity: 3, return_quantity: 1, net_sales_quantity: 2, operating_net_profit_cny: BigDecimal("180") }
    }
  }

  calculator_calls = []

  with_stubbed_constructor(Ec::SkuPeriodProfitBreakdown, lambda { |**|
    Struct.new(:call).new(breakdown_payload)
  }) do
    Ec::ProjectedStockRoiCalculator.stub(:call, lambda { |**kwargs|
      calculator_calls << kwargs
      {
        average_daily_net_sales: BigDecimal("1"),
        projected_stock_qty_180d: BigDecimal("180"),
        average_inventory_qty: BigDecimal("90"),
        projected_months_to_clear: BigDecimal("5.9"),
        predicted_storage_cost_cny: BigDecimal("6"),
        predicted_interest_cost_cny: BigDecimal("18"),
        cost_base_cny: BigDecimal("6192"),
        adjusted_operating_net_profit_cny: BigDecimal("476"),
        roi: BigDecimal("0.0768"),
        missing_cost: false,
        missing_volume: false,
        invalid_date_range: false,
        non_positive_net_sales: false,
        calculable: true
      }
    }) do
      Ec::SkuPeriodRoiQuery.new(
        sku_code: sku.sku_code,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 10),
        time_zone: "Asia/Shanghai"
      ).call
    end
  end

  assert_equal 3, calculator_calls.size
  assert_equal [10, 8, 2], calculator_calls.map { |call| call[:net_sales_quantity] }
  assert_equal [BigDecimal("500"), BigDecimal("320"), BigDecimal("180")], calculator_calls.map { |call| call[:operating_profit_cny] }
  assert_equal [10, 10, 10], calculator_calls.map { |call| call[:days_count] }
  assert_equal [BigDecimal("34.4000")] * 3, calculator_calls.map { |call| call[:unit_goods_cost_cny] }
  assert_equal [BigDecimal("1.2000")] * 3, calculator_calls.map { |call| call[:unit_volume_l] }
end
```

- [ ] **Step 2: Run the targeted query test to verify it fails**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_period_roi_query_test.rb -n /delegates bucket roi math to projected stock roi calculator/'
```

Expected:

- FAIL because `Ec::SkuPeriodRoiQuery` still computes the bucket math inline

- [ ] **Step 3: Replace inline bucket math with calculator delegation**

Update `app/services/ec/sku_period_roi_query.rb`:

```ruby
def build_bucket(bucket, unit_goods_cost_cny, unit_volume_l)
  bucket = bucket.symbolize_keys

  roi_metrics = Ec::ProjectedStockRoiCalculator.call(
    net_sales_quantity: bucket.fetch(:net_sales_quantity),
    operating_profit_cny: bucket.fetch(:operating_net_profit_cny),
    days_count: days_count,
    unit_goods_cost_cny: unit_goods_cost_cny,
    unit_volume_l: unit_volume_l
  )

  {
    sales_quantity: bucket.fetch(:sales_quantity),
    return_quantity: bucket.fetch(:return_quantity),
    net_sales_quantity: bucket.fetch(:net_sales_quantity),
    average_daily_net_sales: roi_metrics[:average_daily_net_sales],
    projected_stock_qty_180d: roi_metrics[:projected_stock_qty_180d],
    average_inventory_qty: roi_metrics[:average_inventory_qty],
    projected_months_to_clear: roi_metrics[:projected_months_to_clear],
    predicted_storage_cost_cny: roi_metrics[:predicted_storage_cost_cny],
    predicted_interest_cost_cny: roi_metrics[:predicted_interest_cost_cny],
    cost_base_cny: roi_metrics[:cost_base_cny],
    operating_net_profit_cny: bucket.fetch(:operating_net_profit_cny),
    adjusted_operating_net_profit_cny: roi_metrics[:adjusted_operating_net_profit_cny],
    roi: roi_metrics[:roi]
  }
end
```

Also simplify `call` to derive top-level flags from the total bucket instead of reimplementing the same checks:

```ruby
total_bucket = build_bucket(breakdown.fetch(:total), unit_goods_cost_cny, unit_volume_l)
wb_bucket = build_bucket(breakdown.dig(:platforms, :wb), unit_goods_cost_cny, unit_volume_l)
ozon_bucket = build_bucket(breakdown.dig(:platforms, :ozon), unit_goods_cost_cny, unit_volume_l)

{
  sku_code: sku.sku_code,
  from_date: @from_date,
  to_date: @to_date,
  days_count: days_count,
  unit_goods_cost_cny: unit_goods_cost_cny,
  unit_volume_l: unit_volume_l,
  roi_formula: ROI_FORMULA,
  total: total_bucket,
  platforms: { wb: wb_bucket, ozon: ozon_bucket },
  missing_cost: total_bucket[:cost_base_cny].nil? && unit_goods_cost_cny.blank?,
  missing_volume: total_bucket[:predicted_storage_cost_cny].nil? && unit_volume_l.to_d <= 0,
  invalid_date_range: days_count <= 0,
  calculable: total_bucket[:roi].present?
}
```

- [ ] **Step 4: Run the focused query tests to verify the refactor passes**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_period_roi_query_test.rb'
```

Expected:

- PASS for the new delegation test
- PASS for the existing holding-cost ROI assertions

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/sku_period_roi_query.rb test/services/ec/sku_period_roi_query_test.rb
git commit -m "Refactor sku period roi query to shared calculator"
```

### Task 3: Build `GoogleSheets::WeeklySummaryDeepService`

**Files:**
- Create: `app/services/google_sheets/weekly_summary_deep_service.rb`
- Create: `test/services/google_sheets/weekly_summary_deep_service_test.rb`

- [ ] **Step 1: Write the failing service test for SKU aggregation and derived columns**

Create `test/services/google_sheets/weekly_summary_deep_service_test.rb`:

```ruby
require "test_helper"

module GoogleSheets
  class WeeklySummaryDeepServiceTest < ActiveSupport::TestCase
    setup do
      @week_rate = Struct.new(:rate_cny_rub, :rate_byn_rub).new(BigDecimal("0.08"), BigDecimal("3.5"))
      @sku_code = "WSU-DEEP-#{SecureRandom.hex(4)}".upcase

      Ec::Sku.create!(sku_code: @sku_code)
      Ec::SkuCost.create!(
        sku_code: @sku_code,
        purchase_price_cny: BigDecimal("10"),
        freight_to_by_cny: BigDecimal("0"),
        customs_misc_cny: BigDecimal("0"),
        customs_duty_rate: BigDecimal("0"),
        import_vat_rate: BigDecimal("0"),
        pkg_length_cm: BigDecimal("10"),
        pkg_width_cm: BigDecimal("10"),
        pkg_height_cm: BigDecimal("10")
      )
    end

    teardown do
      Ec::SkuCost.where(sku_code: @sku_code).delete_all
      Ec::Sku.with_deleted.where(sku_code: @sku_code).delete_all
    end

    test "writes one row per sku with previous-week comparisons and roi columns" do
      current_rows = [
        { sku: @sku_code, platform: "WB", shop: "Shop A", net_sales: 8, revenue: 760.0, ads: 76.0, goods_cost: 304.0, pre_tax: 200.0, tax: 20.0, after_tax: 180.0 },
        { sku: @sku_code, platform: "Ozon", shop: "Shop B", net_sales: 6, revenue: 570.0, ads: 57.0, goods_cost: 228.0, pre_tax: 175.0, tax: 17.5, after_tax: 157.5 },
        { sku: "OTHER-SKU", platform: "WB", shop: "Shop C", net_sales: 2, revenue: 120.0, ads: 12.0, goods_cost: 40.0, pre_tax: 30.0, tax: 3.0, after_tax: 27.0 }
      ]

      previous_rows = [
        { sku: @sku_code, platform: "WB", shop: "Shop A", net_sales: 5, revenue: 500.0, ads: 50.0, goods_cost: 200.0, pre_tax: 110.0, tax: 11.0, after_tax: 99.0 },
        { sku: @sku_code, platform: "Ozon", shop: "Shop B", net_sales: 4, revenue: 360.0, ads: 36.0, goods_cost: 144.0, pre_tax: 88.0, tax: 8.8, after_tax: 79.2 }
      ]

      writes = {}
      service = GoogleSheets::WeeklySummaryDeepService.new(
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 7),
        week_label: "W23"
      )

      Ec::WeeklyRate.stub(:resolve, @week_rate) do
        service.stub(:collect_rows, lambda { |from_date, *_args|
          from_date == Date.new(2026, 6, 1) ? [current_rows, { wb: -10.0, ozon: -5.0 }] : [previous_rows, { wb: -2.0, ozon: -1.0 }]
        }) do
          service.stub(:ensure_sheet_exists, nil) do
            service.stub(:clear_sheet, nil) do
              service.stub(:sheet_id, 123) do
                service.stub(:batch_update, nil) do
                  service.stub(:write_to_sheet, lambda { |range:, values:| writes[range] = values }) do
                    service.call
                  end
                end
              end
            end
          end
        end
      end

      table = writes.fetch("WSU-DEEP:W23!A1")
      sku_row = table[2]

      assert_equal @sku_code, sku_row[0]
      assert_equal 14, sku_row[1]
      assert_in_delta 1330.0, sku_row[2].to_f, 0.001
      assert_in_delta 133.0, sku_row[3].to_f, 0.001
      assert_in_delta 532.0, sku_row[4].to_f, 0.001
      assert_in_delta 337.5, sku_row[7].to_f, 0.001
      assert_in_delta 25.38, sku_row[8].to_f, 0.05
      assert_in_delta 24.11, sku_row[9].to_f, 0.05
      assert_in_delta 10.0, sku_row[10].to_f, 0.05
      assert_in_delta 63.44, sku_row[11].to_f, 0.1
      assert_in_delta 3.44, sku_row[12].to_f, 0.2
      assert_equal 9, sku_row[13]
      assert_in_delta 860.0, sku_row[14].to_f, 0.001
      assert_in_delta 55.56, sku_row[15].to_f, 0.1
      assert_in_delta 54.65, sku_row[16].to_f, 0.1
    end

    test "leaves roi blank when sku cost volume is unusable" do
      Ec::SkuCost.where(sku_code: @sku_code).delete_all
      Ec::SkuCost.create!(
        sku_code: @sku_code,
        purchase_price_cny: BigDecimal("10"),
        freight_to_by_cny: BigDecimal("0"),
        customs_misc_cny: BigDecimal("0"),
        customs_duty_rate: BigDecimal("0"),
        import_vat_rate: BigDecimal("0"),
        pkg_volume_override_l: BigDecimal("0")
      )

      rows = [
        { sku: @sku_code, platform: "WB", shop: "Shop A", net_sales: 7, revenue: 700.0, ads: 70.0, goods_cost: 280.0, pre_tax: 200.0, tax: 20.0, after_tax: 180.0 }
      ]

      writes = {}
      service = GoogleSheets::WeeklySummaryDeepService.new(
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 7),
        week_label: "W23"
      )

      Ec::WeeklyRate.stub(:resolve, @week_rate) do
        service.stub(:collect_rows, ->(*_args) { [rows, { wb: 0.0, ozon: 0.0 }] }) do
          service.stub(:ensure_sheet_exists, nil) do
            service.stub(:clear_sheet, nil) do
              service.stub(:sheet_id, 123) do
                service.stub(:batch_update, nil) do
                  service.stub(:write_to_sheet, lambda { |range:, values:| writes[range] = values }) do
                    service.call
                  end
                end
              end
            end
          end
        end
      end

      table = writes.fetch("WSU-DEEP:W23!A1")
      assert_nil table[2][12]
    end
  end
end
```

- [ ] **Step 2: Run the new deep-summary tests to verify they fail**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/google_sheets/weekly_summary_deep_service_test.rb'
```

Expected:

- FAIL because `GoogleSheets::WeeklySummaryDeepService` does not exist yet

- [ ] **Step 3: Implement the deep weekly summary writer**

Create `app/services/google_sheets/weekly_summary_deep_service.rb`:

```ruby
module GoogleSheets
  class WeeklySummaryDeepService < WeeklySummaryService
    HDR_ZH = [
      "SKU", "净销量", "销售额(CNY)", "广告费(CNY)", "货物成本(CNY)",
      "税前毛利(CNY)", "税/营业税(CNY)", "税后净利(CNY)", "利润率%",
      "平均每单利润", "广告占比%", "成本回报率%", "ROI(180天备货)%",
      "上周净销量", "上周销售额(CNY)", "销量环比%", "销售额环比%"
    ].freeze

    HDR_RU = [
      "Артикул", "Чистые продажи", "Выручка(CNY)", "Реклама(CNY)", "Себестоимость(CNY)",
      "До налогов(CNY)", "Налог(CNY)", "Чистая прибыль(CNY)", "Рентабельность%",
      "Средняя прибыль/заказ", "Доля рекламы%", "Доходность по себестоимости%", "ROI(180д)%",
      "Продажи пр.н.", "Выручка пр.н.(CNY)", "Δ продаж%", "Δ выручки%"
    ].freeze

    COL_TYPES = %i[text int num num num num num num pct num pct pct pct int num pct pct].freeze
    COL_WIDTHS = [110, 80, 100, 100, 100, 100, 100, 100, 80, 110, 90, 110, 110, 90, 110, 80, 80].freeze

    def self.run(from_date:, to_date:, week_label:)
      new(from_date: from_date, to_date: to_date, week_label: week_label).call
    end

    def call
      rows, @unalloc_cny = collect_rows(@from_date, @to_date, @rate)
      aggregated_rows = aggregate_rows(rows)

      prev_from = @from_date - 7
      prev_to = @to_date - 7
      prev_rate = Ec::WeeklyRate.resolve(prev_from)
      prev_rows, _prev_unalloc = prev_rate ? collect_rows(prev_from, prev_to, prev_rate) : [[], nil]
      prev_map = aggregate_rows(prev_rows).index_by { |row| row[:sku] }

      tab = "WSU-DEEP:#{@week_label}"
      @spreadsheet_sheets = nil
      ensure_sheet_exists(tab)
      clear_sheet(range: "#{tab}!A1:Z")
      sid_pre = sheet_id(tab)
      batch_update([req_clear_format(sid_pre)]) if sid_pre

      data_rows = build_data_rows(aggregated_rows, prev_map)
      total_row = build_total_row(aggregated_rows)
      all_rows = [HDR_ZH, HDR_RU] + data_rows + [total_row]
      write_to_sheet(range: "#{tab}!A1", values: all_rows)

      summary_offset = all_rows.size + 3
      write_to_sheet(range: "#{tab}!A#{summary_offset + 1}", values: build_summary(aggregated_rows))

      @spreadsheet_sheets = nil
      sid = sheet_id(tab)
      if sid
        data_end = 2 + data_rows.size
        reqs = []
        reqs << req_header_rows(sid, num_rows: 2, num_cols: COL_TYPES.size)
        reqs += req_data_rows(sid, start_row: 2, end_row: data_end, col_types: COL_TYPES)
        reqs << req_special_row(sid, row_index: data_end, style: :total, num_cols: COL_TYPES.size)
        reqs << req_freeze_rows(sid, count: 2)
        reqs += req_col_widths(sid, widths: COL_WIDTHS)
        batch_update(reqs)
      end
    end

    private

    def aggregate_rows(rows)
      cost_map = Ec::SkuCost.where(sku_code: rows.map { |row| row[:sku] }.uniq).index_by(&:sku_code)

      rows.group_by { |row| row[:sku] }.map do |sku_code, sku_rows|
        revenue = sku_rows.sum { |row| row[:revenue].to_d }
        ads = sku_rows.sum { |row| row[:ads].to_d }
        goods_cost = sku_rows.sum { |row| row[:goods_cost].to_d }
        pre_tax = sku_rows.sum { |row| row[:pre_tax].to_d }
        tax = sku_rows.sum { |row| row[:tax].to_d }
        after_tax = sku_rows.sum { |row| row[:after_tax].to_d }
        net_sales = sku_rows.sum { |row| row[:net_sales].to_i }
        cost = cost_map[sku_code]
        roi_metrics = Ec::ProjectedStockRoiCalculator.call(
          net_sales_quantity: net_sales,
          operating_profit_cny: after_tax,
          days_count: (@to_date - @from_date).to_i + 1,
          unit_goods_cost_cny: cost&.goods_cost_cny,
          unit_volume_l: cost&.pkg_volume_l
        )

        {
          sku: sku_code,
          net_sales: net_sales,
          revenue: revenue.round(2),
          ads: ads.round(2),
          goods_cost: goods_cost.round(2),
          pre_tax: pre_tax.round(2),
          tax: tax.round(2),
          after_tax: after_tax.round(2),
          margin_pct: percent(after_tax, revenue),
          average_profit_per_unit: net_sales.positive? ? (after_tax / BigDecimal(net_sales.to_s)).round(2) : nil,
          ad_ratio_pct: percent(ads, revenue),
          cost_return_ratio_pct: percent(after_tax, goods_cost),
          roi_180d_pct: roi_metrics[:roi] ? (roi_metrics[:roi] * 100).round(2) : nil
        }
      end.sort_by { |row| -(row[:after_tax] || 0).to_d }
    end

    def build_data_rows(rows, prev_map)
      rows.map do |row|
        prev = prev_map[row[:sku]]
        prev_sales = prev&.dig(:net_sales)
        prev_revenue = prev&.dig(:revenue)

        [
          row[:sku],
          row[:net_sales],
          row[:revenue],
          row[:ads],
          row[:goods_cost],
          row[:pre_tax],
          row[:tax],
          row[:after_tax],
          row[:margin_pct],
          row[:average_profit_per_unit],
          row[:ad_ratio_pct],
          row[:cost_return_ratio_pct],
          row[:roi_180d_pct],
          prev_sales,
          prev_revenue,
          change_pct(row[:net_sales], prev_sales),
          change_pct(row[:revenue], prev_revenue)
        ]
      end
    end

    def build_total_row(rows)
      total_revenue = rows.sum { |row| row[:revenue].to_d }
      total_after_tax = rows.sum { |row| row[:after_tax].to_d }

      [
        "合计 / Итого",
        rows.sum { |row| row[:net_sales].to_i },
        total_revenue.round(2),
        rows.sum { |row| row[:ads].to_d }.round(2),
        rows.sum { |row| row[:goods_cost].to_d }.round(2),
        rows.sum { |row| row[:pre_tax].to_d }.round(2),
        rows.sum { |row| row[:tax].to_d }.round(2),
        total_after_tax.round(2),
        percent(total_after_tax, total_revenue),
        nil, nil, nil, nil, nil, nil, nil, nil
      ]
    end

    def build_summary(rows)
      total_revenue = rows.sum { |row| row[:revenue].to_d }
      total_after_tax = rows.sum { |row| row[:after_tax].to_d }
      total_unalloc = (@unalloc_cny&.dig(:wb).to_d + @unalloc_cny&.dig(:ozon).to_d).round(2)

      [
        ["项目", "金额(CNY)"],
        ["数据周期", "#{@from_date} ~ #{@to_date}"],
        ["汇率 CNY/RUB", @rate.rate_cny_rub],
        ["汇率 BYN/RUB", @rate.rate_byn_rub],
        [],
        ["SKU行数", rows.size],
        ["总销售额", total_revenue.round(2)],
        ["总税后净利", total_after_tax.round(2)],
        ["综合利润率", percent(total_after_tax, total_revenue)],
        [],
        ["WB 未分摊", @unalloc_cny&.dig(:wb).to_d.round(2)],
        ["Ozon 未分摊", @unalloc_cny&.dig(:ozon).to_d.round(2)],
        ["未分摊合计", total_unalloc],
        ["税后净利（含未分摊）", (total_after_tax + total_unalloc).round(2)]
      ]
    end

    def percent(numerator, denominator)
      return nil if denominator.to_d <= 0

      (numerator.to_d / denominator.to_d * 100).round(2)
    end

    def change_pct(current_value, previous_value)
      return nil if previous_value.to_d <= 0

      ((current_value.to_d - previous_value.to_d) / previous_value.to_d * 100).round(2)
    end
  end
end
```

- [ ] **Step 4: Run the deep-summary tests to verify they pass**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/google_sheets/weekly_summary_deep_service_test.rb'
```

Expected:

- PASS for SKU aggregation
- PASS for previous-week comparison
- PASS for blank ROI when cost volume is unusable

- [ ] **Step 5: Commit**

```bash
git add app/services/google_sheets/weekly_summary_deep_service.rb test/services/google_sheets/weekly_summary_deep_service_test.rb
git commit -m "Add weekly summary deep sheet service"
```

### Task 4: Wire `WSU-DEEP` Into The Weekly Report Runner

**Files:**
- Modify: `app/services/google_sheets/weekly_profit_report_runner.rb`
- Create: `test/services/google_sheets/weekly_profit_report_runner_test.rb`

- [ ] **Step 1: Write the failing runner test**

Create `test/services/google_sheets/weekly_profit_report_runner_test.rb`:

```ruby
require "test_helper"

module GoogleSheets
  class WeeklyProfitReportRunnerTest < ActiveSupport::TestCase
    test "runs weekly summary deep by default" do
      rate = Struct.new(:rate_cny_rub, :rate_byn_rub).new(BigDecimal("0.08"), BigDecimal("3.5"))
      calls = []

      Ec::WeeklyRate.stub(:resolve, rate) do
        GoogleSheets::WeeklySummaryDeepService.stub(:run, ->(**kwargs) { calls << kwargs }) do
          GoogleSheets::WeeklyProfitReportRunner.run(
            from_date: Date.new(2026, 6, 1),
            to_date: Date.new(2026, 6, 7)
          )
        end
      end

      assert_equal 1, calls.size
      assert_equal Date.new(2026, 6, 1), calls.first[:from_date]
      assert_equal Date.new(2026, 6, 7), calls.first[:to_date]
      assert_equal "W23", calls.first[:week_label]
    end

    test "clears wsu deep tabs when requested" do
      rate = Struct.new(:rate_cny_rub, :rate_byn_rub).new(BigDecimal("0.08"), BigDecimal("3.5"))
      deleted_prefixes = []

      Ec::WeeklyRate.stub(:resolve, rate) do
        runner = GoogleSheets::WeeklyProfitReportRunner.new
        runner.stub(:delete_sheets_with_prefix, ->(prefix) { deleted_prefixes << prefix }) do
          GoogleSheets::WeeklySummaryDeepService.stub(:run, ->(**) { nil }) do
            GoogleSheets::WeeklyProfitReportRunner.run(
              from_date: Date.new(2026, 6, 1),
              to_date: Date.new(2026, 6, 7),
              types: [:wsu_deep],
              clear: true
            )
          end
        end
      end

      assert_includes deleted_prefixes, "WSU-DEEP:"
    end
  end
end
```

- [ ] **Step 2: Run the runner tests to verify they fail**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/google_sheets/weekly_profit_report_runner_test.rb'
```

Expected:

- FAIL because `:wsu_deep` is not yet a supported runner type

- [ ] **Step 3: Add `:wsu_deep` dispatch and clear-prefix handling**

Update `app/services/google_sheets/weekly_profit_report_runner.rb`:

```ruby
ALL_TYPES = %i[wr_wb wod_wb wr_ozon wsu_deep].freeze
```

Update `clear_all`:

```ruby
def self.clear_all
  svc = new
  svc.send(:delete_sheets_with_prefix, "WR:")
  svc.send(:delete_sheets_with_prefix, "WOD:")
  svc.send(:delete_sheets_with_prefix, "WSU-DEEP:")
  puts "✓ 已清除所有 WR: / WOD: / WSU-DEEP: tab"
end
```

Update the `clear` block:

```ruby
if clear
  new.send(:delete_sheets_with_prefix, "WR:") if (active_types & %i[wr_wb wr_ozon]).any?
  new.send(:delete_sheets_with_prefix, "WOD:") if active_types.include?(:wod_wb)
  new.send(:delete_sheets_with_prefix, "WSU-DEEP:") if active_types.include?(:wsu_deep)
  puts "✓ 已清除对应 tab 前缀"
end
```

Add the new dispatch inside the week loop:

```ruby
if active_types.include?(:wsu_deep)
  WeeklySummaryDeepService.run(
    from_date: from,
    to_date: to,
    week_label: week_label
  )
end
```

- [ ] **Step 4: Run the runner tests and the new deep-summary tests together**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/google_sheets/weekly_profit_report_runner_test.rb test/services/google_sheets/weekly_summary_deep_service_test.rb'
```

Expected:

- PASS for runner dispatch
- PASS for clear-prefix handling
- PASS for the deep-summary sheet writer

- [ ] **Step 5: Commit**

```bash
git add app/services/google_sheets/weekly_profit_report_runner.rb test/services/google_sheets/weekly_profit_report_runner_test.rb
git commit -m "Wire weekly summary deep into report runner"
```

### Task 5: Final Verification

**Files:**
- Verify: `app/services/ec/projected_stock_roi_calculator.rb`
- Verify: `app/services/ec/sku_period_roi_query.rb`
- Verify: `app/services/google_sheets/weekly_summary_deep_service.rb`
- Verify: `app/services/google_sheets/weekly_profit_report_runner.rb`
- Verify: `test/services/ec/projected_stock_roi_calculator_test.rb`
- Verify: `test/services/ec/sku_period_roi_query_test.rb`
- Verify: `test/services/google_sheets/weekly_summary_deep_service_test.rb`
- Verify: `test/services/google_sheets/weekly_profit_report_runner_test.rb`

- [ ] **Step 1: Run the full targeted test set**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/projected_stock_roi_calculator_test.rb test/services/ec/sku_period_roi_query_test.rb test/services/google_sheets/weekly_summary_deep_service_test.rb test/services/google_sheets/weekly_profit_report_runner_test.rb'
```

Expected:

- PASS for all ROI helper, SKU-period ROI, WSU-DEEP, and runner tests

- [ ] **Step 2: Run a broader regression slice for nearby report logic**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_period_profit_breakdown_test.rb test/services/ec/roi_calculator_test.rb'
```

Expected:

- PASS for the existing profit-breakdown and ROI-calculator coverage

- [ ] **Step 3: Inspect the diff before handoff**

Run:

```bash
git diff -- app/services/ec/projected_stock_roi_calculator.rb app/services/ec/sku_period_roi_query.rb app/services/google_sheets/weekly_summary_deep_service.rb app/services/google_sheets/weekly_profit_report_runner.rb test/services/ec/projected_stock_roi_calculator_test.rb test/services/ec/sku_period_roi_query_test.rb test/services/google_sheets/weekly_summary_deep_service_test.rb test/services/google_sheets/weekly_profit_report_runner_test.rb
```

Expected:

- only the new helper, query refactor, WSU-DEEP service, runner hook, and related tests are present

- [ ] **Step 4: Commit the verification-complete state**

```bash
git add app/services/ec/projected_stock_roi_calculator.rb app/services/ec/sku_period_roi_query.rb app/services/google_sheets/weekly_summary_deep_service.rb app/services/google_sheets/weekly_profit_report_runner.rb test/services/ec/projected_stock_roi_calculator_test.rb test/services/ec/sku_period_roi_query_test.rb test/services/google_sheets/weekly_summary_deep_service_test.rb test/services/google_sheets/weekly_profit_report_runner_test.rb
git commit -m "Add WSU-DEEP weekly sku summary"
```

## Self-Review

- Spec coverage:
  - one-row-per-SKU aggregation is covered in Task 3
  - previous-week comparison by SKU is covered in Task 3
  - `平均每单利润`, `广告占比`, `成本回报率`, and `ROI(180天备货)` are covered in Task 3
  - shared 180-day ROI logic is covered in Tasks 1 and 2
  - weekly-runner integration is covered in Task 4
- Placeholder scan:
  - no `TODO`, `TBD`, or “similar to” shortcuts remain
- Type consistency:
  - ROI helper returns raw ratio values
  - `WSU-DEEP` converts ratio outputs to percentage points for sheet display, matching current `WSU:` margin-column style

