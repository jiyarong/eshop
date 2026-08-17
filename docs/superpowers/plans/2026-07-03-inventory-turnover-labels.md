# Inventory Turnover And Label Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align inventory list/detail wording and add a procurement-inclusive turnover metric to both surfaces without changing the underlying inventory summary formulas.

**Architecture:** Keep the new metric in the page-facing inventory query objects rather than `Ec::SkuInventoryOverview`, because it depends on daily sales velocity that is already injected at the page layer. Update controller/view integration tests first, then extend the row/detail payloads, then switch the ERB and locale text to the new labels.

**Tech Stack:** Rails 8, ERB, ActiveRecord, Minitest, I18n, Kaminari

---

### Task 1: Lock The New Inventory Page Contract In Tests

**Files:**
- Modify: `test/controllers/reports_controller_test.rb`
- Modify: `test/services/ec/inventory_page_row_query_test.rb`
- Modify: `test/services/ec/inventory_page_detail_query_test.rb`
- Test: `test/controllers/reports_controller_test.rb`
- Test: `test/services/ec/inventory_page_row_query_test.rb`
- Test: `test/services/ec/inventory_page_detail_query_test.rb`

- [ ] **Step 1: Add a failing row-query test for procurement-inclusive turnover**

Update `test/services/ec/inventory_page_row_query_test.rb` by extending the injected-metrics test so it expects the new field:

```ruby
  test "accepts injected daily sales velocity metrics" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "ROW-METRIC-#{token}", product_name: "行指标测试商品")

    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "ROW-METRIC-REC-#{token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 10,
      received_quantity: 10,
      purchase_unit_price_cny: 1
    )

    row = Ec::InventoryPageRowQuery.new(
      sku,
      metrics: {
        daily_sales_velocity: BigDecimal("2.4"),
        turnover_days: BigDecimal("4.1667"),
        turnover_days_with_procurement: BigDecimal("8.3333")
      }
    ).call

    assert_equal BigDecimal("2.4"), row[:daily_sales_velocity]
    assert_equal BigDecimal("4.1667"), row[:turnover_days]
    assert_equal BigDecimal("8.3333"), row[:turnover_days_with_procurement]
  ensure
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end
```

- [ ] **Step 2: Add a failing detail-query test for normal procurement batches only**

Append this test to `test/services/ec/inventory_page_detail_query_test.rb`:

```ruby
  test "calculates procurement-inclusive turnover from normal procurement batches only" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "DETAIL-PROC-#{token}", product_name: "采购周转测试商品")

    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-PROC-REC-#{token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 0,
      received_quantity: 24,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-PROC-DRAFT-#{token}",
      status: "draft",
      batch_type: :normal,
      purchased_quantity: 6,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-PROC-OFFSET-#{token}",
      status: "ordered",
      batch_type: :wb_fbw_offset,
      purchased_quantity: 50,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )

    fake_velocity_factory = lambda do |sku_codes:, date_to:, time_zone:|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          {
            sku.sku_code => { daily_sales_velocity: BigDecimal("3.0") }
          }
        end
      end
    end

    with_stubbed_constructor(Ec::InventoryVelocityMetricsQuery, fake_velocity_factory) do
      payload = Ec::InventoryPageDetailQuery.new(sku, detail_tab: "book", book_batch_page: 1).call

      assert_in_delta 8.0, payload[:turnover_days].to_f, 0.01
      assert_in_delta 10.0, payload[:turnover_days_with_procurement].to_f, 0.01
    end
  ensure
    Ec::SkuInventoryLevel.where(sku_code: sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end
```

- [ ] **Step 3: Add failing controller assertions for the renamed labels and new turnover field**

Update `test/controllers/reports_controller_test.rb` in the inventory list test stub:

```ruby
          {
            sku_code: sku.sku_code,
            product_name: "商品 #{sku.sku_code}",
            product_name_ru: "Товар #{sku.sku_code}",
            incoming_quantity: 0,
            book_stock: 14,
            platform_stock: 0,
            available_stock: 7,
            daily_sales_velocity: BigDecimal("1.23"),
            turnover_days: BigDecimal("11.38"),
            turnover_days_with_procurement: BigDecimal("20.51"),
            cache_updated_at: Time.zone.parse("2026-06-22 10:00:00")
          }
```

Replace and add assertions:

```ruby
    assert_select "th", I18n.t("reports.inventory.fields.pending_stock")
    assert_select "th", I18n.t("reports.inventory.fields.platform_stock")
    assert_select "th", I18n.t("reports.inventory.fields.overseas_available_stock")
    assert_select "th", I18n.t("reports.inventory.fields.turnover_days")
    assert_select "th", I18n.t("reports.inventory.fields.turnover_days_with_procurement")
    assert_select "tbody tr.inventory-list-table__row td:nth-child(7)", "1.23"
    assert_select "tbody tr.inventory-list-table__row td:nth-child(8)", "11.38"
    assert_select "tbody tr.inventory-list-table__row td:nth-child(9)", "20.51"
```

Update the inventory detail turbo-frame test stub to include:

```ruby
            daily_sales_velocity: BigDecimal("1.23"),
            turnover_days: BigDecimal("5.67"),
            turnover_days_with_procurement: BigDecimal("8.91"),
```

And add assertions:

```ruby
    assert_select ".inventory-metric-card__label", I18n.t("reports.inventory.fields.pending_stock")
    assert_select ".inventory-metric-card__label", I18n.t("reports.inventory.fields.platform_stock")
    assert_select ".inventory-metric-card__label", I18n.t("reports.inventory.fields.overseas_available_stock")
    assert_select ".inventory-metric-card__label", I18n.t("reports.inventory.fields.turnover_days_with_procurement")
    assert_select ".inventory-metric-card__value", "8.91"
```

- [ ] **Step 4: Run the three tests to verify they fail for the expected reason**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_page_row_query_test.rb
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_page_detail_query_test.rb
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb:429
```

Expected:

- row query test fails because `turnover_days_with_procurement` is missing
- detail query test fails because the new turnover metric is missing or wrong
- controller test fails because the new labels/column/card are not rendered yet

- [ ] **Step 5: Commit the red tests**

```bash
git add test/services/ec/inventory_page_row_query_test.rb test/services/ec/inventory_page_detail_query_test.rb test/controllers/reports_controller_test.rb
git commit -m "test: define inventory turnover label contract"
```

### Task 2: Extend Inventory Payloads With Procurement-Inclusive Turnover

**Files:**
- Modify: `app/services/ec/inventory_page_row_query.rb`
- Modify: `app/services/ec/inventory_page_detail_query.rb`
- Modify: `app/controllers/reports_controller.rb`
- Test: `test/services/ec/inventory_page_row_query_test.rb`
- Test: `test/services/ec/inventory_page_detail_query_test.rb`

- [ ] **Step 1: Add a normal-procurement helper to the row query**

Update `app/services/ec/inventory_page_row_query.rb` to expose procurement stock and the new metric:

```ruby
module Ec
  class InventoryPageRowQuery
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze

    def initialize(sku, metrics: nil)
      @sku = sku
      @metrics = metrics || {}
    end

    def call
      summary = @sku.inventory_overview[:summary]

      {
        sku_code: @sku.sku_code,
        product_name: @sku.product_name,
        product_name_ru: @sku.product_name_ru,
        incoming_quantity: incoming_quantity,
        book_stock: summary[:book_stock],
        platform_stock: summary[:platform_stock],
        available_stock: summary[:available_stock],
        daily_sales_velocity: @metrics[:daily_sales_velocity],
        turnover_days: @metrics[:turnover_days],
        turnover_days_with_procurement: @metrics[:turnover_days_with_procurement]
      }
    end

    private

    def incoming_quantity
      procurement_batches.sum(:purchased_quantity).to_i
    end

    def procurement_batches
      @sku.batches.where(status: INCOMING_STATUSES, batch_type: :normal)
    end
  end
end
```

- [ ] **Step 2: Compute procurement-inclusive turnover in the controller list path**

Update `ReportsController#fetch_inventory_row` in `app/controllers/reports_controller.rb`:

```ruby
  def fetch_inventory_row(sku, metrics: {})
    row = Rails.cache.fetch(inventory_row_cache_key(sku.sku_code), expires_in: 30.minutes) do
      Ec::InventoryPageRowQuery.new(sku, metrics: metrics).call
    end

    daily_sales_velocity = metrics[:daily_sales_velocity]
    book_stock = row[:book_stock].to_d
    procurement_stock = row[:incoming_quantity].to_d
    turnover_days = daily_sales_velocity.to_d.positive? ? (book_stock / daily_sales_velocity.to_d) : nil
    turnover_days_with_procurement = daily_sales_velocity.to_d.positive? ? ((book_stock + procurement_stock) / daily_sales_velocity.to_d) : nil

    row.merge(
      daily_sales_velocity: metrics[:daily_sales_velocity],
      turnover_days: turnover_days,
      turnover_days_with_procurement: turnover_days_with_procurement,
      cache_updated_at: Time.current
    )
  end
```

- [ ] **Step 3: Compute procurement-inclusive turnover in the detail query**

Update `app/services/ec/inventory_page_detail_query.rb`:

```ruby
      {
        sku_code: @sku.sku_code,
        product_name: @sku.product_name,
        product_name_ru: @sku.product_name_ru,
        active_detail_tab: @detail_tab,
        summary: overview[:summary],
        daily_sales_velocity: velocity_metrics[:daily_sales_velocity],
        turnover_days: velocity_metrics[:turnover_days],
        turnover_days_with_procurement: velocity_metrics[:turnover_days_with_procurement],
        incoming_quantity: incoming_batches.sum { |row| row[:purchased_quantity].to_i },
```

Add helpers:

```ruby
    def procurement_batches_scope
      @sku.batches.where(status: INCOMING_STATUSES, batch_type: :normal)
    end

    def procurement_quantity
      procurement_batches_scope.sum(:purchased_quantity).to_i
    end
```

Update `inventory_velocity_metrics(summary)`:

```ruby
    def inventory_velocity_metrics(summary)
      @inventory_velocity_metrics ||= begin
        metrics = Ec::InventoryVelocityMetricsQuery.new(
          sku_codes: [@sku.sku_code],
          date_to: @date_to,
          time_zone: @time_zone
        ).call.fetch(@sku.sku_code, {})

        daily_sales_velocity = metrics[:daily_sales_velocity]
        book_stock = summary[:book_stock].to_d
        procurement_stock = procurement_quantity.to_d

        metrics.merge(
          turnover_days: daily_sales_velocity.to_d.positive? ? (book_stock / daily_sales_velocity.to_d) : nil,
          turnover_days_with_procurement: daily_sales_velocity.to_d.positive? ? ((book_stock + procurement_stock) / daily_sales_velocity.to_d) : nil
        )
      end
    end
```

- [ ] **Step 4: Run the focused service/controller tests to verify they pass**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_page_row_query_test.rb
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_page_detail_query_test.rb
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb:429
```

Expected:

- row query test passes with the new field
- detail query tests pass with normal-batch-only procurement logic
- controller test still fails on labels/layout because the view and locales are not updated yet

- [ ] **Step 5: Commit the payload changes**

```bash
git add app/services/ec/inventory_page_row_query.rb app/services/ec/inventory_page_detail_query.rb app/controllers/reports_controller.rb test/services/ec/inventory_page_row_query_test.rb test/services/ec/inventory_page_detail_query_test.rb
git commit -m "feat: add procurement turnover metrics"
```

### Task 3: Update Inventory Views And I18n Labels

**Files:**
- Modify: `app/views/reports/inventory.html.erb`
- Modify: `app/views/reports/_inventory_drawer_content.html.erb`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`
- Modify: `test/controllers/reports_controller_test.rb`
- Test: `test/controllers/reports_controller_test.rb`

- [ ] **Step 1: Add the new locale text**

Update the inventory field labels in all three locale files. The relevant shape should become:

```yaml
reports:
  inventory:
    fields:
      pending_stock: "采购中库存"
      platform_stock: "FBO/FBW在库"
      overseas_available_stock: "FBS库存"
      turnover_days: "周转天数"
      turnover_days_with_procurement: "周转天数(含采购)"
```

For English and Russian, add equivalent translations for the same key while keeping the key names unchanged.

- [ ] **Step 2: Render the new list column and labels**

Update `app/views/reports/inventory.html.erb`:

```erb
            <th><%= t("reports.inventory.fields.pending_stock") %></th>
            <th><%= t("reports.inventory.fields.book_available_stock") %></th>
            <th><%= t("reports.inventory.fields.platform_stock") %></th>
            <th><%= t("reports.inventory.fields.overseas_available_stock") %></th>
            <th><%= t("reports.inventory.fields.daily_sales_velocity") %></th>
            <th><%= t("reports.inventory.fields.turnover_days") %></th>
            <th><%= t("reports.inventory.fields.turnover_days_with_procurement") %></th>
            <th><%= t("reports.inventory.fields.actions") %></th>
```

And inside the row:

```erb
              <% turnover_days_with_procurement = row[:turnover_days_with_procurement] %>
              <td class="numeric inventory-list-table__metric"><%= daily_sales_velocity.present? ? format("%.2f", daily_sales_velocity.to_d) : "-" %></td>
              <td class="numeric inventory-list-table__metric"><%= turnover_days.present? ? format("%.2f", turnover_days.to_d) : "-" %></td>
              <td class="numeric inventory-list-table__metric"><%= turnover_days_with_procurement.present? ? format("%.2f", turnover_days_with_procurement.to_d) : "-" %></td>
```

Also change the empty-row colspan from `9` to `10`.

- [ ] **Step 3: Render the new detail overview card and labels**

Update `app/views/reports/_inventory_drawer_content.html.erb`:

```erb
      <div class="inventory-metric-card inventory-metric-card--warning inventory-metric-card--compact">
        <span class="inventory-metric-card__label"><%= t("reports.inventory.fields.pending_stock") %></span>
        <strong class="inventory-metric-card__value"><%= inventory_detail[:incoming_quantity].to_i %></strong>
      </div>
      <div class="inventory-metric-card inventory-metric-card--compact">
        <span class="inventory-metric-card__label"><%= t("reports.inventory.fields.platform_stock") %></span>
        <strong class="inventory-metric-card__value"><%= inventory_detail.dig(:summary, :platform_stock).to_i %></strong>
      </div>
      <div class="inventory-metric-card inventory-metric-card--primary inventory-metric-card--compact">
        <span class="inventory-metric-card__label"><%= t("reports.inventory.fields.overseas_available_stock") %></span>
        <strong class="inventory-metric-card__value"><%= inventory_detail.dig(:summary, :available_stock).to_i %></strong>
      </div>
      <div class="inventory-metric-card inventory-metric-card--compact">
        <span class="inventory-metric-card__label"><%= t("reports.inventory.fields.turnover_days_with_procurement") %></span>
        <strong class="inventory-metric-card__value">
          <%= inventory_detail[:turnover_days_with_procurement].present? ? format("%.2f", inventory_detail[:turnover_days_with_procurement].to_d) : "-" %>
        </strong>
      </div>
```

- [ ] **Step 4: Run the targeted controller test and the two service tests**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb:429
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_page_row_query_test.rb
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_page_detail_query_test.rb
```

Expected: all three pass.

- [ ] **Step 5: Commit the UI and locale updates**

```bash
git add app/views/reports/inventory.html.erb app/views/reports/_inventory_drawer_content.html.erb config/locales/zh.yml config/locales/en.yml config/locales/ru.yml test/controllers/reports_controller_test.rb
git commit -m "feat: align inventory labels and turnover views"
```

## Self-Review

- Spec coverage: the plan covers label renames, the new procurement-inclusive turnover metric, normal-batch-only filtering, list rendering, detail rendering, and TDD verification.
- Placeholder scan: no `TODO`/`TBD` placeholders remain; each task includes exact file paths, code shapes, commands, and expected outcomes.
- Type consistency: the new field name is consistently `turnover_days_with_procurement` across tests, services, controller merge logic, views, and locales.
