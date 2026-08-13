# Weekly Profit Report Unified Web Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade `/weekly_profit_reports` into a unified weekly profit report page that supports `WR`, `WSU`, and `WSU-DEEP` with strict completed-natural-week validation and shared logic between Web and Google Sheet services.

**Architecture:** Keep the existing route and Turbo-based page shell, but replace the old `platform + account_id` controller model with `report_type + store_ref`. Extract reusable query objects for WR/WSU/WSU-DEEP so the Web layer and the Google Sheet writers consume the same calculation pipeline instead of duplicating summary logic.

**Tech Stack:** Rails 8, ERB, Turbo Frames, Minitest, Active Record, I18n

---

### Task 1: Lock The New Controller Contract With Failing Tests

**Files:**
- Modify: `test/controllers/weekly_profit_reports_controller_test.rb`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`

- [ ] **Step 1: Rewrite the index HTML test around the new filter contract**

```ruby
test "index renders weekly profit report filters for report type and store ref" do
  get "/weekly_profit_reports", headers: { "Accept" => "text/html" }

  assert_response :success
  assert_select "h1", I18n.t("weekly_profit_reports.title")
  assert_select "select[name='report_type'] option[value='wr']"
  assert_select "select[name='report_type'] option[value='wsu']"
  assert_select "select[name='report_type'] option[value='wsu_deep']"
  assert_select "select[name='store_ref'] option[value='wb:#{@wb_account.id}']", /WB/
  assert_select "select[name='store_ref'] option[value='ozon:#{@ozon_account.id}']", /Ozon/
  assert_select "input[name='from_date'][value=?]", (Date.current.beginning_of_week(:monday) - 7.days).iso8601
  assert_select "input[name='to_date'][value=?]", (Date.current.beginning_of_week(:monday) - 1.day).iso8601
end
```

- [ ] **Step 2: Add failing JSON tests for WR/WSU/WSU-DEEP dispatch and week validation**

```ruby
test "show requires store_ref for wr" do
  get "/weekly_profit_reports.json", params: {
    report_type: "wr",
    from_date: "2026-05-18",
    to_date: "2026-05-24"
  }

  assert_response :bad_request
end

test "show rejects current week range" do
  monday = Date.current.beginning_of_week(:monday)
  sunday = monday + 6

  get "/weekly_profit_reports.json", params: {
    report_type: "wsu",
    from_date: monday.iso8601,
    to_date: sunday.iso8601
  }

  assert_response :unprocessable_entity
end

test "show rejects non natural week range" do
  get "/weekly_profit_reports.json", params: {
    report_type: "wsu",
    from_date: "2026-05-19",
    to_date: "2026-05-24"
  }

  assert_response :unprocessable_entity
end
```

- [ ] **Step 3: Add failing dispatch tests that stub future query objects**

```ruby
test "show dispatches wr query for wb store ref" do
  rate = Ec::WeeklyRate.create!(week_start: Date.parse("2026-05-18"), rate_cny_rub: 10.93, rate_byn_rub: 26.41)
  payload = { report_type: "wr", meta: { platform: "wb" }, summary: { total_after_tax: 88.5 }, rows: [], extras: {} }
  original_run = Ec::WeeklyProfitReportQuery.method(:run) rescue nil

  Ec::WeeklyProfitReportQuery.define_singleton_method(:run) do |**kwargs|
    assert_equal "wb:#{@wb_account.id}", kwargs[:store_ref]
    assert_equal Date.parse("2026-05-18"), kwargs[:from_date]
    assert_equal Date.parse("2026-05-24"), kwargs[:to_date]
    payload
  end

  get "/weekly_profit_reports.json", params: {
    report_type: "wr",
    store_ref: "wb:#{@wb_account.id}",
    from_date: "2026-05-18",
    to_date: "2026-05-24"
  }

  assert_response :success
  assert_equal "wr", JSON.parse(response.body).dig("data", "report_type")
ensure
  Ec::WeeklyProfitReportQuery.define_singleton_method(:run, original_run) if original_run
  rate.destroy!
end
```

- [ ] **Step 4: Run the controller tests and verify RED**

Run: `bundle exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb`

Expected: FAIL because the controller still expects `platform` and `account_id`, has no week validation, and no query objects exist yet.

- [ ] **Step 5: Commit the red controller tests**

```bash
git add test/controllers/weekly_profit_reports_controller_test.rb
git commit -m "test: cover unified weekly profit report controller contract"
```

### Task 2: Add Shared Query Objects For WR / WSU / WSU-DEEP

**Files:**
- Create: `app/services/ec/weekly_profit_report_query.rb`
- Create: `app/services/ec/weekly_summary_query.rb`
- Create: `app/services/ec/weekly_summary_deep_query.rb`
- Create: `test/services/ec/weekly_summary_query_test.rb`
- Create: `test/services/ec/weekly_summary_deep_query_test.rb`
- Modify: `app/services/google_sheets/weekly_summary_service.rb`
- Modify: `app/services/google_sheets/weekly_summary_deep_service.rb`

- [ ] **Step 1: Write failing tests for the shared summary query objects**

```ruby
require "test_helper"

class Ec::WeeklySummaryQueryTest < ActiveSupport::TestCase
  test "run returns summary rows and meta for wsu" do
    payload = Ec::WeeklySummaryQuery.run(
      from_date: Date.new(2026, 5, 25),
      to_date: Date.new(2026, 5, 31)
    )

    assert_equal "wsu", payload[:report_type]
    assert payload[:meta][:rates]
    assert_kind_of Array, payload[:rows]
    assert payload[:summary].key?(:total_sales_revenue)
  end
end
```

```ruby
require "test_helper"

class Ec::WeeklySummaryDeepQueryTest < ActiveSupport::TestCase
  test "run aggregates rows by sku for wsu deep" do
    payload = Ec::WeeklySummaryDeepQuery.run(
      from_date: Date.new(2026, 5, 25),
      to_date: Date.new(2026, 5, 31)
    )

    assert_equal "wsu_deep", payload[:report_type]
    assert_kind_of Array, payload[:rows]
    assert payload[:summary].key?(:total_after_tax)
  end
end
```

- [ ] **Step 2: Run the new service tests and verify RED**

Run: `bundle exec ruby bin/rails test test/services/ec/weekly_summary_query_test.rb test/services/ec/weekly_summary_deep_query_test.rb`

Expected: FAIL because the new query classes do not exist.

- [ ] **Step 3: Implement minimal query objects by extracting current non-sheet logic**

```ruby
module Ec
  class WeeklySummaryQuery
    def self.run(from_date:, to_date:)
      new(from_date:, to_date:).run
    end

    def initialize(from_date:, to_date:)
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @rate = Ec::WeeklyRate.resolve(@from_date)
      raise "找不到 #{@from_date} 的汇率，请先录入 ec_weekly_rates" unless @rate
    end

    def run
      rows, unalloc_cny = collect_rows(@from_date, @to_date, @rate)
      prev_rows, = previous_rows
      prev_map = prev_rows.index_by { |row| [row[:sku], row[:platform], row[:shop]] }

      {
        report_type: "wsu",
        period: { from_date: @from_date.to_s, to_date: @to_date.to_s },
        meta: { rates: { rate_cny_rub: @rate.rate_cny_rub, rate_byn_rub: @rate.rate_byn_rub } },
        summary: build_summary(rows, unalloc_cny),
        rows: build_rows(rows, prev_map),
        extras: {}
      }
    end
  end
end
```

- [ ] **Step 4: Update the Google Sheet services to consume the query objects instead of duplicating the summary-building logic**

```ruby
query = Ec::WeeklySummaryQuery.run(from_date: @from_date, to_date: @to_date)
data_rows = query[:rows].map { |row| [...] }
summary_rows = query[:summary]
```

```ruby
query = Ec::WeeklySummaryDeepQuery.run(from_date: @from_date, to_date: @to_date)
data_rows = query[:rows].map { |row| [...] }
summary_rows = query[:summary]
```

- [ ] **Step 5: Run the new service tests plus the existing deep service regression test**

Run: `bundle exec ruby bin/rails test test/services/ec/weekly_summary_query_test.rb test/services/ec/weekly_summary_deep_query_test.rb test/services/google_sheets/weekly_summary_deep_service_test.rb`

Expected: PASS with the Google Sheet service still producing the same summary/table content from the shared query outputs.

- [ ] **Step 6: Commit the shared query extraction**

```bash
git add app/services/ec/weekly_profit_report_query.rb app/services/ec/weekly_summary_query.rb app/services/ec/weekly_summary_deep_query.rb app/services/google_sheets/weekly_summary_service.rb app/services/google_sheets/weekly_summary_deep_service.rb test/services/ec/weekly_summary_query_test.rb test/services/ec/weekly_summary_deep_query_test.rb
git commit -m "feat: add shared weekly profit summary queries"
```

### Task 3: Rebuild The Weekly Profit Controller Around `report_type` And `store_ref`

**Files:**
- Modify: `app/controllers/weekly_profit_reports_controller.rb`
- Modify: `test/controllers/weekly_profit_reports_controller_test.rb`

- [ ] **Step 1: Implement the minimal controller contract**

```ruby
def show
  return render_index if html_index_request?

  parsed = parse_request_params
  return unless parsed

  @report = run_report_query(parsed)
  respond_to do |format|
    format.html { render partial: "weekly_profit_reports/results", status: :ok }
    format.json { render json: { success: true, data: @report, message: "ok" } }
  end
rescue ActiveRecord::RecordNotFound
  render_error(t("weekly_profit_reports.errors.store_not_found"), :not_found)
end
```

- [ ] **Step 2: Add strict completed-natural-week validation in the controller**

```ruby
def validate_period!(from_date, to_date)
  today = user_today
  current_monday = today.beginning_of_week(:monday)
  raise ArgumentError, t("weekly_profit_reports.errors.invalid_week_range") unless from_date.cwday == 1 && to_date.cwday == 7
  raise ArgumentError, t("weekly_profit_reports.errors.invalid_week_range") unless ((to_date - from_date).to_i + 1) % 7 == 0
  raise ArgumentError, t("weekly_profit_reports.errors.current_week_unsupported") if to_date >= current_monday
end
```

- [ ] **Step 3: Parse `store_ref` instead of `platform` and `account_id`**

```ruby
def parse_store_ref!(value)
  platform, raw_id = value.to_s.split(":", 2)
  raise ArgumentError, t("weekly_profit_reports.errors.invalid_store_ref") unless %w[wb ozon].include?(platform) && raw_id.present?
  [platform, Integer(raw_id)]
end
```

- [ ] **Step 4: Dispatch to the new query objects**

```ruby
def run_report_query(parsed)
  case parsed[:report_type]
  when "wr"
    Ec::WeeklyProfitReportQuery.run(**parsed.slice(:store_ref, :from_date, :to_date))
  when "wsu"
    Ec::WeeklySummaryQuery.run(from_date: parsed[:from_date], to_date: parsed[:to_date])
  when "wsu_deep"
    Ec::WeeklySummaryDeepQuery.run(from_date: parsed[:from_date], to_date: parsed[:to_date])
  else
    raise ArgumentError, t("weekly_profit_reports.errors.invalid_report_type")
  end
end
```

- [ ] **Step 5: Run the controller tests and verify GREEN**

Run: `bundle exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb`

Expected: PASS with WR/WSU/WSU-DEEP dispatch and strict week validation enforced.

- [ ] **Step 6: Commit the controller rewrite**

```bash
git add app/controllers/weekly_profit_reports_controller.rb test/controllers/weekly_profit_reports_controller_test.rb
git commit -m "feat: route weekly profit reports by report type"
```

### Task 4: Rework The ERB Filters And Result Partials

**Files:**
- Modify: `app/views/weekly_profit_reports/show.html.erb`
- Modify: `app/views/weekly_profit_reports/_results.html.erb`
- Create: `app/views/weekly_profit_reports/_wr_results.html.erb`
- Create: `app/views/weekly_profit_reports/_wsu_results.html.erb`
- Create: `app/views/weekly_profit_reports/_wsu_deep_results.html.erb`
- Create: `app/views/weekly_profit_reports/_summary_cards.html.erb`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`

- [ ] **Step 1: Update the filter form to use `report_type` and `store_ref`**

```erb
<div class="field">
  <label for="weekly-profit-report-type"><%= t("weekly_profit_reports.filters.report_type") %></label>
  <select id="weekly-profit-report-type" name="report_type" required data-weekly-profit-report-type>
    <option value="wr">WR</option>
    <option value="wsu">WSU</option>
    <option value="wsu_deep">WSU-DEEP</option>
  </select>
</div>

<div class="field" data-weekly-profit-store-field>
  <label for="weekly-profit-store-ref"><%= t("weekly_profit_reports.filters.store") %></label>
  <select id="weekly-profit-store-ref" name="store_ref">
    <% @store_options.each do |store| %>
      <option value="<%= store[:ref] %>"><%= store[:label] %></option>
    <% end %>
  </select>
</div>
```

- [ ] **Step 2: Add the minimal progressive-enhancement script for showing or hiding the store field**

```html
<script>
  document.addEventListener("turbo:load", () => {
    const reportType = document.querySelector("[data-weekly-profit-report-type]");
    const storeField = document.querySelector("[data-weekly-profit-store-field]");
    const storeSelect = document.getElementById("weekly-profit-store-ref");
    if (!reportType || !storeField || !storeSelect) return;

    const syncStoreVisibility = () => {
      const needsStore = reportType.value === "wr";
      storeField.hidden = !needsStore;
      storeSelect.required = needsStore;
    };

    reportType.addEventListener("change", syncStoreVisibility);
    syncStoreVisibility();
  });
</script>
```

- [ ] **Step 3: Split the result rendering by report type**

```erb
<turbo-frame id="weekly_profit_report_results">
  <% case @report[:report_type] %>
  <% when "wr" %>
    <%= render "weekly_profit_reports/wr_results", report: @report %>
  <% when "wsu" %>
    <%= render "weekly_profit_reports/wsu_results", report: @report %>
  <% when "wsu_deep" %>
    <%= render "weekly_profit_reports/wsu_deep_results", report: @report %>
  <% end %>
</turbo-frame>
```

- [ ] **Step 4: Add I18n keys for the new filters, errors, labels, and empty state**

```yml
weekly_profit_reports:
  empty_state: "请选择周期和归集类型后查询"
  filters:
    date_range: "时间范围"
    report_type: "归集类型"
    store: "店铺"
    submit: "查询"
  errors:
    current_week_unsupported: "当前自然周尚不可查询"
    invalid_report_type: "不支持的归集类型"
    invalid_store_ref: "店铺参数无效"
    invalid_week_range: "只能查询已完成的完整自然周"
    store_not_found: "店铺不存在或未启用"
```

- [ ] **Step 5: Run the controller tests again to verify the rendered HTML and localization changes**

Run: `bundle exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb`

Expected: PASS with the new HTML structure and localized validations.

- [ ] **Step 6: Commit the ERB and locale changes**

```bash
git add app/views/weekly_profit_reports/show.html.erb app/views/weekly_profit_reports/_results.html.erb app/views/weekly_profit_reports/_wr_results.html.erb app/views/weekly_profit_reports/_wsu_results.html.erb app/views/weekly_profit_reports/_wsu_deep_results.html.erb app/views/weekly_profit_reports/_summary_cards.html.erb config/locales/zh.yml config/locales/en.yml config/locales/ru.yml
git commit -m "feat: add unified weekly profit report views"
```

### Task 5: Full Regression Verification

**Files:**
- Modify: `app/controllers/weekly_profit_reports_controller.rb`
- Modify: `app/views/weekly_profit_reports/*.erb`
- Modify: `app/services/ec/*.rb`
- Modify: `app/services/google_sheets/*.rb`
- Modify: `test/controllers/weekly_profit_reports_controller_test.rb`
- Modify: `test/services/ec/*.rb`

- [ ] **Step 1: Run all targeted tests for the feature**

Run: `bundle exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb test/services/ec/wb_profit_attribution_test.rb test/services/ec/weekly_summary_query_test.rb test/services/ec/weekly_summary_deep_query_test.rb test/services/google_sheets/weekly_summary_deep_service_test.rb test/services/google_sheets/weekly_profit_report_runner_test.rb`

Expected: PASS

- [ ] **Step 2: Review the final diff**

Run: `git diff -- app/controllers/weekly_profit_reports_controller.rb app/views/weekly_profit_reports app/services/ec app/services/google_sheets config/locales test/controllers/weekly_profit_reports_controller_test.rb test/services/ec test/services/google_sheets`

Expected: Only the unified weekly profit page, shared query extraction, locale updates, and related tests.

- [ ] **Step 3: Commit the verified implementation**

```bash
git add app/controllers/weekly_profit_reports_controller.rb app/views/weekly_profit_reports app/services/ec app/services/google_sheets config/locales test/controllers/weekly_profit_reports_controller_test.rb test/services/ec test/services/google_sheets docs/superpowers/specs/2026-07-08-weekly-profit-report-unified-web-design.md docs/superpowers/plans/2026-07-08-weekly-profit-report-unified-web.md
git commit -m "feat: unify weekly profit reports across wr wsu and wsu deep"
```
