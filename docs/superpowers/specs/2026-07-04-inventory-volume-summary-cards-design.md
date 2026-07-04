# Inventory Volume Summary Cards Design

## Summary

This change adds a summary card row to the inventory list page so users can see total estimated volume for the filtered SKU set without being affected by pagination.

Affected surface:

- `GET /reports/inventory`

The scope is limited to page-facing query/controller logic, ERB rendering, I18n text, and test coverage for the summary contract.

## Goals

- Add four summary cards between the filter form and the inventory table.
- Show filtered-set totals for the same four stock columns that already display per-row estimated volume:
  - `采购中库存`
  - `账面可用库存`
  - `FBO/FBW在库`
  - `FBS库存`
- Make the summary independent of the current page so totals stay stable across pagination.
- Exclude missing and non-positive volume results from aggregation.

## Non-Goals

- No new routes or API responses.
- No changes to inventory list pagination behavior.
- No changes to the underlying inventory ownership formulas in `Ec::SkuInventoryOverview`.
- No changes to the existing row-level size and estimated-volume display contract beyond reusing the same volume inputs.

## User Experience

On `/reports/inventory`, render a row of four summary cards directly below the filter panel and above the table panel.

Each card shows:

- the existing inventory column label
- the filtered total estimated volume in `m³`

The card values:

- always reflect the full filtered SKU result set
- do not change when the user moves between pages of the same filter result
- render as `0.0000 m³` when no qualifying rows contribute to that card

## Aggregation Rules

### Filter Scope

The summary uses the same SKU filter as the list table:

- when `params[:sku]` is blank, aggregate over the full inventory SKU scope
- when `params[:sku]` is present, aggregate over all matching SKUs

The summary must be computed before pagination is applied conceptually, even if pagination still controls which rows are rendered in the table.

### Per-SKU Contribution

Each SKU row already exposes:

- `incoming_quantity`
- `book_stock`
- `platform_stock`
- `available_stock`
- `unit_volume_l`

For each stock field, the per-SKU contribution is:

- `quantity * unit_volume_l / 1000`

Where:

- `unit_volume_l` is the single-SKU package volume in liters
- the final unit displayed by cards is cubic meters

### Exclusion Rules

Do not count a contribution when:

- `unit_volume_l` is blank
- `unit_volume_l <= 0`
- the resulting cubic-meter value is `<= 0`

This means:

- missing volume data does not contribute
- zero or negative volume overrides do not contribute
- negative stock quantities do not subtract from the total
- negative contributions are ignored rather than offsetting positive ones

### Override Behavior

`Ec::SkuCost#pkg_volume_l` remains the source of truth for unit volume:

- package dimensions take priority when all three dimensions exist
- `pkg_volume_override_l` is still used when dimensions are absent and override volume is positive

The summary should not duplicate this fallback logic in a second place.

## Implementation Shape

Keep the implementation in existing inventory page flow, with one small aggregation helper.

Recommended ownership:

- `ReportsController#inventory`
  - builds paginated `@inventory_rows` as today
  - builds new `@inventory_volume_summary` for the full filtered scope
- `ReportsController#fetch_inventory_row`
  - remains the source for page-facing row payload, including `unit_volume_l`
- helper/controller-private aggregation logic
  - derives per-field cubic-meter contributions from one row
  - accumulates totals for the four cards

Recommended shape for `@inventory_volume_summary`:

- `pending_stock_volume_m3`
- `book_available_stock_volume_m3`
- `platform_stock_volume_m3`
- `overseas_available_stock_volume_m3`

All values should be `BigDecimal`-safe through accumulation and formatted only at render time.

## Performance And Consistency

Use the existing row-building path rather than introducing a second SQL implementation for volume totals.

Rationale:

- it keeps card totals aligned with the same page-facing inventory row contract already used by the table
- it avoids copying inventory formulas into a second aggregation query
- it reuses the existing per-SKU row cache, including the new size and unit-volume payload

Because the page row cache shape has already changed once for volume metadata, the inventory row cache version should remain explicit so stale cached rows do not silently break the summary.

## View Changes

Update [app/views/reports/inventory.html.erb](/Users/jiyarong/Developer/5/eshop/app/views/reports/inventory.html.erb) to insert a summary-card section between the filter panel and the list table.

The cards should:

- reuse the existing report-card visual language where possible
- use Rails I18n for labels
- render values with four decimal places and `m³`

Example display:

- `12.3456 m³`

## I18n Changes

Add summary-specific text through locale files:

- `config/locales/zh.yml`
- `config/locales/en.yml`
- `config/locales/ru.yml`

Prefer reusing the existing stock field labels for card titles. Add only the minimum new keys required for section labeling or helper text if needed.

## Testing

Follow TDD with inventory-focused tests.

Required coverage:

- controller integration test proving summary cards render above the table
- controller integration test proving totals are based on the full filtered SKU set, not just the current page
- controller integration test proving missing volume, zero volume, and negative contributions are excluded
- helper or controller-private coverage proving contribution calculation ignores non-positive results if the logic becomes complex enough to deserve isolation

Suggested fixture shape for the pagination test:

- create more than 10 filtered SKUs
- give at least one SKU contributing volume that appears off the current page
- assert the card total still includes it

Suggested exclusion coverage:

- one SKU with valid positive contribution
- one SKU with no `Ec::SkuCost`
- one SKU with zero or negative `pkg_volume_override_l`
- one SKU with negative stock quantity in one of the relevant fields

## Risks And Guards

- Full filtered aggregation may touch more SKUs than the current page, so targeted tests should verify this does not accidentally regress pagination behavior.
- The summary must not drift from row-level volume logic; reusing the same row payload is the guard against formula mismatch.
- Existing unrelated failures in `test/controllers/reports_controller_test.rb` should be treated as pre-existing noise and reported separately from this change.
