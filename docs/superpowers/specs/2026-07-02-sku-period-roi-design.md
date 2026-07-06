# SKU Period ROI Design

## Goal

Add a reusable service that calculates ROI for a single SKU within a user-selected time window.

This ROI is not based on sold-unit cost in the same window and not based on actual SKU batch records. It uses the window's operating profit together with a projected 180-day stocking cost base derived from the same window's average daily net sales, then subtracts predicted holding costs for storage and capital interest using the same style as the original ROI HTML calculator.

## Scope

In scope:

- define one query-style service for `sku_code + from_date + to_date + time_zone`
- reuse existing WB and Ozon profit-attribution services
- return total ROI and per-platform breakdown
- use current standard SKU goods cost as the unit cost source
- add direct service tests for the new query service

Out of scope:

- ERB page changes
- controller wiring
- API response changes outside the new service
- using `ec_sku_batches` as the ROI cost base
- introducing a new cost source beyond the current standard SKU cost table

## Metric Definition

The metric is defined as:

`period_roi = adjusted_operating_net_profit / projected_180d_cost_base`

Where:

- `operating_net_profit = revenue - commission - logistics - storage - ads - goods_cost`
- `net_sales_quantity = sales_quantity - return_quantity`
- `days_count = (to_date - from_date).to_i + 1`
- `average_daily_net_sales = net_sales_quantity / days_count`
- `projected_stock_qty_180d = average_daily_net_sales * 180`
- `average_inventory_qty = projected_stock_qty_180d / 2`
- `projected_weeks_to_clear = projected_stock_qty_180d / (average_daily_net_sales * 7)`
- `projected_months_to_clear = projected_weeks_to_clear / 4.33`
- `unit_volume_m3 = unit_volume_l / 1000`
- `predicted_storage_cost = average_inventory_qty * projected_months_to_clear * unit_volume_m3 * 100`
- `predicted_interest_cost = average_inventory_qty * projected_months_to_clear * unit_goods_cost_cny * 0.01`
- `adjusted_operating_net_profit = operating_net_profit - predicted_storage_cost - predicted_interest_cost`
- `projected_180d_cost_base = projected_stock_qty_180d * unit_goods_cost_cny`

The total ROI is recomputed from total raw inputs:

- `total_operating_net_profit = wb_operating_net_profit + ozon_operating_net_profit`
- `total_net_sales_quantity = wb_net_sales_quantity + ozon_net_sales_quantity`
- `total_adjusted_operating_net_profit = total_operating_net_profit - total_predicted_storage_cost - total_predicted_interest_cost`
- `total_roi = total_adjusted_operating_net_profit / ((total_net_sales_quantity / days_count) * 180 * unit_goods_cost_cny)`

`total_roi` must not be calculated by averaging `wb` ROI and `ozon` ROI.

## Attribution Rules

SKU attribution must follow the project's existing `ec_sku_products` binding rules only.

Do not use `ec_order_items.sku_code` as a fallback attribution key.

The time window must use the current user time zone for day boundaries so that report date filters match rendered dates.

## Cost Source

The unit cost and package volume source is the current standard SKU cost record.

The first implementation uses one shared unit goods cost for the SKU across all platforms:

- `unit_goods_cost_cny` comes from the existing standard SKU cost table
- `unit_volume_l` comes from `Ec::SkuCost#pkg_volume_l`
- `wb` and `ozon` platform ROI both use that same unit cost
- `total` ROI also uses that same unit cost

No batch-level or FIFO-style costing is part of this design.

Holding-cost constants are fixed in this first version:

- storage fee: `100 CNY / m³ / month`
- capital interest: `1% / month`

## Service Design

The public entry point should be:

`Ec::SkuPeriodRoiQuery`

Suggested interface:

```ruby
Ec::SkuPeriodRoiQuery.new(
  sku_code:,
  from_date:,
  to_date:,
  time_zone:
).call
```

Supporting services:

- `Ec::SkuPeriodRoiQuery`
  - orchestrates loading, aggregation, and final response shape
- `Ec::SkuPeriodProfitBreakdown`
  - collects per-platform sales, returns, net sales, and operating profit
- `Ec::RoiCalculator`
  - remains a formula-only utility and should be reused for the final ratio calculation where practical

This keeps business data gathering separate from formula evaluation.

## Data Sources

### WB

Use `Ec::WbProfitAttribution` as the source of per-SKU WB values.

For ROI input fields, use the WB result fields that already expose:

- `sales_qty`
- `return_qty`
- `net_qty`
- the profit-chain layer corresponding to operating profit, not tax-adjusted profit

### Ozon

Use `Ec::OzonProfitAttribution` as the source of per-SKU Ozon values.

For ROI input fields, use the Ozon result fields that already expose:

- `order_count`
- `return_count`
- `net_sales_count`
- the profit-chain layer corresponding to operating profit, including ads and goods cost but excluding tax

### Standard Cost

Use the current SKU standard goods-cost record for:

- `unit_goods_cost_cny`
- `unit_volume_l` via `pkg_volume_l`

If there is no usable standard cost record, the result is non-calculable.

## Result Shape

Return a structured payload with both raw inputs and final ROI values.

Suggested shape:

```ruby
{
  sku_code: "SKU-123",
  from_date: Date,
  to_date: Date,
  days_count: 30,
  unit_goods_cost_cny: 35.5,
  unit_volume_l: 4.2,
  roi_formula: "adjusted_operating_net_profit / (projected_stock_qty_180d * unit_goods_cost_cny)",
  total: {
    sales_quantity: 120,
    return_quantity: 8,
    net_sales_quantity: 112,
    average_daily_net_sales: 3.7333,
    projected_stock_qty_180d: 672.0,
    average_inventory_qty: 336.0,
    projected_months_to_clear: 5.93,
    predicted_storage_cost_cny: 83.72,
    predicted_interest_cost_cny: 749.31,
    cost_base_cny: 23856.0,
    operating_net_profit_cny: 4200.0,
    adjusted_operating_net_profit_cny: 3366.97,
    roi: 0.1411
  },
  platforms: {
    wb: {
      sales_quantity: 70,
      return_quantity: 5,
      net_sales_quantity: 65,
      average_daily_net_sales: 2.1667,
      projected_stock_qty_180d: 390.0,
      average_inventory_qty: 195.0,
      projected_months_to_clear: 5.93,
      predicted_storage_cost_cny: 48.55,
      predicted_interest_cost_cny: 434.41,
      cost_base_cny: 13845.0,
      operating_net_profit_cny: 2600.0,
      adjusted_operating_net_profit_cny: 2117.04,
      roi: 0.1529
    },
    ozon: {
      sales_quantity: 50,
      return_quantity: 3,
      net_sales_quantity: 47,
      average_daily_net_sales: 1.5667,
      projected_stock_qty_180d: 282.0,
      average_inventory_qty: 141.0,
      projected_months_to_clear: 5.93,
      predicted_storage_cost_cny: 35.17,
      predicted_interest_cost_cny: 314.90,
      cost_base_cny: 10011.0,
      operating_net_profit_cny: 1600.0,
      adjusted_operating_net_profit_cny: 1249.93,
      roi: 0.1249
    }
  },
  calculable: true,
  missing_cost: false
}
```

Platform results should be calculated independently. The total result should be recomputed from total raw metrics rather than derived from platform ROI averaging.

## Edge Cases

Return `roi: nil` when any of the following blocks calculation:

- `days_count <= 0`
- `net_sales_quantity <= 0`
- `unit_goods_cost_cny.blank?`
- `unit_goods_cost_cny <= 0`
- `unit_volume_l.blank?` only if all package-dimension paths are unavailable and `pkg_volume_l` resolves to unusable data

Additional rules:

- if one platform has no data in the window, treat that platform as zeroed rather than erroring
- if a platform has profit rows but zero net sales, keep the raw fields and return that platform's `roi: nil`
- set `missing_cost: true` when the SKU standard cost record is missing or unusable
- set `missing_volume: true` when no usable package volume can be derived
- set `calculable: false` whenever the total ROI cannot be computed

## Testing

Add direct service tests for:

- WB-only SKU window ROI
- Ozon-only SKU window ROI
- cross-platform aggregation with total ROI recalculated from total raw metrics
- projected storage cost and projected interest cost using fixed constants and `pkg_volume_l`
- zero or negative total net sales returning `roi: nil`
- missing standard cost returning `roi: nil` with `missing_cost: true`
- missing package volume returning `roi: nil` with `missing_volume: true`
- SKU attribution continuing to rely on `ec_sku_products` bindings rather than `ec_order_items.sku_code`

Controller and UI tests are out of scope until a consumer of the new service is introduced.
