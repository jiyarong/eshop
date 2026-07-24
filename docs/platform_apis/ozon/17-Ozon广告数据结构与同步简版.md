# Ozon 广告数据结构与同步（简版）

本文只描述 Ozon 推广分析新链路 `RawOzon::Ads::*` 的表结构、数据关系和同步机制。

> 广告原始事实统一使用 `raw_ozon_ad_*`。周利润仅额外保留 `raw_ozon_performance_sku_spends` 作为周期费用投影。

## 1. 整体关系

```text
Ec::Store
  └── ozon_raw_account_id
        ↓
RawOzon::SellerAccount
  ├── raw_ozon_ad_units                  活动主表
  │     ├── raw_ozon_ad_unit_products    活动与 Ozon SKU 关系
  │     ├── raw_ozon_ad_daily_stats      活动级日统计
  │     └── raw_ozon_ad_sku_daily_stats  活动 + SKU 级日统计
  └── raw_ozon_ad_report_runs            异步报告执行记录
```

内部 SKU 关系：

```text
raw_ozon_ad_unit_products.ozon_sku_id
  = ec_sku_products.platform_sku_id

同时限定：
ec_sku_products.store_id = 当前店铺
ec_sku_products.platform = "ozon"

ec_sku_products.sku_id
  → ec_skus.id
```

## 2. 表结构

### 2.1 `raw_ozon_ad_units`

活动主表，一行代表一个账号下的一个 Ozon 推广活动或推广单元。

唯一键：

```text
account_id + unit_type + external_id
```

核心字段：

| 字段 | 含义 |
|---|---|
| `account_id` | Ozon 原始账号 |
| `external_id` | Ozon 活动 ID |
| `unit_type` | `cpc_campaign`、`cpo_selected`、`cpo_all` |
| `title` | 活动名称 |
| `state` | 已激活、未激活、已归档对应的平台枚举 |
| `billing_model` | `cpc` 或 `cpo` |
| `strategy` | 活动策略 |
| `placement` | 投放位置数组 |
| `daily_budget` / `weekly_budget` | 活动预算，单位 RUB |
| `from_date` / `to_date` | 活动起止日期 |
| `raw_json` | 完整平台活动响应，包含 `updatedAt` 等未结构化字段 |
| `synced_at` | 最近同步时间 |

活动类型映射：

| Ozon `advObjectType` | `unit_type` |
|---|---|
| `ALL_SKU_PROMO` | `cpo_all` |
| `SEARCH_PROMO` | `cpo_selected` |
| 其他商品推广活动 | `cpc_campaign` |

### 2.2 `raw_ozon_ad_unit_products`

活动与 Ozon SKU 的关系表。

唯一键：

```text
ad_unit_id + ozon_sku_id
```

核心字段：

| 字段 | 含义 |
|---|---|
| `ad_unit_id` | 所属活动 |
| `ozon_sku_id` | Ozon SKU |
| `raw_ozon_product_id` | 关联 `raw_ozon_products` |
| `title` / `image_url` | 商品展示信息 |
| `state` | 商品在活动中的状态 |
| `is_current` | 是否仍属于当前活动 |
| `bid` / `bid_price` | 出价信息 |
| `target_cir` | 目标费用比例 |
| `price` | 商品价格 |
| `added_at` / `removed_at` | 加入或移出活动的时间 |
| `raw_json` | 原始商品响应 |

每次同步会更新当前商品。平台不再返回的旧商品不会删除，而是设置：

```text
is_current = false
removed_at = 本次同步时间
```

### 2.3 `raw_ozon_ad_daily_stats`

活动级日统计，用于活动列表和推广总览。

唯一键：

```text
ad_unit_id + stat_date + cost_model
```

核心维度：账号、活动、统计日期、费用模型。

核心指标：

- `impressions`：展示次数
- `clicks`：点击次数
- `cart_additions`：加购次数
- `orders_count`：售出数量
- `model_orders_count`：模型售出数量
- `ad_revenue`：推广销售额
- `model_revenue`：模型推广销售额
- `total_order_revenue`：总订单金额
- `spend`：推广费用

常见 `cost_model`：

- `cpc`
- `cpo`
- `cpo_all_report`

### 2.4 `raw_ozon_ad_sku_daily_stats`

活动 + SKU 级日统计，用于 CPC 抽屉详情、加购汇总和 CPO 商品分析。

唯一键：

```text
ad_unit_id + ozon_sku_id + stat_date + cost_model
```

除活动日统计指标外，还保存：

- `raw_ozon_product_id`
- `price`
- `avg_cpc`
- `ctr`
- `drr`
- `date_added`

主要 `cost_model`：

| 值 | 来源 |
|---|---|
| `cpc` | 最近日期 CPC SKU JSON 接口 |
| `cpc_history` | CPC 历史异步报表 |
| `cpo` | 所选商品按订单付费 |
| `combo` | 所选商品组合模型 |

同一活动、SKU、日期同时存在 `cpc` 和 `cpc_history` 时，查询优先使用 `cpc_history`，防止重复累计。

### 2.5 `raw_ozon_ad_report_runs`

异步报告执行和审计表。

核心字段：

| 字段 | 含义 |
|---|---|
| `account_id` | Ozon 账号 |
| `report_type` | 报告类型 |
| `endpoint` | 生成报告的接口 |
| `period_from` / `period_to` | 报告范围 |
| `external_uuid` | Ozon 报告 UUID |
| `state` | `submitting`、`processing`、`completed`、`failed` |
| `request_body` | 请求参数及导入结果 |
| `response_checksum` | 下载内容 SHA-256 |
| `error_message` | 失败原因 |
| `submitted_at` / `completed_at` | 执行时间 |

CPC 历史报告导入成功后，`request_body` 会附加：

```text
imported_at
imported_rows
```

补拉任务用它判断相同报告是否已经完成导入。

## 3. 数据来源

```text
GET /api/client/campaign
  → raw_ozon_ad_units

GET /api/client/campaign/{campaignId}/v2/products
POST /api/client/campaign/search_promo/v2/products
  → raw_ozon_ad_unit_products

GET /api/client/statistics/daily
  → raw_ozon_ad_daily_stats

POST /api/client/statistics/products/sku
  → raw_ozon_ad_sku_daily_stats (cpc)

POST /api/client/statistics
  → 异步 CSV/ZIP
  → raw_ozon_ad_sku_daily_stats (cpc_history)

POST /api/client/statistic/products/generate
  → raw_ozon_ad_sku_daily_stats (cpo + combo)

GET /api/client/statistics/all_sku_promo/products/generate
  → raw_ozon_ad_daily_stats (cpo_all_report)
```

## 4. 单次同步流程

入口：

```ruby
RawOzon::Ads::Sync.run(from_date: from_date, to_date: to_date)
```

处理顺序：

```text
1. 同步活动主数据
2. 同步活动与商品关系
3. 同步活动级日统计
4. 同步最近 CPC SKU 日统计
5. 同步 CPO selected SKU 统计
6. 同步 CPO all 统计
```

同步范围是所有启用且配置 Performance 凭证的 Ozon 店铺。每个店铺必须关联一个 `RawOzon::SellerAccount`。

## 5. 写入与幂等

活动、活动商品、活动日统计和 SKU 日统计均使用唯一索引配合 `upsert_all`：

- 重复同步相同业务键时更新原记录。
- 不因重跑产生重复事实。
- 每条记录保留最近 `synced_at`。
- `raw_json` 保留平台原始数据用于核对和兼容新字段。

异步报告会先创建 `raw_ozon_ad_report_runs`，再提交平台任务、轮询状态、下载并解析，最后标记完成或失败。

## 6. 定时同步

| 任务 | 时间 | 范围 | 用途 |
|---|---|---|---|
| `ozon_ads_daily_sync` | 每天 02:15 | 昨天 | 日常增量 |
| `ozon_ads_weekly_catchup` | 每周日 03:30 | 最近 8 天至昨天 | 修复漏跑和平台晚结算 |
| `ozon_ads_cpc_history_catchup` | 每周日 05:30 | 最近 8 天至昨天 | 补齐 CPC SKU 历史 |

以上时间均为 `Asia/Shanghai`。

## 7. CPC 历史补拉

入口：

```ruby
RawOzon::Ads::CpcHistoryBackfill.enqueue(
  from_date: from_date,
  to_date: to_date
)
```

拆分规则：

- 每个报告最多 62 天。
- 每个报告最多 10 个 CPC 活动。
- 默认只处理非归档活动。
- 每个账号按链式 Job 串行执行，前一个完成后再排下一个。

串行的原因是 Ozon 异步报告存在并发槽位和限流。失败任务按错误类型自动重试；已经成功导入的报告通过 `raw_ozon_ad_report_runs` 跳过。

## 8. 查询口径

CPC 活动列表：

- 费用、销售额、售出数量、展示、点击来自活动日统计。
- 加购来自 SKU 日统计，并按活动 + SKU + 日期去重。
- 平均点击费用为总费用除以总点击。
- 投放位置来自活动表。
- 更改日期来自活动 `raw_json["updatedAt"]`。

CPC SKU 详情：

- 按活动 + SKU 汇总 SKU 日统计。
- `cpc_history` 优先于重叠的 `cpc`。
- 单商品活动可使用活动级完整统计，避免历史 SKU 数据缺失导致详情全 0。

CPO：

- 所选商品报告拆为 `cpo` 和 `combo` 两种事实。
- 全商品推广的订单与销售额优先使用 `cpo_all_report`。

## 9. 关键代码

- 同步：`app/services/raw_ozon/ads/sync.rb`
- 查询：`app/services/raw_ozon/ads/analytics_query.rb`
- CSV 解析：`app/services/raw_ozon/ads/csv_parser.rb`
- 异步报告：`app/services/raw_ozon/ads/report_runner.rb`
- CPC 补拉：`app/services/raw_ozon/ads/cpc_history_backfill.rb`
- 补拉 Job：`app/jobs/raw_ozon/ads/cpc_history_backfill_job.rb`
- 表结构：`db/migrate/20260723082036_create_raw_ozon_ad_analytics_tables.rb`
- 定时任务：`config/recurring.yml`
