# Global Time Range Selector Design

## Goal

Implement one shared ERP time range selector that matches the new global design standard while remaining compatible with the project's existing GET-based report filtering.

## Scope

### In scope for the first implementation

- Build one shared time range selector component for Rails HTML pages
- Preserve the existing query contract of `from_date` and `to_date` only
- First rollout targets:
  - `GET /reports/sku_sales`
  - `GET /reports/skus/:sku_code?tab=stores`
  - `GET /reports/skus/:sku_code?tab=trend`

### Explicitly out of scope for the first implementation

- Converting Ransack-style date parameters such as `q[ordered_at_gteq]`
- Adding new URL params such as `range_preset` or `range_mode`
- Calling APIs or mutating server data from the component
- Building separate page-local range pickers

## Product constraints

- The component follows `docs/design/docs/global-time-range-selector-standard.md`
- Natural weeks start on Monday
- The component has separated applied state and draft state
- Filtering commits only when the user clicks `应用筛选`
- The right rail contains only quick presets and footer actions
- The visible page query remains `from_date` and `to_date`
- User-facing text must go through Rails I18n

## Existing project context

Current report pages already use plain GET params with visible date inputs:

- `app/views/reports/sku_sales.html.erb`
- `app/views/reports/sku_detail.html.erb`

Current controllers already parse and default `from_date` and `to_date`:

- `ReportsController#sku_sales`
- `ReportsController#load_sku_detail`

This is the key compatibility anchor. The first implementation must preserve those controller inputs so no backend query interface needs to change.

## Chosen approach

Use one shared Rails partial plus one shared Stimulus controller.

### Shared partial responsibilities

- Render the trigger field and popover shell
- Render hidden `from_date` and `to_date` inputs that belong to the enclosing GET form
- Render I18n-backed labels for title, presets, week jumps, reset, and apply
- Accept applied `from_date` and `to_date` from the page
- Accept a mode that tells the component whether apply should submit the form

### Shared Stimulus controller responsibilities

- Hold draft state, applied state, visible month, hover state, and open state
- Support:
  - natural week selection
  - arbitrary day range selection
  - presets
  - reset to current week
  - close on outside click
  - close on `Esc`
  - focus restoration to the trigger
- On apply:
  - validate draft start and end
  - copy values into hidden `from_date` and `to_date`
  - update the trigger summary
  - optionally submit the owning form

## Query compatibility strategy

The shared component is internal UI only. The page-facing query contract stays unchanged.

### Required compatibility rules

- URL output remains only `from_date=YYYY-MM-DD` and `to_date=YYYY-MM-DD`
- Existing non-date filters remain untouched in the same form submission
- Existing hidden fields such as `tab` and `locale` remain untouched
- Existing controller defaults for missing dates remain valid
- Existing tests that assert `from_date` and `to_date` remain conceptually correct

### Preset and mode handling

- No preset or mode is persisted in the URL
- The component infers whether the applied range matches:
  - this week
  - last week
  - last 14 days
  - last 30 days
- This inference is only for trigger summary/tag rendering and active preset highlighting
- `from_date` and `to_date` remain the only source of truth outside the component

## Apply behavior

The first rollout uses one shared component behavior with form submission enabled.

When the user clicks `应用筛选`:

1. Commit draft start and end into applied state
2. Write normalized dates into hidden `from_date` and `to_date`
3. Submit the owning GET form with `requestSubmit()`

This preserves the design intent that apply is the commit point while remaining fully compatible with the current report search flow.

## Why not keep a separate page-level search button for the time range

That would split the meaning of “apply” and “search”:

- the popover would say filtering is applied
- the page results would still be stale until another button click

That mismatch is worse than a small implementation increase. The chosen behavior keeps the time selector semantically complete while preserving all existing GET params.

## Page rollout plan

### Phase 1 pages

#### `app/views/reports/sku_sales.html.erb`

- Replace the visible `from_date` and `to_date` date inputs with the shared component
- Keep the rest of the report form unchanged
- Preserve selected SKU, platform, store, grain, and period params during apply-submit

#### `app/views/reports/sku_detail.html.erb`

Apply the shared component in both report-like tabs:

- `tab=stores`
- `tab=trend`

Requirements:

- preserve `tab`
- preserve `period`, `grain`, `platform`, `store_id` where relevant
- keep current backend param parsing untouched

### Later expansion

Other date-range surfaces across the system should adopt the same shared component, but pages using non-`from_date/to_date` params need an adapter layer instead of direct reuse of the first-phase markup contract.

## UI and DOM contract

The implementation should follow the standard document's structure as closely as practical in Rails/Stimulus:

- one visible trigger
- one anchored popover
- left calendar pane
- right compact preset pane
- reset and apply footer

The component should not introduce:

- a second selected summary card inside the popover
- day-adjust controls in the side rail
- immediate query on day click
- page-local alternative popover layouts

## Styling direction

Use shared application CSS and project tokens rather than page-local styling.

Implementation target:

- add shared selector styles to `app/assets/stylesheets/application.css`
- keep selectors namespaced to the component
- avoid layout regressions in the existing `report-form` flex row

Because the new trigger is wider than a single date input, the form must still wrap cleanly on narrower widths without requiring a separate mobile component.

## Accessibility and keyboard behavior

Minimum implementation requirements:

- trigger exposes `aria-haspopup`, `aria-expanded`, and `aria-controls`
- popover uses `role="dialog"` with an accessible label
- icon-only buttons have accessible labels
- `Enter` or `Space` opens from the trigger
- `Esc` closes without mutating applied state
- keyboard users can reach presets, week jumps, navigation, reset, and apply

Arrow-key day-grid navigation is desirable, but first implementation priority is a complete keyboard-accessible open/select/apply/close flow.

## State model

The Stimulus controller should keep these concepts separate:

- applied start
- applied end
- applied preset
- draft start
- draft end
- draft preset
- visible month
- open state
- hover date
- drag anchor

All comparisons should use normalized local dates with no time component.

## Test strategy

Use TDD for the implementation.

### Controller/view coverage

Add request or controller tests that verify:

- target pages still render successfully with `from_date` and `to_date`
- hidden query fields remain present after markup conversion
- the shared component markup appears on the phase 1 pages
- existing `tab` and locale preservation still work

### Stimulus coverage

Add JavaScript tests for:

- applied state initializes from hidden inputs
- draft changes do not mutate hidden inputs before apply
- apply writes hidden inputs
- apply submits the form in submit mode
- reset returns draft state to current natural week
- preset selection updates the draft range

## Risks and mitigations

### Risk: form submission drops other filters

Mitigation:

- keep the component inside the existing form
- write only date fields
- submit the owner form instead of constructing a custom URL

### Risk: preset tag becomes inconsistent with current dates

Mitigation:

- always derive active preset from applied `from_date` and `to_date`
- never persist preset as independent state outside the controller

### Risk: wider trigger breaks current report filter layout

Mitigation:

- test the existing `report-form` wrapping behavior
- keep component styles shared and compact

## Acceptance criteria

Phase 1 is complete when:

- one shared component powers time range selection on `sku_sales` and SKU detail `stores/trend`
- query URLs still use only `from_date` and `to_date`
- applying a range submits the existing GET form with all current filters intact
- the popover keeps draft state separate from applied state
- reset and preset behaviors match the design standard
- no page-specific duplicate time picker implementation is introduced
