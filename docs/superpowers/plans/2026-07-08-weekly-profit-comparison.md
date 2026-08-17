# Weekly Profit Comparison Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add unified period-over-period comparison data and red/green comparison rendering to `WR`, `WSU`, and `WSU-DEEP` in `/weekly_profit_reports`.

**Architecture:** Build comparison data on the server beside the existing report payloads, not in the views. Extend the report queries with a shared comparison builder, then update the Rails controller helpers and ERB partials to render current value plus comparison trend lines without adding extra columns.

**Tech Stack:** Rails 8, ERB, Ruby service objects, Minitest, Node `--test` for small front-end/controller helpers if needed.

---

### Task 1: Comparison Support and Query Payload Shape

**Files:**
- Modify: `app/services/ec/weekly_summary_support.rb`
- Modify: `app/services/ec/weekly_summary_query.rb`
- Modify: `app/services/ec/weekly_summary_deep_query.rb`
- Modify: `app/services/ec/weekly_profit_report_query.rb`
- Test: `test/services/ec/weekly_summary_query_test.rb`
- Test: `test/services/ec/weekly_summary_deep_query_test.rb`
- Test: `test/controllers/weekly_profit_reports_controller_test.rb`

- [ ] **Step 1: Write failing tests for `WSU` comparison payload**

```ruby
test "run returns wsu comparison payload with previous period and row comparisons" do
  payload = query.run

  assert_equal "2026-05-18", payload.dig(:comparison, :period, :from_date)
  assert_equal "2026-05-24", payload.dig(:comparison, :period, :to_date)
  assert_equal 100.0, payload.dig(:comparison, :rows, "SKU-WB|WB|WB-1", :net_sales, :delta_pct)
  assert_equal "positive", payload.dig(:comparison, :rows, "SKU-WB|WB|WB-1", :revenue, :semantic)
  assert_equal "negative", payload.dig(:comparison, :rows, "SKU-WB|WB|WB-1", :ads, :semantic)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby bin/rails test test/services/ec/weekly_summary_query_test.rb`
Expected: FAIL because `comparison` payload and row comparison keys do not exist yet.

- [ ] **Step 3: Write failing tests for `WSU-DEEP` comparison payload**

```ruby
test "run returns wsu deep comparison payload keyed by sku" do
  payload = query.run

  assert_equal "2026-05-18", payload.dig(:comparison, :period, :from_date)
  assert_equal "WSUDEEP-A", payload.dig(:rows, 0, :sku)
  assert_equal "positive", payload.dig(:comparison, :rows, "WSUDEEP-A", :after_tax, :semantic)
  assert_equal "negative", payload.dig(:comparison, :rows, "WSUDEEP-A", :ads, :semantic)
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bundle exec ruby bin/rails test test/services/ec/weekly_summary_deep_query_test.rb`
Expected: FAIL because `comparison` payload and comparison map do not exist yet.

- [ ] **Step 5: Implement shared comparison helpers and query payload changes**

```ruby
def previous_period_range(from_date, to_date)
  span_days = (to_date - from_date).to_i + 1
  [from_date - span_days, to_date - span_days]
end

def build_metric_comparison(current:, previous:, semantic_type:)
  return { current:, previous: nil, delta_value: nil, delta_pct: nil, trend: "none", semantic: "none" } if previous.nil?
  return { current:, previous:, delta_value: 0, delta_pct: 0, trend: "flat", semantic: "neutral" } if current.to_d.zero? && previous.to_d.zero?

  delta_value = (BigDecimal(current.to_s) - BigDecimal(previous.to_s)).round(2)
  delta_pct = previous.to_d.zero? ? nil : ((delta_value / BigDecimal(previous.to_s)) * 100).round(2)
  trend = delta_value.positive? ? "up" : delta_value.negative? ? "down" : "flat"
  semantic = semantic_for(trend:, semantic_type:)

  { current:, previous:, delta_value:, delta_pct:, trend:, semantic: }
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec ruby bin/rails test test/services/ec/weekly_summary_query_test.rb test/services/ec/weekly_summary_deep_query_test.rb`
Expected: PASS

- [ ] **Step 7: Write failing controller payload shape assertion for `WR`**

```ruby
assert_equal "2026-05-11", body.dig("data", "comparison", "period", "from_date")
assert_equal "positive", body.dig("data", "comparison", "summary", "total_after_tax", "semantic")
```

- [ ] **Step 8: Run test to verify it fails**

Run: `bundle exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb`
Expected: FAIL because `WR` query does not include comparison data.

- [ ] **Step 9: Implement `WR` previous-period comparison payload**

```ruby
prev_from, prev_to = previous_period_range(@from_date, @to_date)
previous_service = build_service(previous_rate, from_date: prev_from, to_date: prev_to).call

{
  comparison: {
    period: { from_date: prev_from.to_s, to_date: prev_to.to_s },
    summary: build_wr_summary_comparison(service.summary, previous_service.summary, platform: @platform),
    rows: build_wr_row_comparison(service.results, previous_service.results, platform: @platform),
    extras: build_wr_unallocated_comparison(service.unallocated, previous_service.unallocated, platform: @platform)
  }
}
```

- [ ] **Step 10: Run controller test to verify it passes**

Run: `bundle exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb`
Expected: PASS

- [ ] **Step 11: Commit query/comparison payload work**

```bash
git add app/services/ec/weekly_summary_support.rb app/services/ec/weekly_summary_query.rb app/services/ec/weekly_summary_deep_query.rb app/services/ec/weekly_profit_report_query.rb test/services/ec/weekly_summary_query_test.rb test/services/ec/weekly_summary_deep_query_test.rb test/controllers/weekly_profit_reports_controller_test.rb
git commit -m "Add weekly profit comparison payloads"
```

### Task 2: Controller Helpers and View Rendering

**Files:**
- Modify: `app/controllers/weekly_profit_reports_controller.rb`
- Modify: `app/views/weekly_profit_reports/_summary_cards.html.erb`
- Modify: `app/views/weekly_profit_reports/_wr_results.html.erb`
- Modify: `app/views/weekly_profit_reports/_wsu_results.html.erb`
- Modify: `app/views/weekly_profit_reports/_wsu_deep_results.html.erb`
- Modify: `app/assets/stylesheets/application.css`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`
- Test: `test/controllers/weekly_profit_reports_controller_test.rb`

- [ ] **Step 1: Write failing HTML rendering assertions**

```ruby
assert_select ".weekly-profit-comparison-note", /上一等长自然周范围/
assert_select ".weekly-profit-comparison-trend", minimum: 1
assert_select ".weekly-profit-table-value", minimum: 1
assert_select ".weekly-profit-table-comparison", minimum: 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb`
Expected: FAIL because views do not render comparison note or comparison rows.

- [ ] **Step 3: Add controller helper methods for comparison lookup and formatting**

```ruby
def weekly_profit_report_comparison(report, key, row: nil, row_key: nil, scope: :rows)
  source = report.dig(:comparison, scope) || {}
  comparison_row = row_key ? source[row_key] : source
  comparison_row&.dig(key)
end

def weekly_profit_report_row_key(report, row)
  case report[:report_type]
  when "wsu" then [row[:sku], row[:platform], row[:shop]].join("|")
  when "wsu_deep" then row[:sku].to_s
  end
end
```

- [ ] **Step 4: Render current value plus comparison line in cards and table cells**

```erb
<div class="summary-value"><%= card[:value] %></div>
<div class="weekly-profit-comparison-trend <%= card[:comparison_class] %>">
  <%= card[:comparison_label] %>
</div>
```

```erb
<div class="weekly-profit-table-value"><%= weekly_profit_report_value(row, key) %></div>
<div class="weekly-profit-table-comparison <%= weekly_profit_report_comparison_class(comparison) %>">
  <%= weekly_profit_report_comparison_label(comparison) %>
</div>
```

- [ ] **Step 5: Add compact comparison styles**

```css
.weekly-profit-comparison-note { color: var(--erp-muted); font-size: 12px; }
.weekly-profit-comparison-trend,
.weekly-profit-table-comparison { margin-top: 4px; font-size: 11px; line-height: 1.2; }
.weekly-profit-comparison-trend.is-positive,
.weekly-profit-table-comparison.is-positive { color: #0f9d58; }
.weekly-profit-comparison-trend.is-negative,
.weekly-profit-table-comparison.is-negative { color: #d93025; }
```

- [ ] **Step 6: Add i18n strings for comparison note and fallback labels**

```yml
comparison:
  note: "环比基准：上一等长自然周范围"
  versus_previous: "vs 上一周期"
  unavailable: "-"
```

- [ ] **Step 7: Run controller test to verify it passes**

Run: `bundle exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb`
Expected: PASS

- [ ] **Step 8: Commit view rendering work**

```bash
git add app/controllers/weekly_profit_reports_controller.rb app/views/weekly_profit_reports/_summary_cards.html.erb app/views/weekly_profit_reports/_wr_results.html.erb app/views/weekly_profit_reports/_wsu_results.html.erb app/views/weekly_profit_reports/_wsu_deep_results.html.erb app/assets/stylesheets/application.css config/locales/zh.yml config/locales/en.yml config/locales/ru.yml test/controllers/weekly_profit_reports_controller_test.rb
git commit -m "Render weekly profit comparisons in report views"
```

### Task 3: Full Regression Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-07-08-weekly-profit-comparison.md`
- Test: `test/services/ec/weekly_summary_query_test.rb`
- Test: `test/services/ec/weekly_summary_deep_query_test.rb`
- Test: `test/controllers/weekly_profit_reports_controller_test.rb`
- Test: `test/services/google_sheets/weekly_summary_deep_service_test.rb`
- Test: `test/services/google_sheets/weekly_profit_report_runner_test.rb`

- [ ] **Step 1: Run full targeted Rails regression suite**

Run:

```bash
bundle exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb test/services/ec/weekly_summary_query_test.rb test/services/ec/weekly_summary_deep_query_test.rb test/services/ec/wb_profit_attribution_test.rb test/services/google_sheets/weekly_summary_deep_service_test.rb test/services/google_sheets/weekly_profit_report_runner_test.rb
```

Expected: PASS

- [ ] **Step 2: If failures expose spec drift, adjust tests and implementation in place**

```ruby
# Example drift fix: keep Google Sheet services consuming existing row fields
# while web views consume new comparison payload, instead of forcing sheet updates now.
```

- [ ] **Step 3: Re-run the same regression suite**

Run:

```bash
bundle exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb test/services/ec/weekly_summary_query_test.rb test/services/ec/weekly_summary_deep_query_test.rb test/services/ec/wb_profit_attribution_test.rb test/services/google_sheets/weekly_summary_deep_service_test.rb test/services/google_sheets/weekly_profit_report_runner_test.rb
```

Expected: PASS with `0 failures, 0 errors`

- [ ] **Step 4: Commit final integrated feature**

```bash
git add app/controllers/weekly_profit_reports_controller.rb app/services/ec/weekly_summary_support.rb app/services/ec/weekly_summary_query.rb app/services/ec/weekly_summary_deep_query.rb app/services/ec/weekly_profit_report_query.rb app/views/weekly_profit_reports/_summary_cards.html.erb app/views/weekly_profit_reports/_wr_results.html.erb app/views/weekly_profit_reports/_wsu_results.html.erb app/views/weekly_profit_reports/_wsu_deep_results.html.erb app/assets/stylesheets/application.css config/locales/zh.yml config/locales/en.yml config/locales/ru.yml test/controllers/weekly_profit_reports_controller_test.rb test/services/ec/weekly_summary_query_test.rb test/services/ec/weekly_summary_deep_query_test.rb
git commit -m "Add weekly profit period-over-period comparisons"
```
