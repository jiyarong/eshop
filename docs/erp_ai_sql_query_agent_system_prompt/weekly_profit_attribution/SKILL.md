# Weekly Profit Attribution API Skill

用于回答周利润归集、WR、WSU、WSU-DEEP、周利润报表、利润归集报告、平台财务流水归因和未归集金额排查相关问题。

## 核心规则

周利润归集不是单表查询结果。WR、WSU、WSU-DEEP 的核心逻辑统一在系统业务 API 中维护，必须优先调用：

```http
POST /ai/weekly_profit_reports.json
Authorization: Bearer <user_api_key>
Content-Type: application/json
```

如果当前环境提供 MCP 内部转发工具，使用 `erp_ai_request` 调用本应用 API：

```json
{
  "method": "post",
  "url": "/ai/weekly_profit_reports.json",
  "params": {
    "report_type": "wsu",
    "from_date": "2026-05-18",
    "to_date": "2026-05-24",
    "sku_codes": ["SKU001"]
  },
  "headers": {
    "Accept": "application/json"
  }
}
```

不要手动拼 SQL 复刻 WR、WSU、WSU-DEEP 的计算逻辑。只有在用户明确要求排查某个中间数据缺口、账号绑定、SKU 绑定、原始财务流水或周汇率时，才使用 SQL 查询相关基础表。

## 命中关键字

用户问题包含以下关键词或语义时，优先调用 `/ai/weekly_profit_reports.json`：

- `WR`、`WSU`、`WSU-DEEP`、`WSU_DEEP`。
- 周利润、周利润报表、利润归集、归集报告、周报利润。
- 单店铺周利润、单平台周利润、跨平台周利润、SKU 周利润。
- 税后利润、税前利润、广告费、货物成本、未归集金额，且上下文是自然周利润归集。
- ROI、投产、年化、平均每单利润，且上下文是 WSU-DEEP。

## 请求参数

### 通用参数

- `report_type`：必填。可选值：
  - `wr`：单平台账号周利润明细。
  - `wsu`：跨平台、跨店铺，按 `SKU + platform + shop` 汇总。
  - `wsu_deep`：跨平台、跨店铺，按 SKU 聚合并补充 ROI、年化等深度指标。
- `from_date`：必填，自然周周一，格式 `YYYY-MM-DD`。
- `to_date`：必填，自然周周日，格式 `YYYY-MM-DD`。
- `sku_codes`：可选，数组，内部 SKU code。支持多选。
- `master_sku_ids`：可选，数组，内部 SPU / master SKU ID。API 会展开为其子 SKU。
- `sku`：兼容旧入口的逗号分隔 SKU 字符串。新请求优先使用 `sku_codes`。

周期必须是完整自然周：

- 开始日必须是周一。
- 结束日必须是周日。
- 当前未结束自然周不作为已完成周报口径。
- 如果用户给的是“最近 7 天”、周三到下周二等非自然周范围，先询问是否调整为自然周口径。

### WR 参数

WR 额外必填：

- `store_ref`：平台账号引用。
  - WB：`wb:<raw_wb_seller_accounts.id>`。
  - Ozon：`ozon:<raw_ozon_seller_accounts.id>`。

如果用户只给店铺名，先用只读 SQL 查询启用账号 ID，再调用 API。

WB 账号查询示例：

```sql
SELECT id, name
FROM raw_wb_seller_accounts
WHERE is_active = true
  AND name ILIKE '%店铺关键词%'
ORDER BY id
```

Ozon 账号查询示例：

```sql
SELECT id, company_name
FROM raw_ozon_seller_accounts
WHERE is_active = true
  AND company_name ILIKE '%店铺关键词%'
ORDER BY id
```

不要查询账号凭据字段，例如 `api_token`、`api_key`、`client_id`、`performance_client_secret`。

## 请求示例

### WR：单店铺周利润

```json
{
  "report_type": "wr",
  "store_ref": "wb:2",
  "from_date": "2026-07-06",
  "to_date": "2026-07-12"
}
```

### WR：单店铺 + SKU 筛选

```json
{
  "report_type": "wr",
  "store_ref": "ozon:1",
  "from_date": "2026-07-06",
  "to_date": "2026-07-12",
  "sku_codes": ["KJ-217-GD", "KJ-228"]
}
```

### WSU：跨平台店铺汇总

```json
{
  "report_type": "wsu",
  "from_date": "2026-07-06",
  "to_date": "2026-07-12"
}
```

### WSU-DEEP：按 SKU 深度利润

```json
{
  "report_type": "wsu_deep",
  "from_date": "2026-07-06",
  "to_date": "2026-07-12",
  "sku_codes": ["KJ-217-GD"]
}
```

## 返回结构

成功响应：

```json
{
  "success": true,
  "data": {
    "report_type": "wsu",
    "period": {
      "from_date": "2026-07-06",
      "to_date": "2026-07-12"
    },
    "comparison": {},
    "meta": {},
    "summary": {},
    "rows": [],
    "extras": {}
  },
  "message": "ok"
}
```

错误响应：

```json
{
  "success": false,
  "message": "错误说明"
}
```

常见错误：

- 缺少 `store_ref`：WR 必须指定平台账号。
- `invalid_week_range`：日期范围不是完整自然周。
- `current_week_unsupported`：请求了当前未结束自然周。
- `missing_weekly_rate`：该周缺少 `ec_weekly_rates`。
- `invalid_store_ref` 或店铺不存在：`store_ref` 格式错误、账号不存在或未启用。

## WR 返回字段

WR 是单账号周利润，`meta.platform` 决定字段。

### WB WR

币种：BYN。

行字段：

- `nm_id`、`vendor_code`、`region`。
- `sales_qty`、`return_qty`、`net_qty`。
- `settlement`、`delivery`、`storage`、`ad`、`goods_cost`。
- `pre_tax`、`tax`、`after_tax`。

汇总字段：

- `total_sales_qty`、`total_return_qty`、`total_net`。
- `total_goods_cost`、`total_pre_tax`、`total_tax`、`total_after_tax`。
- `unallocated_rows`。

### Ozon WR

币种：RUB。

行字段：

- `ozon_sku_id`、`sku_code`。
- `sales_revenue`、`commission`、`delivery_charge`。
- `ppc_cost`、`promotion_cost`、`total_ad_cost`。
- `order_count`、`return_count`、`net_sales_count`、`blr_count`、`export_count`。
- `goods_cost`、`pre_tax_profit`、`after_tax_profit`、`after_tax_margin_pct`。

汇总字段：

- `sku_count`、`total_sales_revenue`、`total_orders`、`total_returns`。
- `total_ad`、`total_goods_cost`、`total_after_tax_profit`。
- `unallocated_total`。

## WSU 返回字段

WSU 是跨平台、跨店铺、按 `SKU + platform + shop` 的 CNY 汇总。

行字段：

- `sku`、`platform`、`shop`。
- `net_sales`、`revenue`、`ads`、`goods_cost`。
- `pre_tax`、`tax`、`after_tax`、`margin_pct`。

汇总字段：

- `total_sales_revenue`、`total_after_tax`、`total_margin_pct`。
- `wb_sales_revenue`、`wb_ads`、`wb_goods_cost`、`wb_pre_tax`、`wb_after_tax`。
- `ozon_sales_revenue`、`ozon_ads`、`ozon_goods_cost`、`ozon_pre_tax`、`ozon_after_tax`。
- `wb_unallocated`、`ozon_unallocated`、`unallocated_total`。
- `after_tax_with_unallocated`、`margin_with_unallocated_pct`。

## WSU-DEEP 返回字段

WSU-DEEP 是跨平台、跨店铺、按 SKU 聚合的 CNY 深度利润。

行字段：

- `sku`。
- `net_sales`、`revenue`、`ads`、`goods_cost`。
- `pre_tax`、`tax`、`after_tax`、`margin_pct`。
- `average_profit_per_order`、`ad_ratio_pct`、`cost_return_pct`。
- `projected_roi_pct`、`annualized_return_pct`、`annualized_net_profit_cny`。

汇总字段：

- `total_sku_count`、`total_net_sales`。
- `total_sales_revenue`、`total_ads`、`total_goods_cost`。
- `total_pre_tax`、`total_after_tax`、`total_margin_pct`。
- `unallocated_total`、`after_tax_with_unallocated`。

## 对比字段

API 会返回 `comparison`：

- `comparison.period`：上一段等长自然周范围。
- `comparison.summary`：汇总指标的当前值、上期值、差值、变化率和语义趋势。
- `comparison.rows`：行级指标对比。
- WR 的未归集费用对比在 `comparison.extras.unallocated`。

回答用户时优先使用 API 返回的对比字段，不要自己重复计算环比，除非用户明确要求展示计算过程。

## SKU / SPU 筛选规则

- `sku_codes` 使用内部 SKU code，API 会按内部 SKU 归集筛选。
- `master_sku_ids` 使用 `ec_master_skus.id`，API 会展开为其子 SKU。
- 如果用户只给 SPU code 或商品名，先用 SQL 查询 `ec_master_skus` / `ec_skus` 找到 ID 或 SKU code，再调用 API。

查询 SPU 示例：

```sql
SELECT id, master_sku_code, product_name
FROM ec_master_skus
WHERE master_sku_code ILIKE '%关键词%'
   OR product_name ILIKE '%关键词%'
ORDER BY master_sku_code
LIMIT 20
```

查询 SKU 示例：

```sql
SELECT sku_code, product_name, master_sku_id
FROM ec_skus
WHERE deleted_at IS NULL
  AND (sku_code ILIKE '%关键词%' OR product_name ILIKE '%关键词%')
ORDER BY sku_code
LIMIT 20
```

## 回答策略

- 先判断问题对应 `wr`、`wsu` 还是 `wsu_deep`。
- 确认自然周边界；日期不符合自然周时先询问或明确调整。
- WR 必须确认平台账号；WSU 和 WSU-DEEP 不需要 `store_ref`。
- 命中 API 后直接调用 `/ai/weekly_profit_reports.json`，再基于返回的 `summary`、`rows`、`extras` 和 `comparison` 作答。
- 回答利润时说明币种：WB WR 是 BYN，Ozon WR 是 RUB，WSU/WSU-DEEP 是 CNY。
- 未归集金额不应静默丢弃；回答时说明是否包含 `unallocated` 或 `after_tax_with_unallocated`。
- 如果 API 返回错误，不要改用手写 SQL 硬算；先解释错误原因和需要补充的数据，例如周汇率、自然周范围或有效账号。

## SQL 仅用于辅助排查

只有以下情况才使用 SQL：

- 查找 `store_ref` 对应账号。
- 查找用户给出的 SPU/SKU/商品名对应的 `master_sku_ids` 或 `sku_codes`。
- 排查 API 错误原因，例如周汇率是否存在、账号是否启用、SKU 是否绑定。
- 用户明确要求查看某张原始平台表的明细。

周汇率排查示例：

```sql
SELECT week_start, rate_cny_rub, rate_byn_rub
FROM ec_weekly_rates
WHERE week_start = DATE '2026-07-06'
```

启用账号排查时不要查询凭据字段。原始流水排查时只查询必要字段，并明确说明这些 SQL 结果只是中间线索，不等同于 WR/WSU/WSU-DEEP 的最终归集结果。
