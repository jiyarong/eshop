# Inventory Volume Summary Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four inventory volume summary cards above the inventory table so filtered totals stay stable across pagination and ignore missing or non-positive contributions.

**Architecture:** Keep the inventory list page as the integration point, but extract the cubic-meter accumulation into a tiny PORO so exclusion rules are tested independently from controller rendering. The controller will build summary data from the full filtered SKU scope using the existing row payload path, then the ERB will render the cards with existing summary-card styles and the existing `estimated_volume_m3` translation key.

**Tech Stack:** Rails 8, ERB, ActiveRecord, Minitest, BigDecimal, Kaminari

---

### Task 1: Lock The Volume Aggregation Rules In A Small Unit Test

**Files:**
- Create: `app/services/ec/inventory_volume_summary_builder.rb`
- Create: `test/services/ec/inventory_volume_summary_builder_test.rb`
- Test: `test/services/ec/inventory_volume_summary_builder_test.rb`

- [ ] **Step 1: Write the failing service test**

Create `test/services/ec/inventory_volume_summary_builder_test.rb`:

```ruby
require "test_helper"

class Ec::InventoryVolumeSummaryBuilderTest < ActiveSupport::TestCase
  test "sums only positive cubic meter contributions for each stock bucket" do
    rows = [
      {
        incoming_quantity: 10,
        book_stock: 5,
        platform_stock: 3,
        available_stock: 4,
        unit_volume_l: BigDecimal("1.5")
      },
      {
        incoming_quantity: -8,
        book_stock: 9,
        platform_stock: 1,
        available_stock: 1,
        unit_volume_l: BigDecimal("2.0")
      },
      {
        incoming_quantity: 6,
        book_stock: 6,
        platform_stock: 6,
        available_stock: 6,
        unit_volume_l: nil
      },
      {
        incoming_quantity: 7,
        book_stock: 7,
        platform_stock: 7,
        available_stock: 7,
        unit_volume_l: BigDecimal("0")
      }
    ]

    summary = Ec::InventoryVolumeSummaryBuilder.call(rows)

    assert_equal BigDecimal("0.015"), summary[:pending_stock_volume_m3]
    assert_equal BigDecimal("0.0255"), summary[:book_available_stock_volume_m3]
    assert_equal BigDecimal("0.0065"), summary[:platform_stock_volume_m3]
    assert_equal BigDecimal("0.007"), summary[:overseas_available_stock_volume_m3]
  end
end
```

- [ ] **Step 2: Run the unit test to verify it fails**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_volume_summary_builder_test.rb
```

Expected:

- FAIL with `uninitialized constant Ec::InventoryVolumeSummaryBuilder`

- [ ] **Step 3: Write the minimal aggregation service**

Create `app/services/ec/inventory_volume_summary_builder.rb`:

```ruby
module Ec
  class InventoryVolumeSummaryBuilder
    FIELD_MAP = {
      pending_stock_volume_m3: :incoming_quantity,
      book_available_stock_volume_m3: :book_stock,
      platform_stock_volume_m3: :platform_stock,
      overseas_available_stock_volume_m3: :available_stock
    }.freeze

    def self.call(rows)
      new(rows).call
    end

    def initialize(rows)
      @rows = Array(rows)
    end

    def call
      rows.each_with_object(empty_summary) do |row, totals|
        unit_volume_l = row[:unit_volume_l]
        next if unit_volume_l.blank?

        unit_volume_l = unit_volume_l.to_d
        next unless unit_volume_l.positive?

        FIELD_MAP.each do |summary_key, quantity_key|
          contribution = row[quantity_key].to_d * unit_volume_l / 1000
          next unless contribution.positive?

          totals[summary_key] += contribution
        end
      end
    end

    private

    attr_reader :rows

    def empty_summary
      FIELD_MAP.keys.index_with { BigDecimal("0") }
    end
  end
end
```

- [ ] **Step 4: Run the unit test to verify it passes**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_volume_summary_builder_test.rb
```

Expected:

- PASS for `Ec::InventoryVolumeSummaryBuilderTest`

- [ ] **Step 5: Commit the aggregation rule implementation**

```bash
git add app/services/ec/inventory_volume_summary_builder.rb test/services/ec/inventory_volume_summary_builder_test.rb
git commit -m "feat: add inventory volume summary builder"
```

### Task 2: Add A Focused Inventory Page Integration Test For Cross-Page Totals

**Files:**
- Create: `test/controllers/inventory_volume_summary_cards_test.rb`
- Test: `test/controllers/inventory_volume_summary_cards_test.rb`

- [ ] **Step 1: Write the failing integration test**

Create `test/controllers/inventory_volume_summary_cards_test.rb`:

```ruby
require "test_helper"

class InventoryVolumeSummaryCardsTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("inventory-summary-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
  end

  teardown do
    sku_codes = Ec::Sku.with_deleted.where("sku_code LIKE ?", "SUM-%-#{@token}").pluck(:sku_code)
    Ec::SkuCost.where(sku_code: sku_codes).delete_all
    Ec::SkuBatch.where(sku_code: sku_codes).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku_codes).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "inventory-summary-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "inventory-summary-#{@token.downcase}%").delete_all
  end

  test "inventory report renders filtered volume summary across pagination and ignores invalid contributions" do
    skus = 12.times.map do |index|
      Ec::Sku.create!(
        sku_code: format("SUM-%02d-%s", index, @token),
        product_name: "汇总商品#{index}",
        is_active: true
      )
    end

    row_payloads = skus.index_with do |sku|
      {
        sku_code: sku.sku_code,
        product_name: sku.product_name,
        product_name_ru: nil,
        incoming_quantity: 0,
        book_stock: 0,
        platform_stock: 0,
        available_stock: 0,
        unit_volume_l: nil,
        daily_sales_velocity: nil,
        turnover_days: nil,
        turnover_days_with_procurement: nil,
        cache_updated_at: Time.zone.parse("2026-07-04 10:00:00")
      }
    end

    row_payloads[skus[0]].merge!(incoming_quantity: 10, unit_volume_l: BigDecimal("1.0"))
    row_payloads[skus[1]].merge!(book_stock: 5, unit_volume_l: BigDecimal("2.0"))
    row_payloads[skus[10]].merge!(platform_stock: 3, available_stock: 4, unit_volume_l: BigDecimal("1.5"))
    row_payloads[skus[11]].merge!(incoming_quantity: -9, unit_volume_l: BigDecimal("5.0"))

    fake_query_factory = lambda do |sku, metrics:|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          row_payloads.fetch(sku)
        end
      end
    end

    fake_velocity_factory = lambda do |sku_codes:, date_to:, time_zone:|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          sku_codes.index_with { |_| {} }
        end
      end
    end

    with_stubbed_constructor(Ec::InventoryPageRowQuery, fake_query_factory) do
      with_stubbed_constructor(Ec::InventoryVelocityMetricsQuery, fake_velocity_factory) do
        get "/reports/inventory", params: { sku: "sum-", page: 2 }, headers: { "Accept" => "text/html" }
      end
    end

    assert_response :success
    assert_select ".inventory-volume-summary .weekly-profit-summary-card", count: 4
    assert_select ".inventory-volume-summary .summary-label", I18n.t("reports.inventory.fields.pending_stock")
    assert_select ".inventory-volume-summary .summary-label", I18n.t("reports.inventory.fields.book_available_stock")
    assert_select ".inventory-volume-summary .summary-label", I18n.t("reports.inventory.fields.platform_stock")
    assert_select ".inventory-volume-summary .summary-label", I18n.t("reports.inventory.fields.overseas_available_stock")
    assert_select ".inventory-volume-summary .summary-value", "0.0100 m³"
    assert_select ".inventory-volume-summary .summary-value", "0.0100 m³"
    assert_select ".inventory-volume-summary .summary-value", "0.0045 m³"
    assert_select ".inventory-volume-summary .summary-value", "0.0060 m³"
    assert_select "tbody tr.inventory-list-table__row", count: 2
    assert_select "tbody tr.inventory-list-table__row td:nth-child(1) .inventory-list-table__sku-link", skus[10].sku_code
    assert_select "tbody tr.inventory-list-table__row td:nth-child(1) .inventory-list-table__sku-link", skus[11].sku_code
  end
end
```

- [ ] **Step 2: Run the integration test to verify it fails**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/inventory_volume_summary_cards_test.rb
```

Expected:

- FAIL because `.inventory-volume-summary` does not exist yet

- [ ] **Step 3: Commit the red integration test**

```bash
git add test/controllers/inventory_volume_summary_cards_test.rb
git commit -m "test: define inventory volume summary cards contract"
```

### Task 3: Wire The Summary Through Controller, Helper, And ERB

**Files:**
- Modify: `app/controllers/reports_controller.rb`
- Modify: `app/helpers/application_helper.rb`
- Modify: `app/views/reports/inventory.html.erb`
- Test: `test/controllers/inventory_volume_summary_cards_test.rb`
- Test: `test/services/ec/inventory_volume_summary_builder_test.rb`

- [ ] **Step 1: Build the summary from the full filtered SKU scope**

Update `app/controllers/reports_controller.rb`:

```ruby
  def inventory
    @sku_query = params[:sku].to_s.strip
    scope = inventory_skus_scope.order(:sku_code)
    @inventory_volume_summary = build_inventory_volume_summary(scope)
    @inventory_rows = build_inventory_rows(scope)
  end

  def build_inventory_rows(scope)
    current_page = inventory_page_param
    skus = scope.page(current_page).per(10)
    if skus.total_pages.positive? && current_page > skus.total_pages
      skus = scope.page(skus.total_pages).per(10)
    end

    metrics_by_sku = Ec::InventoryVelocityMetricsQuery.new(
      sku_codes: skus.map(&:sku_code),
      date_to: user_today,
      time_zone: user_time_zone
    ).call

    rows = skus.map do |sku|
      fetch_inventory_row(sku, metrics: metrics_by_sku[sku.sku_code] || {})
    end

    Kaminari.paginate_array(
      rows,
      total_count: skus.total_count,
      limit: skus.limit_value,
      offset: skus.offset_value
    )
  end

  def build_inventory_volume_summary(scope)
    rows = scope.map { |sku| fetch_inventory_row(sku) }
    Ec::InventoryVolumeSummaryBuilder.call(rows)
  end
```

- [ ] **Step 2: Add one formatting helper for already-aggregated cubic meters**

Update `app/helpers/application_helper.rb`:

```ruby
  def inventory_volume_m3_text(volume_m3)
    t("reports.inventory.labels.estimated_volume_m3", volume: format("%.4f", volume_m3.to_d))
  end
```

Place it immediately below `inventory_estimated_volume_text` so the inventory volume rendering helpers stay together.

- [ ] **Step 3: Render the four summary cards above the table**

Insert this block into `app/views/reports/inventory.html.erb` between the filter `<section class="panel">` and the table `<section class="panel">`:

```erb
  <section class="summary-grid inventory-volume-summary">
    <div class="weekly-profit-summary-card">
      <div class="summary-label"><%= t("reports.inventory.fields.pending_stock") %></div>
      <div class="summary-value"><%= inventory_volume_m3_text(@inventory_volume_summary[:pending_stock_volume_m3]) %></div>
    </div>
    <div class="weekly-profit-summary-card">
      <div class="summary-label"><%= t("reports.inventory.fields.book_available_stock") %></div>
      <div class="summary-value"><%= inventory_volume_m3_text(@inventory_volume_summary[:book_available_stock_volume_m3]) %></div>
    </div>
    <div class="weekly-profit-summary-card">
      <div class="summary-label"><%= t("reports.inventory.fields.platform_stock") %></div>
      <div class="summary-value"><%= inventory_volume_m3_text(@inventory_volume_summary[:platform_stock_volume_m3]) %></div>
    </div>
    <div class="weekly-profit-summary-card">
      <div class="summary-label"><%= t("reports.inventory.fields.overseas_available_stock") %></div>
      <div class="summary-value"><%= inventory_volume_m3_text(@inventory_volume_summary[:overseas_available_stock_volume_m3]) %></div>
    </div>
  </section>
```

Do not add new locale keys or CSS unless the existing `summary-grid` and `weekly-profit-summary-card` styles prove insufficient.

- [ ] **Step 4: Run the focused tests to verify they pass**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_volume_summary_builder_test.rb
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/inventory_volume_summary_cards_test.rb
```

Expected:

- PASS for both files
- the integration test proves cards are rendered, totals span all filtered SKUs, and invalid contributions are ignored

- [ ] **Step 5: Commit the UI wiring**

```bash
git add app/controllers/reports_controller.rb app/helpers/application_helper.rb app/views/reports/inventory.html.erb
git commit -m "feat: add inventory volume summary cards"
```

### Task 4: Run Targeted Regression Checks For Existing Inventory UI

**Files:**
- Test: `test/services/ec/inventory_page_row_query_test.rb`
- Test: `test/controllers/reports_controller_test.rb`

- [ ] **Step 1: Re-run the existing row payload regression test**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_page_row_query_test.rb
```

Expected:

- PASS, proving the existing row payload still exposes dimensions and per-row volume inputs used by the new summary

- [ ] **Step 2: Re-run the existing inventory list integration coverage**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb:429
```

Expected:

- PASS for the inventory list rendering contract near `test "inventory report uses inventory page row query for each filtered sku"`

- [ ] **Step 3: Record the known unrelated failures if they still appear elsewhere**

If a broader `reports_controller_test.rb` run still hits the two pre-existing SKU detail failures, note them in the final handoff as unrelated existing failures and do not broaden the scope to fix them here.

- [ ] **Step 4: Commit the regression-verified state**

```bash
git add test/controllers/inventory_volume_summary_cards_test.rb test/services/ec/inventory_volume_summary_builder_test.rb
git commit -m "test: cover inventory volume summary regressions"
```
