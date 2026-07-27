# WB Ads SQL Skill

用于回答 WB/Wildberries 推广活动、广告商品、预算、费用、曝光、点击、加购、订单、推广订单金额、CTR、CPC、CPM、ROAS 和广告费用占比相关问题。

## 核心表关系

```text
ec_stores
  -> raw_wb_adv_campaigns
       -> raw_wb_adv_campaign_products
       -> raw_wb_adv_campaign_daily_stats
       -> raw_wb_adv_product_daily_stats
       -> raw_wb_adv_budget_snapshots
       -> raw_wb_adv_expenses
```

关联条件：

- `raw_wb_adv_campaigns.store_id = ec_stores.id`，且 `ec_stores.platform = 'wb'`。
- 其余表的 `campaign_id = raw_wb_adv_campaigns.id`。
- `raw_wb_adv_expenses.store_id = ec_stores.id`；`campaign_id` 可为空，无法识别活动时仍可按 `advert_id` 排查。
- `raw_wb_adv_campaigns.advert_id` 是 WB 活动 ID；不要把它与内部 `id` 混用。

## `raw_wb_adv_campaigns`

WB 活动主表。唯一粒度是 `store_id + advert_id`。

- `id`：内部活动主键。
- `store_id`：关联 `ec_stores.id`。
- `advert_id`：WB 活动 ID。
- `name`：活动名称。
- `campaign_type`：WB 活动类型整数，保留平台值。
- `status`：WB 活动状态：
  - `-1`：已删除。
  - `4`：准备启动。
  - `7`：展示已结束。
  - `8`：已拒绝。
  - `9`：进行中。
  - `11`：已暂停。
- `payment_type`：计费方式，如 `cpm/cpc`。
- `bid_type`：出价方式，如统一出价或手动出价的内部标准值。
- `placements`：JSON 投放位置，例如搜索、商品推荐。
- `currency`：币种，通常 RUB。
- `can_change_nms`：是否允许修改活动商品。
- `source_created_at`、`source_started_at`、`source_updated_at`、`source_deleted_at`：WB 活动业务时间。
- `is_current`：是否仍在最新活动列表中。当前活动查询必须加 `is_current = true`。
- `raw_payload`、`synced_at`：活动接口原始数据与同步时间。

页面默认活动状态为 `9` 和 `11`，但 SQL 应以用户要求为准。

## `raw_wb_adv_campaign_products`

活动商品配置表。唯一粒度是 `campaign_id + nm_id`。

- `campaign_id`：关联活动。
- `nm_id`：WB 商品 ID。
- `subject_id`、`subject_name`：WB 商品品类。
- `search_bid_kopecks`：搜索出价，单位戈比；换算 RUB 使用 `/ 100.0`。
- `recommendation_bid_kopecks`：推荐位出价，单位戈比；换算 RUB 使用 `/ 100.0`。
- `is_current`：是否仍在活动当前商品配置中。
- `raw_payload`、`synced_at`：原始配置和同步时间。

`is_current` 只表示当前配置，不是历史配置快照。不要用它判断历史日期某商品是否曾属于活动。

内部 SKU 归属：

```sql
JOIN ec_sku_products sp
  ON sp.store_id = raw_wb_adv_campaigns.store_id
 AND sp.platform = 'wb'
 AND sp.product_id = raw_wb_adv_campaign_products.nm_id::text
JOIN ec_skus s
  ON s.sku_code = sp.sku_code
 AND s.deleted_at IS NULL
```

不要只用商品名称、供应商编码或其他冗余字段归属内部 SKU。

## `raw_wb_adv_campaign_daily_stats`

活动日统计表。唯一粒度是 `campaign_id + stat_date`。

- `views`：展示次数。
- `clicks`：点击次数。
- `add_to_cart`：加入购物车次数。
- `orders`：归因订单数。
- `ordered_units`：下单商品件数。
- `canceled`：技术取消数。
- `spend`：广告费用，平台币种。
- `revenue`：推广归因订单金额，平台币种。
- `ctr`、`cpc`、`cr`：平台返回或同步计算的日指标。
- `currency`：币种。
- `stat_date`：统计日期。
- `raw_payload`：`/adv/v3/fullstats` 每日原始数据。
- `synced_at`：同步时间。

### 关联转化口径

活动日统计的 `orders`、`add_to_cart`、`ordered_units` 和 `revenue` 来自 WB `fullstats` 顶层汇总，包含 WB 活动详情中的“基础活动统计 + 关联转化”。它们能与活动详情两部分相加后的逐行活动数据对应，但不一定等于 WB 网页顶部汇总。

因此：

- 可以用本表回答逐活动推广表现和 `fullstats` 官方接口口径。
- 不要声称 `SUM(revenue)` 能复刻 WB 网页顶部“订单金额”。
- 当前数据库没有可靠字段把基础统计与关联转化完整拆开。
- 如果用户要求 WB 网页顶部订单金额、ROAS 或支出占比，应说明该数字暂不可由公开接口和现有表可靠复刻。

派生指标用汇总值重算：

- `CTR = 100 * SUM(clicks) / NULLIF(SUM(views), 0)`。
- `CPC = SUM(spend) / NULLIF(SUM(clicks), 0)`。
- `CPO = SUM(spend) / NULLIF(SUM(orders), 0)`。
- `CR = 100 * SUM(orders) / NULLIF(SUM(clicks), 0)`。
- `CPM = 1000 * SUM(spend) / NULLIF(SUM(views), 0)`。
- `DRR = 100 * SUM(spend) / NULLIF(SUM(revenue), 0)`，仅代表 `fullstats` 含关联转化口径。
- `ROAS = SUM(revenue) / NULLIF(SUM(spend), 0)`，仅代表 `fullstats` 含关联转化口径。

## `raw_wb_adv_product_daily_stats`

活动商品日统计表。唯一粒度是 `campaign_id + stat_date + app_type + nm_id`。

- `campaign_id`、`stat_date`、`nm_id`：活动、日期、WB 商品。
- `product_name`：接口返回商品名。
- `app_type`：展示场景类型；`-1` 是同步生成的跨场景合计行。
- `views`、`clicks`、`add_to_cart`。
- `orders`、`ordered_units`、`canceled`。
- `spend`、`revenue`。
- `ctr`、`cpc`、`cr`、`avg_position`。
- `currency`、`raw_payload`、`synced_at`。

### 防重复规则

商品汇总必须只使用 `app_type = -1`，因为同一商品同一天还保存各展示场景明细。把 `-1` 与其他 `app_type` 一起求和会重复一遍：

```sql
WHERE raw_wb_adv_product_daily_stats.app_type = -1
```

商品统计可能包含并非当前活动配置商品的归因行。需要区分当前配置商品和“其他归因”时，左连接 `raw_wb_adv_campaign_products`，并使用相同的 `campaign_id + nm_id` 判断；不要直接丢弃未配置商品。

## `raw_wb_adv_budget_snapshots`

活动预算余额快照表。一条活动可以有多个观测时间。

- `campaign_id`：关联活动。
- `cash`：现金余额。
- `netting`：抵扣/轧差余额。
- `total`：总预算余额。
- `currency`：币种。
- `observed_at`：实际观测时间。
- `raw_payload`：预算接口原始数据。

当前预算必须按每个活动取 `observed_at` 最新的一行，严禁 `SUM` 所有快照：

```sql
ROW_NUMBER() OVER (PARTITION BY campaign_id ORDER BY observed_at DESC, id DESC)
```

预算余额不是选定日期范围内的历史预算；它是最近一次同步时看到的当前余额。

## `raw_wb_adv_expenses`

WB 广告费用流水/结算明细表，来自 `/adv/v1/upd`。唯一识别使用 `store_id + source_fingerprint`。

- `store_id`：店铺。
- `campaign_id`：可空的内部活动 ID。
- `advert_id`：WB 活动 ID。
- `expense_at`：费用流水时间。
- `campaign_name`：流水中的活动名。
- `payment_type`：支付类型。
- `upd_num`：WB 流水编号。
- `amount`：结算费用金额。
- `advert_type`、`advert_status`：流水返回的活动类型和状态。
- `currency`：币种。
- `source_fingerprint`：幂等去重指纹。
- `raw_payload`、`synced_at`。

`raw_wb_adv_expenses.amount` 是结算/费用流水口径；`raw_wb_adv_campaign_daily_stats.spend` 是推广统计口径。经营效果分析通常使用 `spend`，财务结算、扣费流水和对账使用 `amount`。不要在同一汇总中把两者相加。

## 常见查询路径

活动日表现：

```sql
FROM raw_wb_adv_campaigns c
JOIN raw_wb_adv_campaign_daily_stats d ON d.campaign_id = c.id
JOIN ec_stores st ON st.id = c.store_id AND st.platform = 'wb'
```

商品日表现：

```sql
FROM raw_wb_adv_product_daily_stats d
JOIN raw_wb_adv_campaigns c ON c.id = d.campaign_id
JOIN ec_stores st ON st.id = c.store_id AND st.platform = 'wb'
WHERE d.app_type = -1
```

当前活动商品数：对 `raw_wb_adv_campaign_products` 加 `is_current = true` 后按 `campaign_id` 计数。

## 查询原则

- 默认按店铺和 `stat_date` 过滤，不要默认跨店铺合计。
- 当前活动加 `raw_wb_adv_campaigns.is_current = true`。
- 当前配置商品加 `raw_wb_adv_campaign_products.is_current = true`；历史统计不要因此过滤掉。
- 商品日统计只汇总 `app_type = -1`。
- 比例类字段不要简单 `AVG`，使用汇总分子分母重算。
- 预算取最新快照，不要累加快照。
- 推广 `spend` 与费用流水 `amount` 分开使用。
- 订单金额是广告归因口径，不是纯订单或财务销售额。
- 不要查询店铺 `wb_api_token` 等凭据字段。
