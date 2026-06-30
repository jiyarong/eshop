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

## Testing

Add a direct service test for `Ec::SkuInventoryOverview` that covers:

- a normal batch plus a non-normal negative adjustment batch
- WB `fbw` and `fbs` orders both contributing to sales
- existing return logic continuing to add back returns
- supply records not affecting `book_stock` or `available_stock`

Controller tests are intentionally not part of this task because the current UI is expected to be replaced later and the requested scope is model/service only.
