# Inventory With Vol Google Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repeatable Google Sheets export that writes the current inventory list data, including dimensions and volume columns, into a new `Inventory With Vol` tab.

**Architecture:** Keep the export aligned with the inventory report by reusing the existing raw inventory row query and velocity query, then share the turnover/metric merge logic through a tiny PORO instead of duplicating controller math inside the Google Sheets writer. Implement the tab writer as its own `GoogleSheets::BaseService` subclass with a focused service test that captures the sheet writes without touching the real API.

**Tech Stack:** Rails 8, Ruby, ActiveRecord, Google Sheets API v4, Minitest, BigDecimal, Rake

---

### Task 1: Extract Shared Inventory Row Metric Enrichment

**Files:**
- Create: `app/services/ec/inventory_report_row_metrics_builder.rb`
- Create: `test/services/ec/inventory_report_row_metrics_builder_test.rb`
- Modify: `app/controllers/reports_controller.rb`
- Test: `test/services/ec/inventory_report_row_metrics_builder_test.rb`

- [ ] **Step 1: Write the failing metric enrichment test**

Create `test/services/ec/inventory_report_row_metrics_builder_test.rb`:

```ruby
require "test_helper"

class Ec::InventoryReportRowMetricsBuilderTest < ActiveSupport::TestCase
  test "merges daily sales velocity and turnover values into a raw inventory row" do
    raw_row = {
      sku_code: "INV-ROW-1",
      incoming_quantity: 15,
      book_stock: 10,
      platform_stock: 4,
      available_stock: 6
    }

    result = Ec::InventoryReportRowMetricsBuilder.call(
      raw_row,
      metrics: { daily_sales_velocity: BigDecimal("2.5") },
      cache_updated_at: Time.zone.parse("2026-07-04 10:00:00")
    )

    assert_equal BigDecimal("2.5"), result[:daily_sales_velocity]
    assert_equal BigDecimal("4"), result[:turnover_days]
    assert_equal BigDecimal("10"), result[:turnover_days_with_procurement]
    assert_equal Time.zone.parse("2026-07-04 10:00:00"), result[:cache_updated_at]
  end

  test "keeps turnover values blank when daily sales velocity is missing or non-positive" do
    raw_row = {
      sku_code: "INV-ROW-2",
      incoming_quantity: 8,
      book_stock: 12,
      platform_stock: 0,
      available_stock: 12
    }

    blank_velocity = Ec::InventoryReportRowMetricsBuilder.call(raw_row, metrics: {})
    zero_velocity = Ec::InventoryReportRowMetricsBuilder.call(
      raw_row,
      metrics: { daily_sales_velocity: BigDecimal("0") }
    )

    assert_nil blank_velocity[:daily_sales_velocity]
    assert_nil blank_velocity[:turnover_days]
    assert_nil blank_velocity[:turnover_days_with_procurement]

    assert_equal BigDecimal("0"), zero_velocity[:daily_sales_velocity]
    assert_nil zero_velocity[:turnover_days]
    assert_nil zero_velocity[:turnover_days_with_procurement]
  end
end
```

- [ ] **Step 2: Run the new unit test to verify it fails**

Run:

```bash
bundle exec ruby bin/rails test test/services/ec/inventory_report_row_metrics_builder_test.rb
```

Expected:

- FAIL with `uninitialized constant Ec::InventoryReportRowMetricsBuilder`

- [ ] **Step 3: Implement the minimal shared builder**

Create `app/services/ec/inventory_report_row_metrics_builder.rb`:

```ruby
module Ec
  class InventoryReportRowMetricsBuilder
    def self.call(raw_row, metrics:, cache_updated_at: nil)
      new(raw_row, metrics: metrics, cache_updated_at: cache_updated_at).call
    end

    def initialize(raw_row, metrics:, cache_updated_at:)
      @raw_row = raw_row
      @metrics = metrics || {}
      @cache_updated_at = cache_updated_at
    end

    def call
      daily_sales_velocity = metrics[:daily_sales_velocity]
      book_stock = raw_row[:book_stock].to_d
      procurement_stock = raw_row[:incoming_quantity].to_d
      turnover_days = daily_sales_velocity.to_d.positive? ? (book_stock / daily_sales_velocity.to_d) : nil
      turnover_days_with_procurement = daily_sales_velocity.to_d.positive? ? ((book_stock + procurement_stock) / daily_sales_velocity.to_d) : nil

      raw_row.merge(
        daily_sales_velocity: daily_sales_velocity,
        turnover_days: turnover_days,
        turnover_days_with_procurement: turnover_days_with_procurement,
        cache_updated_at: cache_updated_at
      )
    end

    private

    attr_reader :raw_row, :metrics, :cache_updated_at
  end
end
```

Modify `app/controllers/reports_controller.rb` inside `fetch_inventory_row`:

```ruby
  def fetch_inventory_row(sku, metrics: {})
    raw_row = Rails.cache.fetch(inventory_row_cache_key(sku.sku_code), expires_in: 30.minutes) do
      Ec::InventoryPageRowQuery.new(sku).call
    end

    Ec::InventoryReportRowMetricsBuilder.call(
      raw_row,
      metrics: metrics,
      cache_updated_at: Time.current
    )
  end
```

- [ ] **Step 4: Run the shared-row test to verify it passes**

Run:

```bash
bundle exec ruby bin/rails test test/services/ec/inventory_report_row_metrics_builder_test.rb
```

Expected:

- PASS with `2 runs, 0 failures`

- [ ] **Step 5: Commit the shared row builder**

```bash
git add app/services/ec/inventory_report_row_metrics_builder.rb app/controllers/reports_controller.rb test/services/ec/inventory_report_row_metrics_builder_test.rb
git commit -m "feat: share inventory row metric enrichment"
```

### Task 2: Add The Inventory With Vol Google Sheet Export Service

**Files:**
- Create: `app/services/google_sheets/inventory_with_vol_sheet_service.rb`
- Create: `test/services/google_sheets/inventory_with_vol_sheet_service_test.rb`
- Test: `test/services/google_sheets/inventory_with_vol_sheet_service_test.rb`

- [ ] **Step 1: Write the failing Google Sheets export service test**

Create `test/services/google_sheets/inventory_with_vol_sheet_service_test.rb`:

```ruby
require "test_helper"

class GoogleSheets::InventoryWithVolSheetServiceTest < ActiveSupport::TestCase
  def setup
    @sku_codes = []
    @original_base_initialize = GoogleSheets::BaseService.instance_method(:initialize)
    GoogleSheets::BaseService.define_method(:initialize) { nil }
  end

  def teardown
    GoogleSheets::BaseService.define_method(:initialize, @original_base_initialize)
    Ec::SkuCost.where(sku_code: @sku_codes).delete_all
    Ec::SkuBatch.where(sku_code: @sku_codes).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku_codes).delete_all
  end

  test "writes bilingual headers and flattened inventory rows to Inventory With Vol" do
    sku = create_inventory_sku("GS-INV-1")

    service = GoogleSheets::InventoryWithVolSheetService.new
    writes = []
    ensured_tab = nil
    cleared_range = nil
    batch_updates = []

    service.define_singleton_method(:ensure_sheet_exists) { |tab| ensured_tab = tab }
    service.define_singleton_method(:clear_sheet) { |range:| cleared_range = range }
    service.define_singleton_method(:sheet_id) { |_tab| 321 }
    service.define_singleton_method(:batch_update) { |requests| batch_updates << requests }
    service.define_singleton_method(:write_to_sheet) do |range:, values:|
      writes << { range: range, values: values }
    end

    fake_velocity_factory = lambda do |sku_codes:, date_to:, time_zone:|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          {
            sku.sku_code => { daily_sales_velocity: BigDecimal("2.5") }
          }
        end
      end
    end

    with_stubbed_constructor(Ec::InventoryVelocityMetricsQuery, fake_velocity_factory) do
      result = service.call

      assert_equal "Inventory With Vol", ensured_tab
      assert_equal "Inventory With Vol!A:ZZ", cleared_range
      assert_equal({ tab: "Inventory With Vol", sku_count: 1 }, result)

      write = writes.find { |entry| entry[:range] == "Inventory With Vol!A1" }
      assert write, "expected main sheet write"

      values = write[:values]
      assert_equal "SKU", values[0][0]
      assert_equal "商品名(中文)", values[0][1]
      assert_equal "采购中库存体积(m³)", values[0][4]
      assert_equal "周转天数(含采购)", values[0][13]
      assert_equal "单件体积(L)", values[0][17]

      assert_equal "SKU", values[1][0]
      assert_equal "Название (кит.)", values[1][1]
      assert_equal "Объём закупаемого запаса (м³)", values[1][4]
      assert_equal "Оборачиваемость с закупкой", values[1][13]
      assert_equal "Объём единицы (L)", values[1][17]

      row = values[2]
      assert_equal sku.sku_code, row[0]
      assert_equal "库存导出商品", row[1]
      assert_equal "Складской товар", row[2]
      assert_equal 15, row[3]
      assert_equal BigDecimal("0.09"), row[4]
      assert_equal 20, row[5]
      assert_equal BigDecimal("0.12"), row[6]
      assert_equal 7, row[7]
      assert_equal BigDecimal("0.042"), row[8]
      assert_equal 13, row[9]
      assert_equal BigDecimal("0.078"), row[10]
      assert_equal BigDecimal("2.5"), row[11]
      assert_equal BigDecimal("8"), row[12]
      assert_equal BigDecimal("14"), row[13]
      assert_equal BigDecimal("10"), row[14]
      assert_equal BigDecimal("20"), row[15]
      assert_equal BigDecimal("30"), row[16]
      assert_equal BigDecimal("6.0"), row[17]

      assert_equal 1, batch_updates.size
    end
  end

  test "leaves cubic meter cells blank when unit volume is unavailable" do
    sku = Ec::Sku.create!(
      sku_code: "GS-INV-BLANK",
      product_name: "空体积商品",
      is_active: true
    )
    @sku_codes << sku.sku_code

    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "GS-INV-BLANK-BATCH",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 6,
      received_quantity: 6,
      purchase_unit_price_cny: 1
    )

    service = GoogleSheets::InventoryWithVolSheetService.new
    writes = []

    service.define_singleton_method(:ensure_sheet_exists) { |_tab| nil }
    service.define_singleton_method(:clear_sheet) { |range:| range }
    service.define_singleton_method(:sheet_id) { |_tab| 321 }
    service.define_singleton_method(:batch_update) { |_requests| nil }
    service.define_singleton_method(:write_to_sheet) do |range:, values:|
      writes << { range: range, values: values }
    end

    fake_velocity_factory = lambda do |sku_codes:, date_to:, time_zone:|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          {
            sku.sku_code => { daily_sales_velocity: BigDecimal("1.2") }
          }
        end
      end
    end

    with_stubbed_constructor(Ec::InventoryVelocityMetricsQuery, fake_velocity_factory) do
      service.call
    end

    row = writes.find { |entry| entry[:range] == "Inventory With Vol!A1" }[:values][2]
    assert_nil row[4]
    assert_nil row[6]
    assert_nil row[8]
    assert_nil row[10]
    assert_nil row[14]
    assert_nil row[15]
    assert_nil row[16]
    assert_nil row[17]
  end

  private

  def create_inventory_sku(code)
    @sku_codes << code
    sku = Ec::Sku.create!(
      sku_code: code,
      product_name: "库存导出商品",
      product_name_ru: "Складской товар",
      is_active: true
    )

    Ec::SkuCost.create!(
      sku_code: code,
      pkg_length_cm: 10,
      pkg_width_cm: 20,
      pkg_height_cm: 30
    )

    Ec::SkuBatch.create!(
      sku_code: code,
      batch_code: "#{code}-REC",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 20,
      received_quantity: 20,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: code,
      batch_code: "#{code}-ORDERED",
      status: "ordered",
      batch_type: :normal,
      purchased_quantity: 15,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )

    sku
  end

  def with_stubbed_constructor(klass, replacement)
    simple_stubs = ActiveSupport::Testing::SimpleStubs.new
    simple_stubs.stub_object(klass, :new, &replacement)
    yield
  ensure
    simple_stubs&.unstub_all!
  end
end
```

- [ ] **Step 2: Run the export service test to verify it fails**

Run:

```bash
bundle exec ruby bin/rails test test/services/google_sheets/inventory_with_vol_sheet_service_test.rb
```

Expected:

- FAIL with `uninitialized constant GoogleSheets::InventoryWithVolSheetService`

- [ ] **Step 3: Implement the Google Sheets export service**

Create `app/services/google_sheets/inventory_with_vol_sheet_service.rb`:

```ruby
module GoogleSheets
  class InventoryWithVolSheetService < BaseService
    TAB_NAME = "Inventory With Vol".freeze

    HEADERS_ZH = [
      "SKU", "商品名(中文)", "商品名(俄文)",
      "采购中库存", "采购中库存体积(m³)",
      "账面可用库存", "账面可用库存体积(m³)",
      "FBO/FBW在库", "FBO/FBW在库体积(m³)",
      "FBS库存", "FBS库存体积(m³)",
      "日均销量", "周转天数", "周转天数(含采购)",
      "长(cm)", "宽(cm)", "高(cm)", "单件体积(L)"
    ].freeze

    HEADERS_RU = [
      "SKU", "Название (кит.)", "Название (рус.)",
      "Закупаемый запас", "Объём закупаемого запаса (м³)",
      "Книжный доступный запас", "Объём книжного доступного запаса (м³)",
      "FBO/FBW остаток", "Объём FBO/FBW остатка (м³)",
      "FBS запас", "Объём FBS запаса (м³)",
      "Средние продажи в день", "Оборачиваемость", "Оборачиваемость с закупкой",
      "Длина (см)", "Ширина (см)", "Высота (см)", "Объём единицы (L)"
    ].freeze

    COL_WIDTHS = [120, 180, 180, 90, 120, 90, 120, 90, 120, 90, 120, 100, 100, 130, 80, 80, 80, 90].freeze
    NUMERIC_TYPES = [:text, :text, :text, :integer, :number, :integer, :number, :integer, :number, :integer, :number, :number, :number, :number, :number, :number, :number, :number].freeze

    def call
      ensure_sheet_exists(TAB_NAME)
      clear_sheet(range: "#{TAB_NAME}!A:ZZ")

      rows = build_rows
      write_to_sheet(range: "#{TAB_NAME}!A1", values: [HEADERS_ZH, HEADERS_RU] + rows)
      apply_styles(rows.size)

      { tab: TAB_NAME, sku_count: rows.size }
    end

    private

    def build_rows
      skus = Ec::Sku.includes(:cost).order(:sku_code).to_a
      metrics_by_sku = Ec::InventoryVelocityMetricsQuery.new(
        sku_codes: skus.map(&:sku_code),
        date_to: Date.current,
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      skus.map do |sku|
        raw_row = Ec::InventoryPageRowQuery.new(sku).call
        row = Ec::InventoryReportRowMetricsBuilder.call(raw_row, metrics: metrics_by_sku[sku.sku_code] || {})

        [
          row[:sku_code],
          row[:product_name].to_s,
          row[:product_name_ru].to_s,
          row[:incoming_quantity],
          estimated_volume_m3(row[:incoming_quantity], row[:unit_volume_l]),
          row[:book_stock],
          estimated_volume_m3(row[:book_stock], row[:unit_volume_l]),
          row[:platform_stock],
          estimated_volume_m3(row[:platform_stock], row[:unit_volume_l]),
          row[:available_stock],
          estimated_volume_m3(row[:available_stock], row[:unit_volume_l]),
          row[:daily_sales_velocity],
          row[:turnover_days],
          row[:turnover_days_with_procurement],
          positive_decimal_or_nil(row[:pkg_length_cm]),
          positive_decimal_or_nil(row[:pkg_width_cm]),
          positive_decimal_or_nil(row[:pkg_height_cm]),
          positive_decimal_or_nil(row[:unit_volume_l])
        ]
      end
    end

    def estimated_volume_m3(quantity, unit_volume_l)
      return nil if unit_volume_l.blank?

      unit_volume_l = unit_volume_l.to_d
      return nil unless unit_volume_l.positive?

      quantity.to_d * unit_volume_l / 1000
    end

    def positive_decimal_or_nil(value)
      return nil if value.blank?

      decimal = value.to_d
      decimal.positive? ? decimal : nil
    end

    def apply_styles(row_count)
      @spreadsheet_sheets = nil
      sid = sheet_id(TAB_NAME)
      return unless sid

      data_end = 2 + row_count
      reqs = []
      reqs << req_header_rows(sid, num_rows: 2, num_cols: HEADERS_ZH.size)
      reqs += req_data_rows(sid, start_row: 2, end_row: data_end, col_types: NUMERIC_TYPES)
      reqs << req_freeze_rows(sid, count: 2)
      reqs += req_col_widths(sid, widths: COL_WIDTHS)
      batch_update(reqs)
    end
  end
end
```

- [ ] **Step 4: Run the export service test to verify it passes**

Run:

```bash
bundle exec ruby bin/rails test test/services/google_sheets/inventory_with_vol_sheet_service_test.rb
```

Expected:

- PASS with `2 runs, 0 failures`

- [ ] **Step 5: Commit the Google Sheets export service**

```bash
git add app/services/google_sheets/inventory_with_vol_sheet_service.rb test/services/google_sheets/inventory_with_vol_sheet_service_test.rb
git commit -m "feat: add inventory with vol sheet export"
```

### Task 3: Add A Repeatable Execution Entry Point And Run Regressions

**Files:**
- Create: `lib/tasks/inventory_sheet.rake`
- Test: `test/services/google_sheets/inventory_with_vol_sheet_service_test.rb`

- [ ] **Step 1: Add the rake entry point**

Create `lib/tasks/inventory_sheet.rake`:

```ruby
namespace :inventory do
  desc "Write the inventory report list with dimensions and volume columns into Google Sheet tab Inventory With Vol"
  task write_with_vol_sheet: :environment do
    require_relative "../../app/services/google_sheets/inventory_with_vol_sheet_service"
    result = GoogleSheets::InventoryWithVolSheetService.new.call
    puts "✓ Wrote #{result[:sku_count]} rows to #{result[:tab]}"
  end
end
```

- [ ] **Step 2: Run the focused regression suite**

Run:

```bash
bundle exec ruby bin/rails test test/services/ec/inventory_report_row_metrics_builder_test.rb test/services/google_sheets/inventory_with_vol_sheet_service_test.rb test/services/ec/inventory_page_row_query_test.rb test/services/ec/inventory_velocity_metrics_query_test.rb
```

Expected:

- PASS with `0 failures, 0 errors`

- [ ] **Step 3: Commit the execution entry point**

```bash
git add lib/tasks/inventory_sheet.rake
git commit -m "feat: add inventory with vol sheet task"
```

- [ ] **Step 4: Record the production run command**

Run after deploy from the app container:

```bash
bin/kamal app exec --reuse "bundle exec ruby bin/rails runner 'result = GoogleSheets::InventoryWithVolSheetService.new.call; puts result.inspect'"
```

Expected:

- output containing `{:tab=>"Inventory With Vol", :sku_count=>...}`

- [ ] **Step 5: Verify the spreadsheet tab content manually after the production run**

Check in Google Sheets:

- tab `Inventory With Vol` exists
- two header rows are present
- SKU rows are in ascending order
- dimension columns and unit volume column are populated where cost data exists
- cubic-meter columns are populated where unit volume is positive

