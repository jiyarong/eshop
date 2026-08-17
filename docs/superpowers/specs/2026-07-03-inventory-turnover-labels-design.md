# Inventory Turnover And Label Alignment Design

## Summary

This change aligns inventory list/detail wording and adds a second turnover metric that includes procurement stock.

Affected surfaces:

- `GET /reports/inventory`
- `GET /reports/inventory/:sku_code`

The scope is limited to page-facing query objects, ERB rendering, I18n text, and test coverage for the new contract.

## Goals

- Replace the user-facing labels for current inventory metrics so list and detail views use the same wording.
- Add `周转天数(含采购)` beside the existing turnover days metric in both list and detail views.
- Keep the existing inventory summary formulas and data ownership stable.

## Non-Goals

- No changes to `Ec::SkuInventoryOverview` formulas for book/platform/FBS inventory.
- No changes to platform inventory aggregation rules.
- No changes to velocity calculation rules in `Ec::InventoryVelocityMetricsQuery`.
- No API or route changes.

## User-Facing Label Changes

The page text should be updated through Rails I18n only.

Inventory list and detail overview labels should become:

- `待入库库存` -> `采购中库存`
- `平台在库` -> `FBO/FBW在库`
- `境外当前可用` -> `FBS库存`

The existing `账面可用库存`, `日均销量`, and `周转天数` labels remain.

Add one new label:

- `周转天数(含采购)`

These label updates apply to:

- inventory list table headers
- inventory detail overview metric cards

## Data Contract

Existing internal field names remain unchanged unless a new field is required.

Existing fields:

- `incoming_quantity`
- `book_stock`
- `platform_stock`
- `available_stock`
- `daily_sales_velocity`
- `turnover_days`

New field:

- `turnover_days_with_procurement`

## Turnover Rules

Existing turnover remains unchanged:

- `turnover_days = book_stock / daily_sales_velocity`

New procurement-inclusive turnover:

- `turnover_days_with_procurement = (book_stock + procurement_stock) / daily_sales_velocity`

Where:

- `procurement_stock` means only normal purchase batches
- `procurement_stock` ignores adjustment batches entirely
- `procurement_stock` includes only procurement-stage statuses already counted by page-level incoming quantity logic

For this page, procurement-stage statuses are:

- `draft`
- `ordered`
- `in_transit`

Batch filtering rules:

- include `Ec::SkuBatch` rows with `batch_type = :normal`
- exclude non-normal adjustment batch types even if they are in a procurement-stage status

Nil behavior:

- if `daily_sales_velocity` is blank or non-positive, both turnover values render as `-`

## Implementation Shape

Keep the logic inside existing page-facing query objects:

- `Ec::InventoryPageRowQuery`
- `Ec::InventoryPageDetailQuery`

Recommended responsibilities:

- `InventoryPageRowQuery` exposes `incoming_quantity` and the new `turnover_days_with_procurement`
- `InventoryPageDetailQuery` exposes the same new field for the detail overview payload
- `ReportsController#fetch_inventory_row` continues merging velocity-dependent values for list rows

The implementation should avoid moving this calculation into `Ec::SkuInventoryOverview`, because the new metric depends on velocity data that is specific to report rendering rather than inventory summary ownership.

## View Changes

### Inventory List

Update [app/views/reports/inventory.html.erb](/Users/jiyarong/Developer/5/eshop/app/views/reports/inventory.html.erb) to:

- replace the three labels with their new wording
- add a new column immediately to the right of `周转天数`
- render the new value with the same decimal formatting as the existing turnover days column
- keep the current fallback of `-` when no value is available

### Inventory Detail

Update [app/views/reports/_inventory_drawer_content.html.erb](/Users/jiyarong/Developer/5/eshop/app/views/reports/_inventory_drawer_content.html.erb) to:

- replace the three overview labels with their new wording
- add a new overview metric card for `周转天数(含采购)`
- render the new value with the same decimal formatting and fallback as the existing turnover card

## I18n Changes

Update locale entries in:

- `config/locales/zh.yml`
- `config/locales/en.yml`
- `config/locales/ru.yml`

Only change user-facing translations. Keep key names stable where possible and add one new key for `turnover_days_with_procurement`.

## Testing

Follow TDD:

- add/adjust service tests for `InventoryPageRowQuery`
- add/adjust service tests for `InventoryPageDetailQuery`
- add/adjust controller integration tests for the inventory list/detail rendering contract

Required assertions:

- procurement-inclusive turnover uses only normal procurement batches
- adjustment batches do not affect procurement-inclusive turnover
- list page renders the renamed headers
- list page renders the new turnover column
- detail overview renders the renamed labels
- detail overview renders the new turnover card

## Risks And Guards

- Current tests in `test/controllers/reports_controller_test.rb` already have unrelated failures; targeted test execution should be used while implementing this change.
- The list page currently derives turnover in the controller after row query execution. The new metric should follow one clear ownership path so the list and detail stay consistent.
- Since labels are reused in multiple locales, assertions should reference I18n keys instead of hard-coded text where practical.
