# Weekly Summary Deep Design

## Goal

Add a second weekly profit summary sheet that follows the existing `WSU:` weekly-summary logic but aggregates data one level deeper:

- one row per `SKU`
- merged across all platforms and shops
- includes four additional derived columns

The new Google Sheet tab name format is:

`WSU-DEEP:W{n}`

## Scope

In scope:

- create a new weekly summary writer for `WSU-DEEP`
- reuse the existing weekly profit attribution logic and CNY normalization rules
- aggregate rows by `SKU` only
- add new derived columns for unit economics and ROI
- preserve weekly previous-period comparison columns

Out of scope:

- changing the current `WSU:` tab layout or logic
- replacing the current `WeeklySummaryService`
- changing `WR:` / `WOD:` generation
- making storage fee or interest rate configurable in this version

## Data Grain

`WSU-DEEP` uses one row per internal `SKU`.

For one SKU row:

- WB and Ozon rows are merged
- all shops are merged
- no separate platform or shop columns remain in the main table

This is a deeper aggregation than `WSU:`, which currently keeps `SKU + platform + shop` as separate rows.

## Source Logic

The source logic should follow the current `GoogleSheets::WeeklySummaryService` data collection rules:

- WB data comes from `Ec::WbProfitAttribution`
- Ozon data comes from `Ec::OzonProfitAttribution`
- all amounts are normalized to `CNY`
- the same net-sales, revenue, ads, goods-cost, pre-tax, tax, and after-tax fields are reused

The recommended design is:

- keep `GoogleSheets::WeeklySummaryService` behavior stable
- add a new `GoogleSheets::WeeklySummaryDeepService`
- optionally extract a shared row-collection helper if duplication becomes excessive

## Row Aggregation

For each internal `SKU`, aggregate:

- `net_sales`
- `revenue`
- `ads`
- `goods_cost`
- `pre_tax`
- `tax`
- `after_tax`

The previous-week lookup should also be keyed by `SKU` only in this deep version.

## Output Columns

Each `WSU-DEEP` main table row should include at least:

- `SKU`
- `净销量`
- `销售额(CNY)`
- `广告费(CNY)`
- `货物成本(CNY)`
- `税前毛利(CNY)`
- `税/营业税(CNY)`
- `税后净利(CNY)`
- `利润率%`
- `平均每单利润`
- `广告占比`
- `成本回报率`
- `ROI(180天备货)`
- `上周净销量`
- `上周销售额(CNY)`
- `销量环比%`
- `销售额环比%`

The exact bilingual headers can follow the same style as the current `WSU:` sheet.

## Derived Metrics

### 1. 平均每单利润

`average_profit_per_unit = after_tax / net_sales`

Return blank when `net_sales <= 0`.

### 2. 广告占比

`ad_ratio = ads / revenue`

Return blank when `revenue <= 0`.

### 3. 成本回报率

`cost_return_ratio = after_tax / goods_cost`

Return blank when `goods_cost <= 0`.

### 4. ROI(180天备货)

This ROI should use the same holding-cost model as the new SKU ROI logic, but with the weekly summary row's aggregated metrics.

Use:

- numerator base: `after_tax`
- projected stock horizon: `180 days`
- fixed storage fee: `100 CNY / m³ / month`
- fixed capital interest: `1% / month`

Formula:

```text
days_count = (to_date - from_date).to_i + 1
average_daily_net_sales = net_sales / days_count
projected_stock_qty_180d = average_daily_net_sales * 180
average_inventory_qty = projected_stock_qty_180d / 2
projected_months_to_clear = (projected_stock_qty_180d / (average_daily_net_sales * 7)) / 4.33
unit_goods_cost_cny = Ec::SkuCost#goods_cost_cny
unit_volume_l = Ec::SkuCost#pkg_volume_l
unit_volume_m3 = unit_volume_l / 1000

predicted_storage_cost_cny =
average_inventory_qty * projected_months_to_clear * unit_volume_m3 * 100

predicted_interest_cost_cny =
average_inventory_qty * projected_months_to_clear * unit_goods_cost_cny * 0.01

roi_180d =
(after_tax - predicted_storage_cost_cny - predicted_interest_cost_cny)
/
(projected_stock_qty_180d * unit_goods_cost_cny)
```

## Cost And Volume Source

For each SKU:

- cost source: `Ec::SkuCost#goods_cost_cny`
- volume source: `Ec::SkuCost#pkg_volume_l`

`pkg_volume_l` already follows the preferred fallback chain:

- package dimensions first
- `pkg_volume_override_l` only when dimensions are unavailable

No batch-based cost allocation is part of this design.

## Edge Cases

Return blank for derived columns when the denominator is unusable.

For `ROI(180天备货)`, return blank when any of the following is true:

- `net_sales <= 0`
- `days_count <= 0`
- `goods_cost_cny.blank?`
- `goods_cost_cny <= 0`
- `pkg_volume_l.blank?`
- `pkg_volume_l <= 0`

These blank results should not prevent the row from being written.

## Summary Section

`WSU-DEEP` can keep a summary area similar to `WSU:`, but it should be SKU-aggregated.

At minimum it should keep:

- data period
- exchange rates used
- total revenue
- total after-tax profit
- blended margin
- unallocated cost summary if reused from the current logic

The exact vertical summary layout can match the current sheet style.

## Service Design

Recommended file:

- `app/services/google_sheets/weekly_summary_deep_service.rb`

Recommended responsibilities:

- collect normalized weekly rows
- aggregate by `SKU`
- build previous-week map by `SKU`
- compute derived columns
- write `WSU-DEEP:W{n}`

Avoid overloading the current `WeeklySummaryService` with mode flags unless the implementation stays clearly separated.

## Testing

Add service tests covering:

- multiple rows for the same SKU across different platforms and shops merge into one row
- previous-week comparison fields still work after SKU-level aggregation
- `average_profit_per_unit`, `ad_ratio`, and `cost_return_ratio` compute correctly
- `ROI(180天备货)` computes correctly with valid cost and volume
- `ROI(180天备货)` is blank when cost is missing
- `ROI(180天备货)` is blank when volume is missing
- the existing `WSU:` service remains unchanged
