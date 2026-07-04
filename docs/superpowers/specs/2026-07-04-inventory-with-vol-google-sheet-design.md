# Inventory With Vol Google Sheet Design

## Summary

Add a repeatable Google Sheets export for the current inventory report list into a new tab named `Inventory With Vol`.

The export should:

- write into the existing project spreadsheet
- use a bilingual two-row header, matching the established Google Sheets pattern in this codebase
- export only the inventory list table rows, not the top summary cards
- include the current inventory report list columns plus flattened dimension and volume columns
- reuse the same row-calculation path as the inventory report page instead of introducing a second inventory calculation implementation

## Goals

- Create a service that can fully refresh the `Inventory With Vol` tab on demand.
- Keep exported row values aligned with the current `/reports/inventory` list behavior.
- Include package dimensions and unit volume fields that are already available in the inventory list row payload.
- Make the export easy to rerun in production without manual spreadsheet editing.

## Non-Goals

- Do not export the four inventory volume summary cards into this tab.
- Do not add new inventory business rules or a second standalone SQL/reporting path.
- Do not change the inventory page request behavior.
- Do not introduce a new external spreadsheet integration.

## Existing Context

Current relevant pieces:

- Google Sheets write infrastructure lives in `GoogleSheets::BaseService`.
- Existing tab-oriented exports follow the pattern used by `GoogleSheets::SkuSheetService`.
- Inventory list row data already comes from:
  - `Ec::InventoryPageRowQuery`
  - `Ec::InventoryVelocityMetricsQuery`
- The inventory page view currently displays:
  - SKU
  - product name
  - incoming/book/platform/available quantities
  - daily sales velocity
  - turnover days
  - turnover days with procurement
  - dimensions subline
  - per-cell volume sublines

The export should stay aligned with this existing page contract rather than re-deriving values with new query logic.

## Export Shape

### Tab

- Spreadsheet tab name: `Inventory With Vol`
- Service behavior: ensure the tab exists, clear prior content, then rewrite the full dataset

### Header Format

Use two header rows:

- row 1: Chinese labels
- row 2: Russian labels

Header styling should follow the same general pattern as existing Google Sheets export services:

- colored header rows
- frozen header rows
- explicit column widths
- typed numeric formatting for quantities, dimensions, velocities, turnover values, and volumes

### Exported Columns

The export will flatten the current inventory page list into dedicated columns:

1. `SKU`
2. `商品名(中文)`
3. `商品名(俄文)`
4. `采购中库存`
5. `采购中库存体积(m³)`
6. `账面可用库存`
7. `账面可用库存体积(m³)`
8. `FBO/FBW在库`
9. `FBO/FBW在库体积(m³)`
10. `FBS库存`
11. `FBS库存体积(m³)`
12. `日均销量`
13. `周转天数`
14. `周转天数(含采购)`
15. `长(cm)`
16. `宽(cm)`
17. `高(cm)`
18. `单件体积(L)`

Russian labels should be added for the same set of columns in row 2.

## Data Contract

Each exported row should be built from the same payload shape the inventory page relies on.

Required source fields:

- `sku_code`
- `product_name`
- `product_name_ru`
- `incoming_quantity`
- `book_stock`
- `platform_stock`
- `available_stock`
- `daily_sales_velocity`
- `turnover_days`
- `turnover_days_with_procurement`
- `pkg_length_cm`
- `pkg_width_cm`
- `pkg_height_cm`
- `unit_volume_l`

Derived export-only fields:

- `incoming_volume_m3 = incoming_quantity * unit_volume_l / 1000`
- `book_volume_m3 = book_stock * unit_volume_l / 1000`
- `platform_volume_m3 = platform_stock * unit_volume_l / 1000`
- `available_volume_m3 = available_stock * unit_volume_l / 1000`

Nil/blank handling:

- textual blanks export as empty string
- missing numeric values export as blank
- volume cells export as blank when `unit_volume_l` is blank or non-positive

## Implementation Shape

Create a new service:

- `GoogleSheets::InventoryWithVolSheetService`

Responsibilities:

- enumerate all SKUs in `sku_code` order
- precompute velocity metrics in batches where practical
- build export rows using the same inventory row query path used by the report page
- write bilingual headers and all rows into `Inventory With Vol`
- apply basic tab formatting via `GoogleSheets::BaseService`

Recommended internal structure:

- `call`
- `build_rows`
- `build_row_for_sku`
- `estimated_volume_m3`
- `apply_styles`

## Reuse Rules

The export must not introduce a second inventory calculation algorithm.

Specifically:

- inventory quantities must come from `Ec::InventoryPageRowQuery`
- velocity and turnover values must come from `Ec::InventoryVelocityMetricsQuery`
- dimensions and unit volume must come from the same row payload already used by the inventory page

If controller-specific code is currently the only place composing some values, extract the minimum shared logic into a reusable service/helper method rather than duplicating calculations inside the Google Sheets export.

## Execution Entry Point

Provide a repeatable entry point suitable for production reruns.

Preferred options:

- service class with `call`
- optional rake task that invokes the service

The implementation should make it straightforward to execute once on production after deploy, then rerun later as needed.

## Testing

Add focused service tests that stub Google Sheets side effects.

Required coverage:

- writes to tab `Inventory With Vol`
- writes bilingual two-row headers
- exports the expected flattened columns
- includes dimensions and unit volume values
- computes per-column cubic-meter values correctly
- keeps blank volume cells blank when unit volume is unavailable

Tests should stub or intercept:

- `ensure_sheet_exists`
- `clear_sheet`
- `write_to_sheet`
- `sheet_id`
- `batch_update`

The tests should validate row content and the expected sheet range without calling the real Google Sheets API.

## Risks And Mitigations

### Full-table export cost

Risk:

- exporting every SKU can be heavier than the paginated page

Mitigation:

- batch velocity lookups
- keep the row builder shared and simple
- leave the export as an explicit rerun operation, not a page request side effect

### Drift from page behavior

Risk:

- export values can diverge from `/reports/inventory`

Mitigation:

- reuse the same row query and velocity metrics path
- avoid hand-written duplicate SQL or formulas for inventory quantities and turnover values

### Spreadsheet readability

Risk:

- flattened volume columns can make the tab wide

Mitigation:

- set explicit column widths
- keep the sheet to only the requested list columns and volume/dimension data
- freeze the two header rows

## Acceptance Criteria

The work is complete when:

- a new Google Sheets service can fully refresh `Inventory With Vol`
- the tab is populated with all inventory list rows in SKU order
- the export contains dimensions and unit volume columns
- the export contains per-stock-column cubic-meter values
- the export uses two bilingual header rows
- automated tests cover row mapping and sheet writing behavior
