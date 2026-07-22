# WB Sales Funnel Period SQL Skill

用于回答 WB 销售漏斗自然周汇总数据相关问题。该 Skill 只描述 `raw_wb_sales_funnel_period`，这是按自然周汇总的商品维度销售漏斗数据。

## 适用问题

用户提到以下内容时应优先加载本 Skill：

- WB 销售漏斗、Wildberries 销售漏斗。
- 商品浏览、打开商品卡、加购、下单、支付、买断、取消、收藏。
- 漏斗转化率、加购率、加购到下单转化、买断率。
- 商品曝光后的购买路径、商品漏斗表现、商品卡转化。
- 按商品、nm_id、vendor code、品牌、品类、店铺查看 WB 漏斗数据。

不要把本 Skill 用于 Ozon 销售漏斗，Ozon 使用 `ozon_sales_funnel_period` Skill。

## 时间口径

非常重要：`raw_wb_sales_funnel_period` 是自然周汇总表，不是日表。

- 每行周期由 `period_start` 和 `period_end` 表示。
- `period_start` 必须是周一。
- `period_end` 必须是周日。
- “本周”指当前自然周的周一到周日。
- “上周”指上一个自然周的周一到周日。
- 用户要求“本周和上周环比”“本周 vs 上周”“这周比上周”时，默认就是当前自然周周一到周日对比上一个自然周周一到周日，即使今天是周三或周中任意一天，也不要改成最近 7 天或截至今天的等长区间。
- “近一个月”“最近 30 天”“近 3 个月”等相对时间，应自动落到完整自然周边界：开始日期向前/向后调整到周一，结束日期调整到周日，并在回答里明确告知用户实际查询的自然周范围。
- 如果用户要求某一天、某日、按天、日维度的销售漏斗数据，应直接说明：当前销售漏斗表暂时不支持按天查看，只支持自然周汇总。

示例：

- 用户问“本周 WB 销售漏斗”：查询当前自然周周一到周日。
- 用户问“上周加购率”：查询上一个自然周周一到周日。
- 用户问“本周环比上周”：查询当前自然周周一到周日对比上一个自然周周一到周日，并说明如果本周尚未结束，本周数据是截至最近同步时间的自然周累计。
- 用户问“近一个月销售漏斗”：先转换为覆盖近一个月的若干自然周，再告知“已按自然周查询，实际周期为 YYYY-MM-DD 到 YYYY-MM-DD”。
- 用户问“7 月 10 日销售漏斗”：不要查询，应说明暂时不支持按天看。

## 数据表

### `raw_wb_sales_funnel_period`

WB 商品维度自然周销售漏斗汇总表。每行代表一个 WB 账号、一个自然周、一个 WB 商品 `nm_id` 的汇总数据。

唯一粒度：

- `account_id`
- `period_start`
- `period_end`
- `nm_id`

核心字段：

- `account_id`：WB 原始账号 ID，关联 `raw_wb_seller_accounts.id`。
- `period_start`：自然周开始日期，周一。
- `period_end`：自然周结束日期，周日。
- `currency`：币种，默认 `RUB`。
- `nm_id`：WB 商品 ID。
- `vendor_code`：供应商编码，常可对应内部 SKU。
- `product_name`：商品名。
- `brand`：品牌。
- `subject_id`、`subject`：WB 品类。
- `tags`：商品标签。
- `product_rating`、`feedback_rating`：商品评分。
- `stock_wb`、`stock_mp`、`stock_balance_sum`：接口返回的库存信息。

当前周期漏斗指标：

- `open_card`：打开商品卡 / 浏览商品卡次数。
- `add_to_cart`：加购次数。
- `orders`：下单数量。
- `orders_sum`：下单金额。
- `buyouts`：买断数量。
- `buyouts_sum`：买断金额。
- `cancel_count`：取消数量。
- `cancel_sum`：取消金额。
- `avg_price`：平均价格。
- `avg_orders_per_day`：日均订单数。
- `share_order_percent`：订单占比。
- `add_to_wishlist`：加入收藏数量。
- `localization_percent`：本地化比例。
- `conv_to_cart`：商品卡到加购转化率。
- `cart_to_order`：加购到下单转化率。
- `buyout_percent`：买断率。

对比周期字段：

- `past_*`：上一对比周期的同类指标。
- `*_dynamic`：当前周期相对对比周期的动态变化字段。

WB Club 字段：

- `wb_club_orders`
- `wb_club_orders_sum`
- `wb_club_buyouts`
- `wb_club_buyouts_sum`
- `wb_club_cancel_count`
- `wb_club_cancel_sum`
- `wb_club_avg_price`
- `wb_club_buyout_percent`
- `wb_club_avg_orders_per_day`
- `past_wb_club_*`
- `wb_club_*_dynamic`

排查字段：

- `raw_json`：接口原始单商品返回。
- `synced_at`：同步时间。
- `created_at`、`updated_at`：内部记录时间。

## 账号与店铺关系

- `raw_wb_sales_funnel_period.account_id = raw_wb_seller_accounts.id`
- `ec_stores.platform = 'wb'`
- `ec_stores.wb_raw_account_id = raw_wb_sales_funnel_period.account_id`

默认店铺口径：

- 销售漏斗数据默认不要汇总所有店铺，应按店铺分别展示或分组统计。
- 除非用户明确要求“全部店铺合计”“跨店铺汇总”，否则 SQL 必须保留 `ec_stores.id`、`ec_stores.store_name` 或 `account_id` 作为分组维度。
- 如果某些 WB 店铺没有销售漏斗数据，可能是对应店铺未开通平台侧所需会员/权限、接口未返回数据或尚未同步；回答时要告知用户哪些店铺没有数据，不要静默忽略。

查询店铺名称时关联 `ec_stores`：

```sql
JOIN ec_stores
  ON ec_stores.platform = 'wb'
 AND ec_stores.wb_raw_account_id = raw_wb_sales_funnel_period.account_id
```

## 商品与内部 SKU 关系

如需归属内部 SKU，优先通过 `ec_sku_products` 绑定关系：

- `ec_sku_products.store_id = ec_stores.id`
- `ec_sku_products.platform = 'wb'`
- `ec_sku_products.product_id = raw_wb_sales_funnel_period.nm_id::text`

不要只用商品名模糊匹配内部 SKU。`vendor_code` 可用于展示和排查，但统计归属优先使用 `ec_sku_products` 的绑定关系。

## 常见查询口径

- 商品浏览量：`SUM(open_card)`。
- 加购量：`SUM(add_to_cart)`。
- 下单量：`SUM(orders)`。
- 下单金额：`SUM(orders_sum)`。
- 买断量：`SUM(buyouts)`。
- 买断金额：`SUM(buyouts_sum)`。
- 取消量：`SUM(cancel_count)`。
- 加购率：可用平台返回 `conv_to_cart`；多商品汇总时更稳妥使用 `SUM(add_to_cart) / NULLIF(SUM(open_card), 0)`。
- 加购到下单转化率：可用平台返回 `cart_to_order`；多商品汇总时更稳妥使用 `SUM(orders) / NULLIF(SUM(add_to_cart), 0)`。
- 买断率：可用平台返回 `buyout_percent`；多商品汇总时更稳妥使用 `SUM(buyouts) / NULLIF(SUM(orders), 0)`。

## 使用原则

- 查询必须过滤自然周周期，不要用任意日区间直接筛 `period_start <= date AND period_end >= date` 来伪造日数据。
- 用户要按天看时，直接说明暂不支持按天销售漏斗。
- 用户给出非自然周范围时，应转换为自然周范围并告知转换后的 `period_start` 和 `period_end`。
- 环比本周和上周时，默认使用当前自然周完整周期对比上一个自然周完整周期，即便今天是周三；不要使用最近 7 天、过去 7 天或截至今天的等长区间替代。
- 默认按店铺分开展示销售漏斗，不要默认把所有店铺加总；只有用户明确要求跨店铺合计时才汇总。
- 发现部分店铺没有销售漏斗数据时，应在回答里说明可能是店铺未开通平台侧所需会员/权限、接口不可用或尚未同步。
- 汇总多个商品或店铺时，计数类字段用 `SUM`；比例类字段不要简单平均，优先用分子分母重算。
- 不要查询 `raw_wb_seller_accounts.api_token` 等敏感字段。
