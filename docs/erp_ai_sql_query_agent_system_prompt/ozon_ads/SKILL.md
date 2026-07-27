# Ozon Ads SQL Skill

用于回答 Ozon 推广、Performance 广告、CPC 活动、CPO 选品推广、全店 CPO 推广、广告花费、曝光、点击、加购、广告订单和推广销售额相关问题。

## 核心表关系

```text
ec_stores
  -> raw_ozon_seller_accounts
       -> raw_ozon_ad_units
            -> raw_ozon_ad_unit_products
            -> raw_ozon_ad_daily_stats
            -> raw_ozon_ad_sku_daily_stats
       -> raw_ozon_ad_report_runs

raw_ozon_ad_unit_products.raw_ozon_product_id
raw_ozon_ad_sku_daily_stats.raw_ozon_product_id
  -> raw_ozon_products.id
```

关联条件：

- `ec_stores.platform = 'ozon'`。
- `ec_stores.ozon_raw_account_id = raw_ozon_seller_accounts.id`。
- `raw_ozon_ad_units.account_id = raw_ozon_seller_accounts.id`。
- `raw_ozon_ad_unit_products.ad_unit_id = raw_ozon_ad_units.id`。
- `raw_ozon_ad_daily_stats.ad_unit_id = raw_ozon_ad_units.id`。
- `raw_ozon_ad_sku_daily_stats.ad_unit_id = raw_ozon_ad_units.id`。
- 日统计表的 `account_id` 也应等于活动的 `account_id`；连接时优先使用 `ad_unit_id`，同时按店铺账号过滤。

## `raw_ozon_ad_units`

Ozon 推广单元/活动主表。唯一粒度是 `account_id + unit_type + external_id`。

- `id`：内部主键，其他广告表通过 `ad_unit_id` 关联。
- `account_id`：Ozon 原始账号 ID。
- `external_id`：Ozon 活动 ID，字符串类型。
- `unit_type`：内部归一化推广类型：
  - `cpc_campaign`：普通 CPC 活动。
  - `cpo_selected`：选品推广/按订单付费。
  - `cpo_all`：全店商品推广。
- `title`：活动名称。
- `state`：活动状态，常见值为 `CAMPAIGN_STATE_RUNNING`、`CAMPAIGN_STATE_INACTIVE`、`CAMPAIGN_STATE_ARCHIVED`。
- `billing_model`：平台计费方式，来自 `PaymentType/paymentType` 并转为小写。
- `strategy`：自动推广策略。
- `placement`：投放位置数组。
- `daily_budget`、`weekly_budget`：预算，单位 RUB；接口微单位已在同步时除以 `1,000,000`。
- `from_date`、`to_date`：平台活动起止日期。
- `raw_json`：活动接口原始数据。
- `synced_at`：最近同步时间。

默认活动列表不要展示已归档活动，除非用户明确要求：

```sql
WHERE raw_ozon_ad_units.state <> 'CAMPAIGN_STATE_ARCHIVED'
```

## `raw_ozon_ad_unit_products`

活动当前/历史商品配置表。唯一粒度是 `ad_unit_id + ozon_sku_id`。

- `ad_unit_id`：关联推广活动。
- `ozon_sku_id`：Ozon SKU，字符串类型。
- `raw_ozon_product_id`：可空，关联 `raw_ozon_products.id`。
- `source_sku`：接口返回的来源 SKU。
- `title`：商品名。
- `state`：商品在推广中的状态。
- `is_current`：是否仍在当前活动配置中。查询当前商品必须加 `is_current = true`。
- `bid`：CPC 出价；接口微单位已换算为 RUB。
- `bid_price`：平台返回的出价金额。
- `target_cir`：目标广告成本占比/目标 CIR，保留平台返回数值。
- `price`：商品价格。
- `views`：配置接口附带的浏览数据，不要代替日统计表的曝光量。
- `added_at`、`removed_at`：加入/移出活动时间；可能为空。
- `image_url`：商品图片地址。
- `raw_json`、`synced_at`：原始数据与同步时间。

内部 SKU 归属必须通过店铺和平台绑定：

```sql
JOIN ec_sku_products sp
  ON sp.store_id = ec_stores.id
 AND sp.platform = 'ozon'
 AND sp.platform_sku_id = raw_ozon_ad_unit_products.ozon_sku_id
JOIN ec_skus s
  ON s.sku_code = sp.sku_code
 AND s.deleted_at IS NULL
```

不要仅通过商品名、`source_sku` 或 `offer_id` 猜测内部 SKU。

## `raw_ozon_ad_daily_stats`

活动日统计表。唯一粒度是 `ad_unit_id + stat_date + cost_model`。

- `account_id`、`ad_unit_id`：账号和活动。
- `stat_date`：统计日期。
- `cost_model`：统计来源/计费口径；同一活动同一天可能有不同口径行。
- `impressions`：曝光次数。
- `clicks`：点击次数。
- `cart_additions`：加购次数；部分活动级报表可能为空，CPC 页面会从 SKU 日统计补加购。
- `orders_count`：推广售出商品数/广告订单件数。
- `ad_revenue`：推广销售额，RUB。
- `model_orders_count`、`model_revenue`：平台模型订单件数和模型推广销售额，不等同于实际 `orders_count/ad_revenue`。
- `total_order_revenue`：平台报告中的全部下单金额；当前推广页面不使用，不要替代 `ad_revenue`。
- `spend`：广告费用，RUB。
- `raw_json`、`synced_at`：原始报表行和同步时间。

常见派生指标必须用汇总后的分子分母重算：

- `CTR = 100 * SUM(clicks) / NULLIF(SUM(impressions), 0)`。
- `平均 CPC = SUM(spend) / NULLIF(SUM(clicks), 0)`。
- `DRR = 100 * SUM(spend) / NULLIF(SUM(ad_revenue), 0)`。
- `每单费用 = SUM(spend) / NULLIF(SUM(orders_count), 0)`。

## `raw_ozon_ad_sku_daily_stats`

SKU 日统计表。唯一粒度是 `ad_unit_id + ozon_sku_id + stat_date + cost_model`。

维度字段：

- `account_id`、`ad_unit_id`、`ozon_sku_id`、`stat_date`。
- `raw_ozon_product_id`：可空，关联 `raw_ozon_products.id`。
- `cost_model`：常见值：
  - `cpc`：最近日期的实时商品统计。
  - `cpc_history`：CPC 历史报表导入。
  - `cpo`：选品推广的按订单付费部分。
  - `combo`：选品推广的组合计费部分。

指标字段：

- `impressions`、`clicks`、`cart_additions`。
- `orders_count`、`ad_revenue`。
- `model_orders_count`、`model_revenue`。
- `total_order_revenue`：全部下单金额，不是推广销售额。
- `spend`、`price`、`avg_cpc`、`ctr`、`drr`。
- `date_added`：商品加入推广日期。
- `raw_json`、`synced_at`。

### CPC 去重规则

同一个 `ad_unit_id + ozon_sku_id + stat_date` 可能同时有 `cpc` 和 `cpc_history`。汇总 SKU 数据时只能选一条，优先 `cpc_history`，否则会重复计算：

```sql
ROW_NUMBER() OVER (
  PARTITION BY ad_unit_id, ozon_sku_id, stat_date
  ORDER BY CASE cost_model WHEN 'cpc_history' THEN 0 ELSE 1 END
)
```

只保留 `row_number = 1`。不要直接对 `cost_model IN ('cpc', 'cpc_history')` 求和。

## `raw_ozon_ad_report_runs`

异步广告报表运行记录，用于同步排查，不是经营指标表。

- `account_id`、`report_type`、`endpoint`。
- `period_from`、`period_to`：报告周期。
- `state`：`pending/completed/failed` 等运行状态。
- `external_uuid`：Ozon 异步报告 ID。
- `request_body`：请求参数；可包含导入时间、导入行数。
- `attempts`、`submitted_at`、`completed_at`、`error_message`。
- `response_checksum`：响应校验值。

只有排查缺数、失败报告、同步时间时查询本表；不要把报告运行数当作推广活动数。

## 页面汇总口径

Ozon 推广概览按 `unit_type + placement` 汇总，但不同推广类型的数据来源不同：

- CPC：活动日统计提供曝光、点击、订单、销售额和费用。
- `cpo_selected`：活动日统计只贡献费用；订单件数和推广销售额来自 SKU 日统计中 `cost_model = 'cpo'` 的行。
- `cpo_all`：普通活动日统计贡献曝光、点击、加购、费用；`cost_model = 'cpo_all_report'` 的活动日统计只贡献订单件数和推广销售额。
- 汇总时不要把 `cpo_all_report` 与普通活动日统计的全部指标一起相加，否则费用或流量可能重复。

## 查询原则

- 默认按店铺和日期过滤，不要默认跨店铺合计。
- 日统计使用 `stat_date`，活动配置的 `from_date/to_date` 不能替代统计日期。
- 比例字段不要简单 `AVG`，使用汇总分子分母重算。
- 当前活动商品加 `is_current = true`；历史统计不要因为商品现在被移出就丢弃。
- 通过 `ec_sku_products.platform_sku_id` 绑定内部 SKU。
- 不要查询 Ozon 账号或店铺中的 API Key、Client ID、Client Secret 等凭据字段。
