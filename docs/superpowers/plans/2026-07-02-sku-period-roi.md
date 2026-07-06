# SKU Period ROI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable service that returns per-SKU ROI for a selected time window using operating profit minus predicted holding costs and a 180-day projected stocking cost base, with total and per-platform breakdowns.

**Architecture:** Add a query-style service `Ec::SkuPeriodRoiQuery` that orchestrates ROI calculation for one SKU and one date range. Add a focused aggregation service `Ec::SkuPeriodProfitBreakdown` that reuses `Ec::WbProfitAttribution` and `Ec::OzonProfitAttribution`, and extend `Ec::RoiCalculator` with a formula mode for `profit / cost_base` so query code does not inline ratio math. The query service also derives predicted storage cost and predicted capital-interest cost from `Ec::SkuCost#pkg_volume_l`, fixed storage fee `100 CNY / m³ / month`, fixed monthly interest `1%`, and the same projected stock quantity window.

**Tech Stack:** Rails 8, ActiveSupport, Minitest, existing `Ec::*` service layer, existing WB/Ozon profit-attribution services.

---

## File Structure

- Create: `app/services/ec/sku_period_profit_breakdown.rb`
  - Aggregates per-platform raw metrics for one SKU in one period.
- Create: `app/services/ec/sku_period_roi_query.rb`
  - Loads SKU and cost, invokes the breakdown service, computes predicted holding costs, and returns total and per-platform ROI payloads.
- Modify: `app/services/ec/roi_calculator.rb`
  - Keep current HTML-calculator behavior intact and add a second formula entry point for `operating_profit / cost_base`.
- Create: `test/services/ec/sku_period_profit_breakdown_test.rb`
  - Verifies breakdown output against stubbed platform attribution services and SKU binding rules.
- Create: `test/services/ec/sku_period_roi_query_test.rb`
  - Verifies total ROI, platform ROI, predicted storage and interest costs, missing-cost handling, missing-volume handling, and nil ROI edge cases.
- Modify: `test/services/ec/roi_calculator_test.rb`
  - Adds coverage for the new formula-only ROI API.

### Task 1: Extend `Ec::RoiCalculator` For Period ROI Formula

**Files:**
- Modify: `app/services/ec/roi_calculator.rb`
- Modify: `test/services/ec/roi_calculator_test.rb`

- [ ] **Step 1: Write the failing test for formula-only ROI**

Add this test to `test/services/ec/roi_calculator_test.rb`:

```ruby
test "returns roi from operating profit and cost base" do
  result = Ec::RoiCalculator.for_profit_and_cost_base(
    operating_profit: 4200,
    cost_base: 23856
  )

  assert_in_delta 0.1761402, result[:roi], 0.000001
end
```

- [ ] **Step 2: Run the targeted test to verify it fails**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/roi_calculator_test.rb -n /returns roi from operating profit and cost base/'
```

Expected:

- test fails with `NoMethodError` or `NameError` because `for_profit_and_cost_base` does not exist yet

- [ ] **Step 3: Write the minimal implementation**

Update `app/services/ec/roi_calculator.rb` to add a second public entry point without disturbing the current HTML-oriented API:

```ruby
def self.for_profit_and_cost_base(operating_profit:, cost_base:)
  operating_profit = BigDecimal(operating_profit.to_s)
  cost_base = BigDecimal(cost_base.to_s)

  return { roi: nil } if cost_base <= 0

  { roi: operating_profit / cost_base }
end
```

- [ ] **Step 4: Run the targeted test to verify it passes**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/roi_calculator_test.rb -n /returns roi from operating profit and cost base/'
```

Expected:

- PASS for the new test

- [ ] **Step 5: Commit**

```bash
git add test/services/ec/roi_calculator_test.rb app/services/ec/roi_calculator.rb
git commit -m "Add formula mode to ROI calculator"
```

### Task 2: Add Breakdown Service Test First

**Files:**
- Create: `test/services/ec/sku_period_profit_breakdown_test.rb`
- Test helpers referenced: `test/test_helper.rb`

- [ ] **Step 1: Write the failing test for per-platform aggregation**

Create `test/services/ec/sku_period_profit_breakdown_test.rb` with:

```ruby
require "test_helper"

class Ec::SkuPeriodProfitBreakdownTest < ActiveSupport::TestCase
  test "aggregates wb and ozon metrics for one sku" do
    sku = Struct.new(:sku_code).new("ROI-SKU-1")

    wb_service = Struct.new(:results).new([
      { vendor_code: "ROI-SKU-1", sales_qty: 70, return_qty: 5, net_qty: 65, pre_tax: 2600.0 },
      { vendor_code: "OTHER-SKU", sales_qty: 20, return_qty: 1, net_qty: 19, pre_tax: 999.0 }
    ])

    ozon_service = Struct.new(:results).new([
      { sku_code: "ROI-SKU-1", order_count: 50, return_count: 3, net_sales_count: 47, pre_tax_profit: 1600.0 },
      { sku_code: "OTHER-SKU", order_count: 10, return_count: 0, net_sales_count: 10, pre_tax_profit: 500.0 }
    ])

    breakdown = Ec::SkuPeriodProfitBreakdown.new(
      sku: sku,
      from_date: Date.new(2026, 6, 1),
      to_date: Date.new(2026, 6, 30),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      wb_attributions: [wb_service],
      ozon_attributions: [ozon_service]
    ).call

    assert_equal 70, breakdown.dig(:platforms, :wb, :sales_quantity)
    assert_equal 5, breakdown.dig(:platforms, :wb, :return_quantity)
    assert_equal 65, breakdown.dig(:platforms, :wb, :net_sales_quantity)
    assert_equal BigDecimal("2600.0"), breakdown.dig(:platforms, :wb, :operating_net_profit_cny)

    assert_equal 50, breakdown.dig(:platforms, :ozon, :sales_quantity)
    assert_equal 3, breakdown.dig(:platforms, :ozon, :return_quantity)
    assert_equal 47, breakdown.dig(:platforms, :ozon, :net_sales_quantity)
    assert_equal BigDecimal("1600.0"), breakdown.dig(:platforms, :ozon, :operating_net_profit_cny)

    assert_equal 120, breakdown.dig(:total, :sales_quantity)
    assert_equal 8, breakdown.dig(:total, :return_quantity)
    assert_equal 112, breakdown.dig(:total, :net_sales_quantity)
    assert_equal BigDecimal("4200.0"), breakdown.dig(:total, :operating_net_profit_cny)
  end
end
```

- [ ] **Step 2: Run the breakdown test to verify it fails**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_period_profit_breakdown_test.rb'
```

Expected:

- FAIL because `Ec::SkuPeriodProfitBreakdown` does not exist yet

- [ ] **Step 3: Write the minimal breakdown implementation**

Create `app/services/ec/sku_period_profit_breakdown.rb` with:

```ruby
module Ec
  class SkuPeriodProfitBreakdown
    def initialize(sku:, from_date:, to_date:, time_zone:, wb_attributions: nil, ozon_attributions: nil)
      @sku = sku
      @from_date = from_date
      @to_date = to_date
      @time_zone = time_zone
      @wb_attributions = wb_attributions
      @ozon_attributions = ozon_attributions
    end

    def call
      wb = wb_metrics
      ozon = ozon_metrics

      {
        platforms: {
          wb: wb,
          ozon: ozon
        },
        total: {
          sales_quantity: wb[:sales_quantity] + ozon[:sales_quantity],
          return_quantity: wb[:return_quantity] + ozon[:return_quantity],
          net_sales_quantity: wb[:net_sales_quantity] + ozon[:net_sales_quantity],
          operating_net_profit_cny: wb[:operating_net_profit_cny] + ozon[:operating_net_profit_cny]
        }
      }
    end

    private

    attr_reader :sku, :from_date, :to_date, :time_zone, :wb_attributions, :ozon_attributions

    def wb_metrics
      result = Array(wb_results).find { |row| row[:vendor_code].to_s.casecmp?(sku.sku_code.to_s) } || {}

      {
        sales_quantity: result[:sales_qty].to_i,
        return_quantity: result[:return_qty].to_i,
        net_sales_quantity: result[:net_qty].to_i,
        operating_net_profit_cny: BigDecimal((result[:pre_tax] || 0).to_s)
      }
    end

    def ozon_metrics
      result = Array(ozon_results).find { |row| row[:sku_code].to_s.casecmp?(sku.sku_code.to_s) } || {}

      {
        sales_quantity: result[:order_count].to_i,
        return_quantity: result[:return_count].to_i,
        net_sales_quantity: result[:net_sales_count].to_i,
        operating_net_profit_cny: BigDecimal((result[:pre_tax_profit] || 0).to_s)
      }
    end

    def wb_results
      Array(wb_attributions).flat_map { |service| service.results }
    end

    def ozon_results
      Array(ozon_attributions).flat_map { |service| service.results }
    end
  end
end
```

- [ ] **Step 4: Run the breakdown test to verify it passes**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_period_profit_breakdown_test.rb'
```

Expected:

- PASS for the aggregation test

- [ ] **Step 5: Commit**

```bash
git add test/services/ec/sku_period_profit_breakdown_test.rb app/services/ec/sku_period_profit_breakdown.rb
git commit -m "Add SKU period profit breakdown service"
```

### Task 3: Replace Stub Injection With Real Store/Account Resolution

**Files:**
- Modify: `app/services/ec/sku_period_profit_breakdown.rb`
- Modify: `test/services/ec/sku_period_profit_breakdown_test.rb`

- [ ] **Step 1: Write the failing integration-style breakdown test**

Append this test to `test/services/ec/sku_period_profit_breakdown_test.rb`:

```ruby
test "calls platform attribution services for stores bound to the sku" do
  token = SecureRandom.hex(4).upcase
  sku = Ec::Sku.create!(sku_code: "ROI-#{token}", product_name: "ROI SKU")

  wb_account = RawWb::SellerAccount.create!(name: "wb-#{token}", api_token: "token-#{token}", company_type: "small")
  wb_store = Ec::Store.create!(platform: "wb", store_name: "WB ROI #{token}", company_type: "small", wb_raw_account_id: wb_account.id, is_active: true)
  ozon_account = RawOzon::SellerAccount.create!(company_name: "ozon-#{token}", client_id: "client-#{token}", api_key: "key-#{token}", company_type: "small")
  ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon ROI #{token}", company_type: "small", ozon_raw_account_id: ozon_account.id, is_active: true)

  Ec::SkuProduct.create!(sku_code: sku.sku_code, store: wb_store, product_id: "WB-#{token}", platform_sku_id: "WB-SKU-#{token}")
  Ec::SkuProduct.create!(sku_code: sku.sku_code, store: ozon_store, product_id: "OZON-#{token}", platform_sku_id: "OZON-SKU-#{token}", offer_id: "OFFER-#{token}")

  wb_double = Struct.new(:results).new([{ vendor_code: sku.sku_code, sales_qty: 10, return_qty: 2, net_qty: 8, pre_tax: 320.0 }])
  ozon_double = Struct.new(:results).new([{ sku_code: sku.sku_code, order_count: 5, return_count: 1, net_sales_count: 4, pre_tax_profit: 180.0 }])

  Ec::WbProfitAttribution.stub(:new, ->(**) { wb_double }) do
    Ec::OzonProfitAttribution.stub(:new, ->(**) { ozon_double }) do
      breakdown = Ec::SkuPeriodProfitBreakdown.new(
        sku: sku,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 30),
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      assert_equal 15, breakdown.dig(:total, :sales_quantity)
      assert_equal 3, breakdown.dig(:total, :return_quantity)
      assert_equal 12, breakdown.dig(:total, :net_sales_quantity)
      assert_equal BigDecimal("500.0"), breakdown.dig(:total, :operating_net_profit_cny)
    end
  end
ensure
  Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
  Ec::Store.where(id: [wb_store&.id, ozon_store&.id]).delete_all
  RawWb::SellerAccount.where(id: wb_account&.id).delete_all
  RawOzon::SellerAccount.where(id: ozon_account&.id).delete_all
  Ec::Sku.with_deleted.where(id: sku&.id).delete_all
end
```

- [ ] **Step 2: Run the breakdown test to verify it fails for missing real resolution**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_period_profit_breakdown_test.rb -n /calls platform attribution services for stores bound to the sku/'
```

Expected:

- FAIL because the service does not yet resolve bound stores/accounts and instantiate attribution services

- [ ] **Step 3: Implement real bound-store iteration**

Update `app/services/ec/sku_period_profit_breakdown.rb` so that, when explicit service doubles are not injected, it:

```ruby
def wb_results
  return Array(wb_attributions).flat_map { |service| service.results } if wb_attributions

  wb_bound_stores.flat_map do |store|
    Ec::WbProfitAttribution.new(
      account_id: store.wb_raw_account_id,
      from_date: from_date,
      to_date: to_date,
      rate_cny_rub: wb_rate_cny_rub,
      rate_byn_rub: wb_rate_byn_rub
    ).call.results
  end
end

def ozon_results
  return Array(ozon_attributions).flat_map { |service| service.results } if ozon_attributions

  ozon_bound_stores.flat_map do |store|
    Ec::OzonProfitAttribution.new(
      account_id: store.ozon_raw_account_id,
      from_date: from_date,
      to_date: to_date
    ).call.results
  end
end

def wb_bound_stores
  @wb_bound_stores ||= sku.sku_products.includes(:store).map(&:store).compact.select { |store| store.platform == "wb" && store.wb_raw_account_id.present? }
end

def ozon_bound_stores
  @ozon_bound_stores ||= sku.sku_products.includes(:store).map(&:store).compact.select { |store| store.platform == "ozon" && store.ozon_raw_account_id.present? }
end
```

Also add small private rate helpers that use the same fallback constants the existing attribution services already tolerate:

```ruby
def wb_rate_cny_rub
  11.0
end

def wb_rate_byn_rub
  3.5
end
```

- [ ] **Step 4: Run the full breakdown test file**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_period_profit_breakdown_test.rb'
```

Expected:

- PASS for both breakdown tests

- [ ] **Step 5: Commit**

```bash
git add test/services/ec/sku_period_profit_breakdown_test.rb app/services/ec/sku_period_profit_breakdown.rb
git commit -m "Resolve platform attributions for SKU period breakdown"
```

### Task 4: Add Query Service Test First

**Files:**
- Create: `test/services/ec/sku_period_roi_query_test.rb`
- Test setup references: `app/models/ec/sku.rb`, `app/models/ec/sku_cost.rb`

- [ ] **Step 1: Write the failing query-service tests**

Create `test/services/ec/sku_period_roi_query_test.rb` with:

```ruby
require "test_helper"

class Ec::SkuPeriodRoiQueryTest < ActiveSupport::TestCase
  setup do
    @sku = Ec::Sku.create!(sku_code: "ROI-Q-#{SecureRandom.hex(4).upcase}", product_name: "ROI Query SKU")
    @sku.cost&.destroy
    Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      purchase_price_cny: 10,
      freight_to_by_cny: 2,
      customs_misc_cny: 1,
      customs_duty_rate: 0.1,
      import_vat_rate: 0.2
    )
  end

  teardown do
    Ec::SkuCost.where(sku_code: @sku.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "returns total roi and platform roi using 180 day projected stock base and predicted holding costs" do
    fake_breakdown = {
      platforms: {
        wb: { sales_quantity: 70, return_quantity: 5, net_sales_quantity: 65, operating_net_profit_cny: BigDecimal("2600") },
        ozon: { sales_quantity: 50, return_quantity: 3, net_sales_quantity: 47, operating_net_profit_cny: BigDecimal("1600") }
      },
      total: {
        sales_quantity: 120,
        return_quantity: 8,
        net_sales_quantity: 112,
        operating_net_profit_cny: BigDecimal("4200")
      }
    }

    Ec::SkuPeriodProfitBreakdown.stub(:new, ->(**) { Struct.new(:call).new(fake_breakdown) }) do
      payload = Ec::SkuPeriodRoiQuery.new(
        sku_code: @sku.sku_code,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 30),
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      assert_equal 30, payload[:days_count]
      assert_equal 112, payload.dig(:total, :net_sales_quantity)
      assert_in_delta 72, payload.dig(:total, :projected_stock_qty_180d), 0.0001
      assert_in_delta 36, payload.dig(:total, :average_inventory_qty), 0.0001
      assert_in_delta 5.9347, payload.dig(:total, :projected_months_to_clear), 0.0001
      assert_in_delta 1.0682, payload.dig(:total, :predicted_storage_cost_cny), 0.0001
      assert_in_delta 73.4694, payload.dig(:total, :predicted_interest_cost_cny), 0.0001
      assert_in_delta 2476.8, payload.dig(:total, :cost_base_cny), 0.0001
      assert_in_delta 0.1710, payload.dig(:total, :roi), 0.0001
      assert payload[:calculable]
      refute payload[:missing_cost]
    end
  end

  test "returns nil roi and missing_cost when standard cost is unavailable" do
    Ec::SkuCost.where(sku_code: @sku.sku_code).delete_all

    fake_breakdown = {
      platforms: { wb: { sales_quantity: 1, return_quantity: 0, net_sales_quantity: 1, operating_net_profit_cny: BigDecimal("10") }, ozon: { sales_quantity: 0, return_quantity: 0, net_sales_quantity: 0, operating_net_profit_cny: BigDecimal("0") } },
      total: { sales_quantity: 1, return_quantity: 0, net_sales_quantity: 1, operating_net_profit_cny: BigDecimal("10") }
    }

    Ec::SkuPeriodProfitBreakdown.stub(:new, ->(**) { Struct.new(:call).new(fake_breakdown) }) do
      payload = Ec::SkuPeriodRoiQuery.new(
        sku_code: @sku.sku_code,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 30),
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      assert_nil payload.dig(:total, :roi)
      assert_equal true, payload[:missing_cost]
      assert_equal false, payload[:calculable]
    end
  end
end
```

- [ ] **Step 2: Run the query-service tests to verify they fail**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_period_roi_query_test.rb'
```

Expected:

- FAIL because `Ec::SkuPeriodRoiQuery` does not exist yet

- [ ] **Step 3: Write the minimal query service**

Create `app/services/ec/sku_period_roi_query.rb` with:

```ruby
module Ec
  class SkuPeriodRoiQuery
    PROJECTED_DAYS = BigDecimal("180")

    def initialize(sku_code:, from_date:, to_date:, time_zone:)
      @sku_code = sku_code
      @from_date = from_date
      @to_date = to_date
      @time_zone = time_zone
    end

    def call
      sku = Ec::Sku.find_by!(sku_code: @sku_code)
      breakdown = Ec::SkuPeriodProfitBreakdown.new(
        sku: sku,
        from_date: @from_date,
        to_date: @to_date,
        time_zone: @time_zone
      ).call

      unit_cost = sku.cost&.goods_cost_cny
      unit_volume_l = sku.cost&.pkg_volume_l
      missing_cost = unit_cost.blank? || unit_cost.to_d <= 0
      missing_volume = unit_volume_l.blank? || unit_volume_l.to_d <= 0
      days_count = ((@to_date.to_date - @from_date.to_date).to_i + 1)

      payload = {
        sku_code: sku.sku_code,
        from_date: @from_date,
        to_date: @to_date,
        days_count: days_count,
        unit_goods_cost_cny: unit_cost,
        unit_volume_l: unit_volume_l,
        roi_formula: "adjusted_operating_net_profit / (projected_stock_qty_180d * unit_goods_cost_cny)",
        total: build_bucket(breakdown[:total], days_count, unit_cost, unit_volume_l),
        platforms: {
          wb: build_bucket(breakdown.dig(:platforms, :wb), days_count, unit_cost, unit_volume_l),
          ozon: build_bucket(breakdown.dig(:platforms, :ozon), days_count, unit_cost, unit_volume_l)
        }
      }

      payload[:missing_cost] = missing_cost
      payload[:missing_volume] = missing_volume
      payload[:calculable] = payload.dig(:total, :roi).present?
      payload
    end

    private

    def build_bucket(bucket, days_count, unit_cost, unit_volume_l)
      net_sales = bucket[:net_sales_quantity].to_i
      average_daily = days_count.positive? ? BigDecimal(net_sales.to_s) / BigDecimal(days_count.to_s) : nil
      projected_qty = average_daily ? average_daily * PROJECTED_DAYS : nil
      average_inventory_qty = projected_qty ? projected_qty / 2 : nil
      projected_months_to_clear = average_daily && average_daily.positive? ? (projected_qty / (average_daily * 7)) / BigDecimal("4.33") : nil
      unit_volume_m3 = unit_volume_l ? unit_volume_l.to_d / 1000 : nil
      predicted_storage_cost = average_inventory_qty && projected_months_to_clear && unit_volume_m3 ? average_inventory_qty * projected_months_to_clear * unit_volume_m3 * 100 : nil
      predicted_interest_cost = average_inventory_qty && projected_months_to_clear && unit_cost ? average_inventory_qty * projected_months_to_clear * unit_cost.to_d * BigDecimal("0.01") : nil
      cost_base = projected_qty && unit_cost ? projected_qty * unit_cost.to_d : nil
      adjusted_profit = predicted_storage_cost && predicted_interest_cost ? bucket[:operating_net_profit_cny] - predicted_storage_cost - predicted_interest_cost : nil
      roi_result = cost_base && adjusted_profit ? Ec::RoiCalculator.for_profit_and_cost_base(operating_profit: adjusted_profit, cost_base: cost_base) : { roi: nil }

      {
        sales_quantity: bucket[:sales_quantity].to_i,
        return_quantity: bucket[:return_quantity].to_i,
        net_sales_quantity: net_sales,
        average_daily_net_sales: average_daily,
        projected_stock_qty_180d: projected_qty,
        average_inventory_qty: average_inventory_qty,
        projected_months_to_clear: projected_months_to_clear,
        predicted_storage_cost_cny: predicted_storage_cost,
        predicted_interest_cost_cny: predicted_interest_cost,
        cost_base_cny: cost_base,
        operating_net_profit_cny: bucket[:operating_net_profit_cny],
        adjusted_operating_net_profit_cny: adjusted_profit,
        roi: (net_sales <= 0 || days_count <= 0 || unit_cost.blank? || unit_cost.to_d <= 0) ? nil : roi_result[:roi]
      }
    end
  end
end
```

- [ ] **Step 4: Run the query-service tests to verify they pass**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_period_roi_query_test.rb'
```

Expected:

- PASS for both query-service tests

- [ ] **Step 5: Commit**

```bash
git add test/services/ec/sku_period_roi_query_test.rb app/services/ec/sku_period_roi_query.rb
git commit -m "Add SKU period ROI query service"
```

### Task 5: Add Edge-Case Coverage For Nil ROI

**Files:**
- Modify: `test/services/ec/sku_period_roi_query_test.rb`
- Modify: `app/services/ec/sku_period_roi_query.rb`

- [ ] **Step 1: Write the failing edge-case test**

Append this test to `test/services/ec/sku_period_roi_query_test.rb`:

```ruby
test "returns nil roi when total net sales are zero" do
  fake_breakdown = {
    platforms: {
      wb: { sales_quantity: 4, return_quantity: 4, net_sales_quantity: 0, operating_net_profit_cny: BigDecimal("0") },
      ozon: { sales_quantity: 0, return_quantity: 0, net_sales_quantity: 0, operating_net_profit_cny: BigDecimal("0") }
    },
    total: {
      sales_quantity: 4,
      return_quantity: 4,
      net_sales_quantity: 0,
      operating_net_profit_cny: BigDecimal("0")
    }
  }

  Ec::SkuPeriodProfitBreakdown.stub(:new, ->(**) { Struct.new(:call).new(fake_breakdown) }) do
    payload = Ec::SkuPeriodRoiQuery.new(
      sku_code: @sku.sku_code,
      from_date: Date.new(2026, 6, 1),
      to_date: Date.new(2026, 6, 30),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
    ).call

    assert_nil payload.dig(:total, :roi)
    assert_equal false, payload[:calculable]
  end
end

test "returns nil roi when sku package volume is unavailable" do
  Ec::SkuCost.where(sku_code: @sku.sku_code).delete_all
  Ec::SkuCost.create!(
    sku_code: @sku.sku_code,
    purchase_price_cny: 10,
    freight_to_by_cny: 2,
    customs_misc_cny: 1,
    customs_duty_rate: 0.1,
    import_vat_rate: 0.2,
    pkg_length_cm: nil,
    pkg_width_cm: nil,
    pkg_height_cm: nil,
    pkg_volume_override_l: nil
  )

  fake_breakdown = {
    platforms: {
      wb: { sales_quantity: 1, return_quantity: 0, net_sales_quantity: 1, operating_net_profit_cny: BigDecimal("10") },
      ozon: { sales_quantity: 0, return_quantity: 0, net_sales_quantity: 0, operating_net_profit_cny: BigDecimal("0") }
    },
    total: { sales_quantity: 1, return_quantity: 0, net_sales_quantity: 1, operating_net_profit_cny: BigDecimal("10") }
  }

  Ec::SkuPeriodProfitBreakdown.stub(:new, ->(**) { Struct.new(:call).new(fake_breakdown) }) do
    payload = Ec::SkuPeriodRoiQuery.new(
      sku_code: @sku.sku_code,
      from_date: Date.new(2026, 6, 1),
      to_date: Date.new(2026, 6, 30),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
    ).call

    assert_nil payload.dig(:total, :predicted_storage_cost_cny)
    assert_nil payload.dig(:total, :predicted_interest_cost_cny)
    assert_nil payload.dig(:total, :adjusted_operating_net_profit_cny)
    assert_nil payload.dig(:total, :roi)
    assert_equal false, payload[:calculable]
  end
end
```

- [ ] **Step 2: Run the edge-case test to verify it fails**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_period_roi_query_test.rb -n /returns nil roi when total net sales are zero/'
```

Expected:

- FAIL if the query service still calculates a zero-cost-base ROI instead of returning nil

- [ ] **Step 3: Tighten query-service guards**

Update `build_bucket` in `app/services/ec/sku_period_roi_query.rb` so guards happen before ROI calculation:

```ruby
invalid = days_count <= 0 || net_sales <= 0 || unit_cost.blank? || unit_cost.to_d <= 0 || unit_volume_l.blank? || unit_volume_l.to_d <= 0

return {
  sales_quantity: bucket[:sales_quantity].to_i,
  return_quantity: bucket[:return_quantity].to_i,
  net_sales_quantity: net_sales,
  average_daily_net_sales: invalid ? nil : average_daily,
  projected_stock_qty_180d: invalid ? nil : projected_qty,
  average_inventory_qty: invalid ? nil : average_inventory_qty,
  projected_months_to_clear: invalid ? nil : projected_months_to_clear,
  predicted_storage_cost_cny: invalid ? nil : predicted_storage_cost,
  predicted_interest_cost_cny: invalid ? nil : predicted_interest_cost,
  cost_base_cny: invalid ? nil : cost_base,
  operating_net_profit_cny: bucket[:operating_net_profit_cny],
  adjusted_operating_net_profit_cny: invalid ? nil : adjusted_profit,
  roi: nil
} if invalid
```

- [ ] **Step 4: Run the full query-service test file**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_period_roi_query_test.rb'
```

Expected:

- PASS for all query-service tests

- [ ] **Step 5: Commit**

```bash
git add test/services/ec/sku_period_roi_query_test.rb app/services/ec/sku_period_roi_query.rb
git commit -m "Handle SKU period ROI edge cases"
```

### Task 6: Final Verification

**Files:**
- Verify only:
  - `app/services/ec/roi_calculator.rb`
  - `app/services/ec/sku_period_profit_breakdown.rb`
  - `app/services/ec/sku_period_roi_query.rb`
  - `test/services/ec/roi_calculator_test.rb`
  - `test/services/ec/sku_period_profit_breakdown_test.rb`
  - `test/services/ec/sku_period_roi_query_test.rb`

- [ ] **Step 1: Run the focused service test suite**

Run:

```bash
/bin/zsh -lc 'SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/roi_calculator_test.rb test/services/ec/sku_period_profit_breakdown_test.rb test/services/ec/sku_period_roi_query_test.rb'
```

Expected:

- all targeted service tests PASS

- [ ] **Step 2: Review the diff**

Run:

```bash
git diff -- app/services/ec/roi_calculator.rb app/services/ec/sku_period_profit_breakdown.rb app/services/ec/sku_period_roi_query.rb test/services/ec/roi_calculator_test.rb test/services/ec/sku_period_profit_breakdown_test.rb test/services/ec/sku_period_roi_query_test.rb
```

Expected:

- diff is limited to the planned service and test files

- [ ] **Step 3: Commit the final verification state**

```bash
git add app/services/ec/roi_calculator.rb app/services/ec/sku_period_profit_breakdown.rb app/services/ec/sku_period_roi_query.rb test/services/ec/roi_calculator_test.rb test/services/ec/sku_period_profit_breakdown_test.rb test/services/ec/sku_period_roi_query_test.rb
git commit -m "Implement SKU period ROI services"
```
