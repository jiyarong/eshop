# Inventory Book Stock Adjustment Design

## Goal

Update the inventory book-stock logic so that:

- batch receipts are split into `purchase_quantity` and `adjustment_quantity`
- `received_quantity` remains the combined total of both
- WB sales use all non-cancelled WB orders, not only FBS orders
- `supply_quantity` no longer participates in any inventory quantity calculation

This change is intentionally limited to the model/service layer, the inventory debug script, and the reference document. Existing controllers and views are out of scope for now.

## Scope

In scope:

- update `Ec::SkuInventoryOverview`
- update `script/20260618_check_inventory.rb`
- update `docs/库存计算260615.md`
- add direct service-layer tests for `Ec::SkuInventoryOverview`

Out of scope:

- `ReportsController`
- ERB/UI output changes
- renaming current UI labels or adding new UI fields
- broader refactors that extract a shared inventory calculator

## Inventory Definitions

For batches with `status IN ('received', 'closed')`:

- `purchase_quantity` = `SUM(received_quantity)` where `batch_type = normal`
- `adjustment_quantity` = `SUM(received_quantity)` where `batch_type != normal`
- `received_quantity` = `purchase_quantity + adjustment_quantity`

`adjustment_quantity` is expected to often be negative because non-normal batches represent offset or correction entries.

## Book Stock Formula

The new book-stock formula is:

`book_stock = received_quantity - sales_quantity + return_quantity`

Where:

- `sales_quantity` includes all non-cancelled orders linked to the SKU through `ec_sku_products`
- `return_quantity` keeps the existing raw return-table logic
- `supply_quantity` is excluded from book-stock and available-stock calculations for every platform

`available_stock` remains:

`available_stock = book_stock - platform_stock`

## WB Sales Rule

WB sales should count all non-cancelled WB orders linked by `ec_sku_products`, regardless of fulfillment type.

This means:

- `fbs` orders count
- `fbw` orders count
- the fulfillment type split may still exist as a descriptive dimension elsewhere, but it must not change inventory totals

## Service Design

`Ec::SkuInventoryOverview` will:

- compute `purchase_quantity`, `adjustment_quantity`, and `received_quantity` from `Ec::SkuBatch`
- continue using SKU-product binding for order attribution
- keep return aggregation logic unchanged
- stop subtracting WB or Ozon supply quantities from `book_stock`
- stop subtracting WB or Ozon supply quantities from `available_stock`

If `supply_quantity` is still returned in store rows for compatibility, it becomes informational only and must not feed summary calculations.

## Script Design

`script/20260618_check_inventory.rb` will:

- split batch totals into purchase, adjustment, and received totals
- remove WB FBW supply from the book-stock computation
- switch WB sales from `fbs` only to all non-cancelled WB orders linked to the SKU
- keep the current return logic unless a later requirement changes it

The script output should explicitly show:

- `采购数量`
- `补正调整数量`
- `总入库`
- `WB 销售`
- `WB 退货`
- `Ozon 销售`
- `Ozon 退货`
- `净销售`
- `账面库存`

## Documentation Design

`docs/库存计算260615.md` will be updated so the narrative, formulas, and Ruby example all match the new rules:

- total received is split into purchase and adjustment components
- WB sales use all orders
- WB FBW supply is removed from inventory quantity formulas
- `supply_quantity` is explicitly documented as excluded from inventory quantity calculations

## Future UI Data Contract

The latest design draft in `docs/design/releases/1.0.11-current/ui_kits/admin/screens/SkuInventory.jsx` is still mock-driven, but it is useful as a contract sketch for the eventual Rails page.

The future page needs three layers of data:

### 1. SKU list rows

Each row needs at least:

- `sku_code`
- localized or source product name
- `incoming_quantity`
- `book_inventory_quantity`
- `platform_inventory_quantity`
- `overseas_available_quantity`
- enough data to determine whether the row should be visually flagged as low stock

### 2. SKU detail overview summary

The drawer-style detail view expects a compact summary with:

- `incoming_quantity`
- `book_inventory_quantity`
- `platform_inventory_quantity`
- `overseas_available_quantity`

These are presentation-level aggregates and should come from real backend calculations, not be reverse-derived from mock layout data.

### 3. SKU detail tab payloads

The design implies three tab payloads:

- `incoming_batches`
  - batch identifier or label
  - expected arrival or equivalent date
  - quantity

- `book_inventory`
  - mini summary values:
    - `purchase_quantity`
    - platform-level sales and return figures needed to explain `book_inventory_quantity`
  - batch rows:
    - batch label
    - batch type
    - adjustment note
    - signed quantity
  - order distribution rows:
    - platform
    - store label
    - counts by order-status bucket
  - return distribution rows:
    - platform
    - store label
    - return quantity
  - formula inputs:
    - received total
    - platform sales totals
    - platform return totals
    - adjustment totals grouped by batch type

- `platform_inventory`
  - platform summary buckets
  - shop rows split by fulfillment bucket
  - formula inputs:
    - `book_inventory_quantity`
    - total platform inventory
    - `overseas_available_quantity`

## Mock-Only Assumptions To Reject

The current design file contains several placeholders that should not be treated as backend truth:

- order distribution is artificially derived from `sales30d` and fixed weights
- return counts are artificially derived from fixed return rates
- `bookInventoryTotal` in the mock is not computed from the real inventory formula
- platform bucket naming in the mock is inconsistent with the current business vocabulary
- the mock uses `untrackable_defect`, while the current model enum is `untrackable_defective`

When the real page is implemented later, the backend must provide actual counts and formulas from database and platform-derived data instead of reproducing these mock approximations.

## Testing

Add a direct service test for `Ec::SkuInventoryOverview` that covers:

- a normal batch plus a non-normal negative adjustment batch
- WB `fbw` and `fbs` orders both contributing to sales
- existing return logic continuing to add back returns
- supply records not affecting `book_stock` or `available_stock`

Controller tests are intentionally not part of this task because the current UI is expected to be replaced later and the requested scope is model/service only.
