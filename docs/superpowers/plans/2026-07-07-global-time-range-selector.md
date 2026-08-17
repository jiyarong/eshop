# Global Time Range Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the phase-1 report pages' visible `from_date` and `to_date` inputs with one shared global time range selector that preserves the existing GET query contract.

**Architecture:** Build one reusable Rails partial plus one shared Stimulus controller. The component owns draft/applied range state and writes only hidden `from_date` / `to_date` inputs back into the existing GET form, then submits that form on apply for the initial rollout.

**Tech Stack:** Rails 8, ERB partials, Stimulus, existing application.css, Rails controller/request tests, Node `node:test` JavaScript tests with `esbuild`

---

### Task 1: Lock the server-rendered integration contract with failing tests

**Files:**
- Modify: `test/controllers/reports_controller_test.rb`
- Test: `test/controllers/reports_controller_test.rb`

- [ ] **Step 1: Write the failing report-page integration tests**

Add request assertions that the shared range selector markup replaces the old visible date fields on the phase-1 pages and preserves current filter params.

```ruby
  test "sku sales report renders shared time range selector" do
    get "/reports/sku_sales", params: {
      sku_codes: [@sku.sku_code],
      grain: "store",
      period: "day",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "[data-controller='time-range-selector']", count: 1
    assert_select "input[name='from_date'][type='hidden'][value='2026-06-01']", count: 1
    assert_select "input[name='to_date'][type='hidden'][value='2026-06-08']", count: 1
    assert_select "button[aria-controls='sku-sales-time-range-popover']", count: 1
    assert_select "#sku-sales-time-range-popover[role='dialog']", count: 1
    assert_select "input#from_date[type='date']", count: 0
    assert_select "input#to_date[type='date']", count: 0
  end

  test "sku detail stores tab renders shared time range selector and preserves tab" do
    get "/reports/skus/#{@sku.sku_code}", params: {
      tab: "stores",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "[data-controller='time-range-selector']", count: 1
    assert_select "input[name='tab'][value='stores']", count: 1
    assert_select "input[name='from_date'][type='hidden'][value='2026-06-01']", count: 1
    assert_select "input[name='to_date'][type='hidden'][value='2026-06-08']", count: 1
    assert_select "input#from_date[type='date']", count: 0
    assert_select "input#to_date[type='date']", count: 0
  end

  test "sku detail trend tab renders shared time range selector and preserves period controls" do
    get "/reports/skus/#{@sku.sku_code}", params: {
      tab: "trend",
      period: "week",
      grain: "platform",
      from_date: "2026-06-01",
      to_date: "2026-06-08"
    }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "[data-controller='time-range-selector']", count: 1
    assert_select "input[name='tab'][value='trend']", count: 1
    assert_select "select[name='period'] option[selected]", "Week"
    assert_select "select[name='grain'] option[selected]", "Platform"
    assert_select "input#trend_from_date[type='date']", count: 0
    assert_select "input#trend_to_date[type='date']", count: 0
  end
```

- [ ] **Step 2: Run the targeted Rails test to verify it fails**

Run: `SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb -n "/shared time range selector|preserves tab|preserves period controls/"`

Expected: FAIL because the phase-1 pages still render direct date inputs and do not contain the shared selector markup.

- [ ] **Step 3: Commit the red test**

```bash
git add test/controllers/reports_controller_test.rb
git commit -m "test: cover report time range selector integration"
```

### Task 2: Lock the front-end state contract with failing JavaScript tests

**Files:**
- Create: `test/javascript/time_range_selector_controller_test.mjs`
- Test: `test/javascript/time_range_selector_controller_test.mjs`

- [ ] **Step 1: Write the failing JavaScript tests for draft/apply behavior**

Create a controller-focused test file that bundles `app/javascript/controllers/time_range_selector_controller.js` and exercises exported pure helpers plus a small fake DOM harness for apply behavior.

```javascript
import assert from "node:assert/strict";
import { test } from "node:test";
import { build } from "esbuild";

const bundle = await build({
  entryPoints: ["app/javascript/controllers/time_range_selector_controller.js"],
  bundle: true,
  format: "esm",
  platform: "browser",
  write: false,
});

const [{ normalizeDateValue, resolvePreset, buildApplyPayload, resetDraftToCurrentWeek }] =
  await Promise.all(bundle.outputFiles.map((file) => import(`data:text/javascript;base64,${Buffer.from(file.text).toString("base64")}`)));

test("resolvePreset matches this week from normalized applied dates", () => {
  assert.equal(
    resolvePreset({ fromDate: "2026-07-06", toDate: "2026-07-12", today: "2026-07-08" }),
    "thisWeek",
  );
});

test("buildApplyPayload keeps hidden inputs unchanged until apply and writes normalized values on apply", () => {
  assert.deepEqual(
    buildApplyPayload({
      draftStart: new Date(2026, 5, 1),
      draftEnd: new Date(2026, 5, 8),
    }),
    { fromDate: "2026-06-01", toDate: "2026-06-08" },
  );
});

test("resetDraftToCurrentWeek returns monday through sunday for the provided today value", () => {
  assert.deepEqual(
    resetDraftToCurrentWeek("2026-07-08"),
    { fromDate: "2026-07-06", toDate: "2026-07-12", mode: "week", preset: "thisWeek" },
  );
});
```

- [ ] **Step 2: Run the JavaScript test to verify it fails**

Run: `node --test test/javascript/time_range_selector_controller_test.mjs`

Expected: FAIL because `app/javascript/controllers/time_range_selector_controller.js` does not exist yet and none of the exported helpers are available.

- [ ] **Step 3: Commit the red JavaScript test**

```bash
git add test/javascript/time_range_selector_controller_test.mjs
git commit -m "test: cover time range selector controller state"
```

### Task 3: Implement the shared selector partial, controller registration, and I18n strings

**Files:**
- Create: `app/views/shared/_time_range_selector.html.erb`
- Create: `app/javascript/controllers/time_range_selector_controller.js`
- Modify: `app/javascript/application.js`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`

- [ ] **Step 1: Add the shared partial with hidden inputs and design-standard structure**

Create the shared partial with locals for `id`, `from_date`, `to_date`, `submit_on_apply`, and optional form label keys. The partial should render one trigger, one popover, hidden `from_date` and `to_date` inputs, and all labels via I18n.

```erb
<div
  class="time-range-field"
  data-controller="time-range-selector"
  data-time-range-selector-from-date-value="<%= from_date %>"
  data-time-range-selector-to-date-value="<%= to_date %>"
  data-time-range-selector-submit-on-apply-value="<%= submit_on_apply %>"
  data-time-range-selector-popover-id-value="<%= "#{id}-popover" %>">
  <input type="hidden" name="from_date" value="<%= from_date %>" data-time-range-selector-target="fromInput">
  <input type="hidden" name="to_date" value="<%= to_date %>" data-time-range-selector-target="toInput">

  <button
    id="<%= "#{id}-trigger" %>"
    class="time-range-trigger"
    type="button"
    aria-haspopup="dialog"
    aria-expanded="false"
    aria-controls="<%= "#{id}-popover" %>"
    data-action="time-range-selector#toggle">
    <span class="time-range-trigger-value" data-time-range-selector-target="triggerValue"></span>
    <span class="time-range-trigger-icon" aria-hidden="true"> </span>
  </button>

  <section
    id="<%= "#{id}-popover" %>"
    class="time-range-popover"
    role="dialog"
    aria-modal="false"
    aria-label="<%= t("shared.time_range.aria_label") %>"
    hidden
    data-time-range-selector-target="popover">
    ...
  </section>
</div>
```

- [ ] **Step 2: Implement the Stimulus controller and export pure helpers**

Create the controller with applied/draft state, preset resolution, reset-to-this-week, apply handling, and document-level close behavior. Export pure helpers so the JavaScript tests can import them directly.

```javascript
import { Controller } from "@hotwired/stimulus";

export function normalizeDateValue(date) {
  const normalized = date instanceof Date ? date : new Date(date);
  const year = normalized.getFullYear();
  const month = String(normalized.getMonth() + 1).padStart(2, "0");
  const day = String(normalized.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function resetDraftToCurrentWeek(todayValue = normalizeDateValue(new Date())) {
  const today = new Date(todayValue);
  const day = today.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  const start = new Date(today.getFullYear(), today.getMonth(), today.getDate() + diff);
  const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6);
  return {
    fromDate: normalizeDateValue(start),
    toDate: normalizeDateValue(end),
    mode: "week",
    preset: "thisWeek",
  };
}

export default class extends Controller {
  static targets = ["fromInput", "toInput", "popover", "triggerValue"];
  static values = {
    fromDate: String,
    toDate: String,
    submitOnApply: { type: Boolean, default: false },
    popoverId: String,
  };

  connect() {
    this.applied = { fromDate: this.fromDateValue, toDate: this.toDateValue };
    this.draft = { ...this.applied };
    this.render();
  }

  apply() {
    this.fromInputTarget.value = this.draft.fromDate;
    this.toInputTarget.value = this.draft.toDate;
    this.applied = { ...this.draft };
    this.render();
    this.close();
    if (this.submitOnApplyValue) this.element.closest("form")?.requestSubmit();
  }
}
```

- [ ] **Step 3: Register the controller and add I18n labels**

Register the new controller in `app/javascript/application.js` and add shared locale keys for:

```yaml
shared:
  time_range:
    aria_label: "时间范围选择器"
    title: "自然周优先选择"
    presets:
      this_week: "本周"
      last_week: "上周"
      last_14_days: "最近14天"
      last_30_days: "最近30天"
    actions:
      reset_this_week: "重置本周"
      apply: "应用筛选"
    jumps:
      previous_week: "-1周"
      this_week: "本周"
      next_week: "+1周"
      previous_month: "上一月"
      next_month: "下一月"
```

- [ ] **Step 4: Run the JavaScript test to verify it passes**

Run: `node --test test/javascript/time_range_selector_controller_test.mjs`

Expected: PASS with all helper/state tests green.

- [ ] **Step 5: Commit the shared component foundation**

```bash
git add app/views/shared/_time_range_selector.html.erb app/javascript/controllers/time_range_selector_controller.js app/javascript/application.js config/locales/zh.yml config/locales/en.yml config/locales/ru.yml test/javascript/time_range_selector_controller_test.mjs
git commit -m "feat: add shared time range selector component"
```

### Task 4: Wire the shared selector into the phase-1 report pages

**Files:**
- Modify: `app/views/reports/sku_sales.html.erb`
- Modify: `app/views/reports/sku_detail.html.erb`
- Modify: `test/controllers/reports_controller_test.rb`

- [ ] **Step 1: Replace the direct date inputs in `sku_sales`**

Swap the visible date fields for the shared partial and pass a stable DOM id plus `submit_on_apply: true`.

```erb
      <div class="field field--time-range">
        <label><%= t("reports.sku_detail.filters.date_range") %></label>
        <%= render "shared/time_range_selector",
                   id: "sku-sales-time-range",
                   from_date: @from_date,
                   to_date: @to_date,
                   submit_on_apply: true %>
      </div>
```

- [ ] **Step 2: Replace the direct date inputs in the SKU detail `stores` and `trend` tabs**

Update both forms to use the shared partial while preserving the hidden `tab` field and the existing non-date filters.

```erb
      <div class="field field--time-range">
        <label><%= t("reports.sku_detail.filters.date_range") %></label>
        <%= render "shared/time_range_selector",
                   id: "sku-detail-stores-time-range",
                   from_date: @from_date,
                   to_date: @to_date,
                   submit_on_apply: true %>
      </div>
```

and:

```erb
      <div class="field field--time-range">
        <label><%= t("reports.sku_detail.filters.date_range") %></label>
        <%= render "shared/time_range_selector",
                   id: "sku-detail-trend-time-range",
                   from_date: @from_date,
                   to_date: @to_date,
                   submit_on_apply: true %>
      </div>
```

- [ ] **Step 3: Run the targeted Rails test to verify it passes**

Run: `SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb -n "/shared time range selector|preserves tab|preserves period controls/"`

Expected: PASS with the updated markup assertions green.

- [ ] **Step 4: Commit the page wiring**

```bash
git add app/views/reports/sku_sales.html.erb app/views/reports/sku_detail.html.erb test/controllers/reports_controller_test.rb
git commit -m "feat: adopt shared time range selector on report pages"
```

### Task 5: Add shared styling and finish full verification

**Files:**
- Modify: `app/assets/stylesheets/application.css`
- Test: `test/controllers/reports_controller_test.rb`
- Test: `test/javascript/time_range_selector_controller_test.mjs`

- [ ] **Step 1: Add namespaced shared CSS for the trigger, popover, calendar pane, and compact side rail**

Append shared styles that keep the component aligned with the design standard while respecting existing report-form wrapping.

```css
.time-range-field {
  position: relative;
  min-width: min(100%, 320px);
}

.time-range-trigger {
  width: min(100%, 360px);
  min-height: 38px;
  display: inline-flex;
  align-items: center;
  justify-content: space-between;
  border: 1px solid var(--erp-border-strong);
  border-radius: 6px;
  background: #fff;
  padding: 0 12px;
}

.time-range-popover {
  position: absolute;
  top: calc(100% + 8px);
  left: 0;
  z-index: 40;
  width: min(704px, calc(100vw - 56px));
  border: 1px solid var(--erp-border);
  border-radius: 8px;
  background: #fff;
  box-shadow: 0 16px 32px rgba(24, 34, 53, 0.16);
}
```

- [ ] **Step 2: Run the focused verification suite**

Run:

```bash
node --test test/javascript/time_range_selector_controller_test.mjs
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb -n "/shared time range selector|sku sales report renders chart and grouped sales metrics|sku detail renders store sales tab without other sku data|sku detail renders sales trend tab/"
```

Expected:

- JavaScript tests PASS
- Rails tests PASS, including existing report rendering coverage around `sku_sales`, `stores`, and `trend`

- [ ] **Step 3: Commit the styling and final verification state**

```bash
git add app/assets/stylesheets/application.css
git commit -m "style: add shared report time range selector styles"
```

