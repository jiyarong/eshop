# Ozon Sales Funnel Period SQL Skill

用于回答 Ozon 销售漏斗自然周汇总数据相关问题。该 Skill 只描述 `raw_ozon_sales_funnel_period`，这是按自然周汇总的 SKU 维度销售漏斗数据。

## 适用问题

用户提到以下内容时应优先加载本 Skill：

- Ozon 销售漏斗。
- SKU 浏览、搜索浏览、商品卡浏览、加购、搜索加购、商品卡加购。
- 下单件数、下单金额、退货、取消。
- 漏斗转化率、加购率、从浏览到加购、商品卡转化。
- 按 SKU、商品、店铺查看 Ozon 漏斗数据。

不要把本 Skill 用于 WB 销售漏斗，WB 使用 `wb_sales_funnel_period` Skill。

## 时间口径

非常重要：`raw_ozon_sales_funnel_period` 是自然周汇总表，不是日表。

- 每行周期由 `period_start` 和 `period_end` 表示。
- `period_start` 必须是周一。
- `period_end` 必须是周日。
- “本周”指当前自然周的周一到周日。
- “上周”指上一个自然周的周一到周日。
- 用户要求“本周和上周环比”“本周 vs 上周”“这周比上周”时，默认就是当前自然周周一到周日对比上一个自然周周一到周日，即使今天是周三或周中任意一天，也不要改成最近 7 天或截至今天的等长区间。
- “近一个月”“最近 30 天”“近 3 个月”等相对时间，应自动落到完整自然周边界：开始日期向前/向后调整到周一，结束日期调整到周日，并在回答里明确告知用户实际查询的自然周范围。
- 如果用户要求某一天、某日、按天、日维度的销售漏斗数据，应直接说明：当前销售漏斗表暂时不支持按天查看，只支持自然周汇总。

当前周说明：

- 当前周数据按当前自然周入库，`period_start` 是本周周一，`period_end` 是本周周日。
- 当前周未结束时，表里的本周数据是截至最近同步时间的周累计，不代表完整周最终值。

示例：

- 用户问“本周 Ozon 销售漏斗”：查询当前自然周周一到周日，并说明本周未结束时是截至同步时间的累计。
- 用户问“上周 Ozon 加购”：查询上一个自然周周一到周日。
- 用户问“本周环比上周”：查询当前自然周周一到周日对比上一个自然周周一到周日，并说明如果本周尚未结束，本周数据是截至最近同步时间的自然周累计。
- 用户问“近一个月销售漏斗”：先转换为覆盖近一个月的若干自然周，再告知“已按自然周查询，实际周期为 YYYY-MM-DD 到 YYYY-MM-DD”。
- 用户问“7 月 10 日销售漏斗”：不要查询，应说明暂时不支持按天看。

## 数据表

### `raw_ozon_sales_funnel_period`

Ozon SKU 维度自然周销售漏斗汇总表。每行代表一个 Ozon 账号、一个自然周、一个 Ozon SKU 的汇总数据。

唯一粒度：

- `account_id`
- `period_start`
- `period_end`
- `sku`

核心字段：

- `account_id`：Ozon 原始账号 ID，关联 `raw_ozon_seller_accounts.id`。
- `period_start`：自然周开始日期，周一。
- `period_end`：自然周结束日期，周日。
- `sku`：Ozon SKU。
- `product_name`：商品名。

浏览与会话指标：

- `hits_view`：总浏览次数。
- `hits_view_search`：搜索场景浏览次数。
- `hits_view_pdp`：商品详情页浏览次数。
- `session_view`：总浏览会话数。
- `session_view_search`：搜索场景浏览会话数。
- `session_view_pdp`：商品详情页浏览会话数。

加购与转化指标：

- `hits_tocart`：总加购次数。
- `hits_tocart_search`：搜索场景加购次数。
- `hits_tocart_pdp`：商品详情页加购次数。
- `conv_tocart`：加购转化率，来自 Ozon 接口。

订单结果指标：

- `ordered_units`：下单件数。
- `revenue`：下单金额。
- `returns_count`：退货数量。
- `cancellations`：取消数量。

排查字段：

- `raw_json`：接口原始单 SKU 返回。
- `synced_at`：同步时间。
- `created_at`、`updated_at`：内部记录时间。

## 账号与店铺关系

- `raw_ozon_sales_funnel_period.account_id = raw_ozon_seller_accounts.id`
- `ec_stores.platform = 'ozon'`
- `ec_stores.ozon_raw_account_id = raw_ozon_sales_funnel_period.account_id`

默认店铺口径：

- 销售漏斗数据默认不要汇总所有店铺，应按店铺分别展示或分组统计。
- 除非用户明确要求“全部店铺合计”“跨店铺汇总”，否则 SQL 必须保留 `ec_stores.id`、`ec_stores.store_name` 或 `account_id` 作为分组维度。
- Ozon 销售漏斗接口依赖 Premium/高级分析权限；如果某些 Ozon 店铺未订阅 Premium 或接口权限不足，可能没有数据。
- 发现部分店铺没有销售漏斗数据时，应在回答里明确告知用户哪些店铺没有数据，并说明可能是未订阅 Premium、接口权限不足或尚未同步，不要静默忽略。

查询店铺名称时关联 `ec_stores`：

```sql
JOIN ec_stores
  ON ec_stores.platform = 'ozon'
 AND ec_stores.ozon_raw_account_id = raw_ozon_sales_funnel_period.account_id
```

## 商品与内部 SKU 关系

如需归属内部 SKU，优先通过 `ec_sku_products` 绑定关系：

- `ec_sku_products.store_id = ec_stores.id`
- `ec_sku_products.platform = 'ozon'`
- `ec_sku_products.platform_sku_id = raw_ozon_sales_funnel_period.sku::text`

不要只用商品名模糊匹配内部 SKU。Ozon 的内部 SKU 归属优先使用 `platform_sku_id` 绑定。

## 常见查询口径

- 浏览次数：`SUM(hits_view)`。
- 搜索浏览次数：`SUM(hits_view_search)`。
- 商品详情页浏览次数：`SUM(hits_view_pdp)`。
- 加购次数：`SUM(hits_tocart)`。
- 搜索加购次数：`SUM(hits_tocart_search)`。
- 商品详情页加购次数：`SUM(hits_tocart_pdp)`。
- 下单件数：`SUM(ordered_units)`。
- 下单金额：`SUM(revenue)`。
- 退货数量：`SUM(returns_count)`。
- 取消数量：`SUM(cancellations)`。
- 加购率：可用平台返回 `conv_tocart`；多 SKU 汇总时更稳妥使用 `SUM(hits_tocart) / NULLIF(SUM(hits_view), 0)`。

Ozon 表没有 WB 的买断、买断金额、加购到下单平台返回字段；如果用户问这些指标，应说明当前 Ozon 自然周漏斗表没有对应字段，只能用现有浏览、加购、下单、退货、取消指标近似分析。

## 使用原则

- 查询必须过滤自然周周期，不要用任意日区间直接筛 `period_start <= date AND period_end >= date` 来伪造日数据。
- 用户要按天看时，直接说明暂不支持按天销售漏斗。
- 用户给出非自然周范围时，应转换为自然周范围并告知转换后的 `period_start` 和 `period_end`。
- 当前周未结束时，应说明本周数据是截至最近同步时间的累计。
- 环比本周和上周时，默认使用当前自然周完整周期对比上一个自然周完整周期，即便今天是周三；不要使用最近 7 天、过去 7 天或截至今天的等长区间替代。
- 默认按店铺分开展示销售漏斗，不要默认把所有店铺加总；只有用户明确要求跨店铺合计时才汇总。
- 发现部分店铺没有销售漏斗数据时，应在回答里说明可能是未订阅 Premium、接口权限不足或尚未同步。
- 汇总多个 SKU 或店铺时，计数类字段用 `SUM`；比例类字段不要简单平均，优先用分子分母重算。
- 不要查询 `raw_ozon_seller_accounts.api_key`、`client_id`、`performance_client_secret` 等敏感字段。
