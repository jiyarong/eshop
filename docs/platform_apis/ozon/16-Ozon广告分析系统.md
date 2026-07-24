# Ozon 广告分析系统

本文档描述项目当前 Ozon 广告数据的接口来源、数据结构、设计依据、同步机制、查询口径和运维边界。除非特别说明，本文所称“广告分析系统”均指 `RawOzon::Ads::*` 新链路，而不是周利润归集使用的旧 `RawOzon::PerformanceSync` 链路。

## 1. 系统目标与边界

当前系统服务于以下只读分析页面：

- 推广总览：`GET /reports/ozon_ads`
- 按点击付费活动：`GET /reports/ozon_ads/cpc`
- CPC 活动 SKU 详情：`GET /reports/ozon_ads/cpc/:id`
- 按订单付费（所选商品）：`GET /reports/ozon_ads/cpo/selected`

系统只负责从 Ozon 拉取、落库、查询和展示数据，不提供创建活动、修改预算、调整出价、启停或归档活动等反向控制功能。

页面请求严格只读。Controller 和 ERB 不调用 Ozon API，不触发同步，也不补数据；所有平台访问均在后台同步任务中完成。

## 2. 设计来源

页面结构和指标语义主要参考 Ozon Seller 的三个页面：

- 推广总览：<https://seller.ozon.ru/app/advertisement/product/overview>
- 按点击付费：<https://seller.ozon.ru/app/advertisement/product/cpc>
- 按订单付费（所选商品）：<https://seller.ozon.ru/app/advertisement/product/cpo/selected>

接口与字段定义参考：

- 仓库文档：`docs/platform_apis/ozon/15-广告投放与PerformanceAPI.md`
- 本地 Ozon Performance API 文档快照：`/Users/jiyarong/Downloads/ozon_perf/Документация Ozon Performance API.htm`
- Ozon Performance API 根地址：`https://api-performance.ozon.ru`

实现并非抓取 Seller 网页数据。Seller 页面仅作为产品设计和数据核对基准，生产数据全部来自 Performance API。

## 3. 两套广告链路的隔离原则

项目内存在两套 Ozon 广告链路，两者共享 Performance API 客户端和账号凭证，但表、同步服务和消费场景相互隔离。

| 链路 | 入口 | 数据表前缀 | 消费方 | 修改原则 |
|---|---|---|---|---|
| 周利润归集旧链路 | `RawOzon::PerformanceSync` | `raw_ozon_performance_*` | `Ec::OzonProfitAttribution`、周利润与 Google Sheets | 视为稳定财务链路，不因广告分析需求修改 |
| 推广分析新链路 | `RawOzon::Ads::Sync` | `raw_ozon_ad_*` | `/reports/ozon_ads*` | 新功能只在此链路演进 |

新链路不得写入以下旧表：

- `raw_ozon_performance_campaigns`
- `raw_ozon_performance_campaign_skus`
- `raw_ozon_performance_daily_stats`
- `raw_ozon_performance_sku_spends`

`RawOzonAdsSyncTest` 中的“syncs units products and CPC daily facts without touching legacy performance tables”测试用于守住这一边界。

## 4. 账号与认证

同步范围为满足以下条件的 `Ec::Store`：

- `platform = "ozon"`
- `is_active = true`
- 已配置 `ozon_performance_client_id`
- 已通过 `ozon_raw_account_id` 关联 `RawOzon::SellerAccount`

真正发起请求时使用关联账号的 `performance_client_id` 和 `performance_client_secret`。

`RawOzon::PerformanceClient` 使用 OAuth client credentials，通过 `POST /api/client/token` 获取 Bearer Token。Token 会缓存到过期前 60 秒；HTTP 429 和 5xx 最多重试 5 次，网络连接超时 10 秒、读取超时 30 秒。

## 5. 平台接口矩阵

| 用途 | 接口 | 形式 | 限制/说明 | 主要落库位置 |
|---|---|---|---|---|
| 活动主数据 | `GET /api/client/campaign` | JSON | 拉取 CPC、CPO selected、CPO all 活动 | `raw_ozon_ad_units` |
| CPC 活动商品 | `GET /api/client/campaign/{campaignId}/v2/products` | JSON | 仅同步非归档 CPC 活动 | `raw_ozon_ad_unit_products` |
| CPO selected 商品 | `POST /api/client/campaign/search_promo/v2/products` | JSON | 当前账号的所选商品推广 | `raw_ozon_ad_unit_products` |
| 活动日统计 | `GET /api/client/statistics/daily` | 同步 CSV | 每批最多 50 个活动 | `raw_ozon_ad_daily_stats` |
| CPC 最近 SKU 日统计 | `POST /api/client/statistics/products/sku` | JSON | 每批最多 10 个活动；当前实现只请求今天和昨天 | `raw_ozon_ad_sku_daily_stats`, `cost_model=cpc` |
| CPC 历史 SKU 日统计 | `POST /api/client/statistics` | 异步 CSV/ZIP | 每批最多 10 个活动；单报告最多 62 天；`groupBy=DATE` | `raw_ozon_ad_sku_daily_stats`, `cost_model=cpc_history` |
| 异步报告状态 | `GET /api/client/statistics/{UUID}` | JSON | 轮询至完成、错误或超时 | `raw_ozon_ad_report_runs` |
| 异步报告下载 | `GET /api/client/statistics/report?UUID=...` | CSV/ZIP | CPC 多活动报告可能返回 ZIP | 原始内容解析后落明细表 |
| CPO selected 统计 | `POST /api/client/statistic/products/generate` | 异步 CSV | 按自然日逐天生成；时间边界使用 `+03:00` | `raw_ozon_ad_sku_daily_stats`, `cost_model=cpo/combo` |
| CPO all 统计 | `GET /api/client/statistics/all_sku_promo/products/generate` | 异步 CSV | 给定日期范围；时间边界使用 `+03:00` | `raw_ozon_ad_daily_stats`, `cost_model=cpo_all_report` |

金额单位需要区别处理：

- 活动接口中的 `dailyBudget`、`weeklyBudget` 和 CPC 商品 `bid` 是微卢布，落库前除以 `1_000_000`。
- 统计 JSON 和 CSV 中的费用、销售额已经是卢布，按十进制金额直接保存。

## 6. 推广类型映射

`GET /api/client/campaign` 返回的活动被归一为三种 `unit_type`：

| Ozon 字段 | 本地 `unit_type` | 页面含义 |
|---|---|---|
| `advObjectType = ALL_SKU_PROMO` | `cpo_all` | 按订单付费：所有商品 |
| `advObjectType = SEARCH_PROMO` | `cpo_selected` | 按订单付费：所选商品 |
| 其他商品推广活动 | `cpc_campaign` | 按点击付费 |

`PaymentType/paymentType` 会被归一为小写 `billing_model`，例如 `cpc`、`cpo`。

## 7. 新链路数据结构

### 7.1 关系概览

```text
RawOzon::SellerAccount
  └── raw_ozon_ad_units                  活动/推广单元
        ├── raw_ozon_ad_unit_products    活动与 Ozon SKU 的当前关系
        ├── raw_ozon_ad_daily_stats      活动级日统计
        └── raw_ozon_ad_sku_daily_stats  活动 + SKU 级日统计

RawOzon::SellerAccount
  └── raw_ozon_ad_report_runs            异步报告执行审计
```

### 7.2 `raw_ozon_ad_units`

活动主表，一行代表一个账号下的一个推广活动或系统推广单元。

唯一键：`account_id + unit_type + external_id`。

关键字段：

- `external_id`：Ozon 活动 ID。
- `unit_type`：`cpc_campaign`、`cpo_selected` 或 `cpo_all`。
- `title`、`state`、`billing_model`、`strategy`。
- `placement`：投放位置数组，如 `PLACEMENT_SEARCH_AND_CATEGORY`。
- `daily_budget`、`weekly_budget`。
- `from_date`、`to_date`。
- `raw_json`：完整活动响应，包含尚未结构化的字段，例如 `updatedAt`。
- `synced_at`：最近一次平台同步时间。

活动状态支持：

- `CAMPAIGN_STATE_RUNNING`
- `CAMPAIGN_STATE_INACTIVE`
- `CAMPAIGN_STATE_ARCHIVED`

### 7.3 `raw_ozon_ad_unit_products`

活动与 Ozon SKU 的关系表。唯一键为 `ad_unit_id + ozon_sku_id`。

关键字段包括商品标题、状态、出价、目标费用比例、价格、图片、平台 SKU 和 `raw_ozon_product_id`。`is_current` 表示当前是否仍在活动中；同步时未返回的旧商品会被标记为非当前，并记录 `removed_at`。

`raw_ozon_product_id` 通过同账号 `RawOzon::Product.raw_json["sku"]` 与 Ozon SKU 匹配。页面进一步通过以下硬关联找到内部 `Ec::Sku`：

```text
ec_sku_products.store_id       = 当前店铺
ec_sku_products.platform       = "ozon"
ec_sku_products.platform_sku_id = ozon_sku_id
```

不使用 `offer_id` 或订单行上的冗余 `sku_code` 兜底。

### 7.4 `raw_ozon_ad_daily_stats`

活动级日统计。唯一键为 `ad_unit_id + stat_date + cost_model`。

主要指标：展示、点击、加购、售出数量、模型售出数量、推广销售额、模型销售额、总订单金额和费用。

主要 `cost_model`：

- `cpc`：CPC 活动日统计。
- `cpo`：CPO 活动日统计。
- `cpo_all_report`：CPO all 专用报告结果。

### 7.5 `raw_ozon_ad_sku_daily_stats`

活动 + SKU 级日统计。唯一键为 `ad_unit_id + ozon_sku_id + stat_date + cost_model`。

除活动级指标外，还保存 `price`、`avg_cpc`、`ctr`、`drr`、`date_added` 和 `raw_ozon_product_id`。

主要 `cost_model`：

- `cpc`：最近日期的 JSON SKU 统计。
- `cpc_history`：CPC 历史异步报表。
- `cpo`：按订单付费明细。
- `combo`：组合模型明细。

### 7.6 `raw_ozon_ad_report_runs`

异步报告执行审计表，记录报告类型、接口、日期范围、请求体、Ozon UUID、状态、校验和、错误和完成时间。

状态流程：

```text
submitting -> processing -> completed
                         -> failed
```

CPC 历史报告导入成功后，`request_body` 会追加 `imported_at` 和 `imported_rows`，用于补拉任务幂等判断。

## 8. 写入与幂等策略

活动、活动商品、活动日统计和 SKU 日统计都使用数据库唯一索引配合 `upsert_all`。相同业务键重复同步时覆盖最新值，不重复插入。

原始响应保存在各表的 `raw_json` 中，作用包括：

- 保留平台证据，便于核对解析问题。
- 支持暂未提升为结构化列的字段，例如活动 `updatedAt`。
- 允许接口扩展后渐进增加页面字段。

异步报告本身不保存文件，只保存请求、执行状态和下载内容 SHA-256；解析后的事实数据落入日统计表。

## 9. CSV 与 ZIP 处理

`RawOzon::Ads::CsvParser` 统一处理 Ozon 俄文 CSV：

- 分隔符为分号。
- 自动处理 UTF-8、Windows-1251 和 BOM。
- 处理俄式小数逗号、空格/不换行空格、卢布与百分号。
- 通过表头语义查找列，不依赖固定列号。
- 空值和破折号返回 `nil`，避免误解释为有效数据。

CPC 历史报告单活动时可能直接返回 CSV，多活动时可能返回 ZIP。ZIP 内文件名以活动 ID 开头，解析器据此将文件归属到请求中的活动；若压缩包活动 ID 与请求活动不相交，同步会失败而不是把数据写错活动。

## 10. 指标来源与合并规则

### 10.1 通用派生指标

查询层统一计算：

```text
CTR                 = clicks / impressions * 100
平均点击费用        = spend / clicks
广告费用份额（DRR） = spend / ad_revenue * 100
加购转化率          = cart_additions / clicks * 100
每单费用            = spend / orders_count
```

分母为 0 时返回空值，而不是 0%。

### 10.2 CPC 列表

费用、销售额、售出数量、展示和点击来自 `raw_ozon_ad_daily_stats`，按活动和页面日期范围聚合。

加购来自 `raw_ozon_ad_sku_daily_stats`。同一活动、SKU、日期同时存在 `cpc` 和 `cpc_history` 时，只选择 `cpc_history`；没有历史行时才使用 `cpc`，防止重复累计。

投放位置来自活动表 `placement`；更改日期来自活动 `raw_json["updatedAt"]`；平均点击费用用活动范围内的总费用除以总点击计算。

### 10.3 CPC SKU 详情

按活动下当前商品逐 SKU 汇总。相同 SKU/日期存在多个 CPC 来源时，同样优先 `cpc_history`。

单商品 CPC 活动存在一个特殊规则：SKU 详情直接使用该活动的完整活动级 `cpc` 指标，避免历史 SKU 接口不完整时详情页显示全 0。

### 10.4 CPO selected

一个 Ozon 报告行拆成两行事实：

- `cost_model=cpo`
- `cost_model=combo`

页面展示时可按 SKU 汇总两种模型，也可按模型分开分析。

### 10.5 CPO all

基础展示、点击、加购和费用来自通用活动日统计；专用 `cpo_all_report` 提供订单数和推广销售额。查询层只从各自权威来源取对应指标，防止重复合并。

## 11. 同步机制

### 11.1 日常同步

`ozon_ads_daily_sync`：每天北京时间 02:15 执行。

```ruby
RawOzon::Ads::Sync.run(from_date: Date.yesterday, to_date: Date.yesterday)
```

顺序为：

1. 同步活动。
2. 同步活动商品关系。
3. 同步活动日统计。
4. 同步最近 CPC SKU 统计。
5. 同步 CPO selected SKU 统计。
6. 同步 CPO all 统计。

### 11.2 近期窗口重刷

`ozon_ads_weekly_catchup`：每周日北京时间 03:30 执行，重刷最近 8 天至昨天的数据，用于恢复漏跑并吸收平台晚结算数据。

### 11.3 CPC 历史补拉

`ozon_ads_cpc_history_catchup`：每周日北京时间 05:30 执行，创建最近 8 天的历史报表任务。

`CpcHistoryBackfill` 按以下维度拆任务：

- 日期每段最多 62 天。
- 每份报告最多 10 个 CPC 活动。
- 仅处理非归档活动。

每个账号只排入一个链式 Job。`CpcHistoryBackfillJob` 每次处理一个任务，完成后再排入下一个，避免 Ozon 同时只允许有限异步报告的冲突。可重试错误由 Active Job 负责：限流/服务错误最多 5 次，API 错误最多 3 次。

### 11.4 手工补拉

完整同步一个日期范围：

```ruby
RawOzon::Ads::Sync.run(from_date: Date.new(2026, 7, 1), to_date: Date.yesterday)
```

排入 CPC 历史补拉：

```ruby
RawOzon::Ads::CpcHistoryBackfill.enqueue(
  from_date: 60.days.ago.to_date,
  to_date: Date.yesterday
)
```

补拉前必须先确保活动主数据已同步，否则任务无法构造正确的活动 ID 分组。

## 12. 页面查询与展示

Controller：`Reports::OzonAdsController`。

查询服务：`RawOzon::Ads::AnalyticsQuery`。

页面先按当前店铺确定 `RawOzon::SellerAccount`，再按 `account_id` 和日期范围读取本地事实表。默认店铺优先 `NEVASTAL`；默认结束日期为该账号活动日统计的最大日期，默认开始日期为结束日前 14 天。

CPC 默认状态为已激活和未激活，可多选加入已归档。活动搜索支持名称、活动 ID、Ozon SKU 和商品标题。

CPC 列表当前展示：

- 活动 ID、名称、状态、策略、预算、商品数。
- 投放位置、费用、推广销售额、售出数量。
- 展示、点击、加购、CTR、平均点击费用、更改日期。

活动名称通过 Turbo Frame 打开宽度 90% 的抽屉，展示活动汇总和 SKU 明细。SKU 优先显示关联的内部 `Ec::Sku.sku_code`，同时保留 Ozon SKU 作为辅助信息。

## 13. 与 Ozon Seller 的核对结果

以 NEVASTAL、2026-07-13 至 2026-07-19 为样本，CPC 活动逐 ID 核对结果：

- 名称、状态、预算、销售额、售出数量、展示、点击和 CTR 一致。
- 多数费用完全一致，少量活动存在正负 `0.01 RUB` 的舍入差异。
- 同状态范围汇总后，销售额、售出数量、展示、点击和 CTR 一致。
- 总费用与 Seller 页面存在约 `0.28%` 的差异，当前判断为 API 与 Seller 页面结算/更新时间和舍入顺序差异。

核对 Ozon 推广总览时，不能用总计行直接与 CPC 页面比较；总计包含 CPC 和两类 CPO。应只合计“按点击付费：搜索与推荐”和“按点击付费：搜索”。

## 14. 旧周利润链路摘要

旧链路由 `RawOzon::PerformanceSync` 驱动，包含：

- 活动：`raw_ozon_performance_campaigns`
- 活动日统计：`raw_ozon_performance_daily_stats`
- SKU 周期费用：`raw_ozon_performance_sku_spends`

它为 PPC SKU 费用使用异步 JSON 报告，并用报告 `totals.moneySpent` 对 SKU 行归一化；CPO/Combo/All SKU 推广费用按 SKU 合并写入周期表。`Ec::OzonProfitAttribution` 和周利润报表读取这些旧表。

定时任务：

- 周一 13:00：同步 W-2、W-1 两个完整自然周。
- 周四 03:00：当前周 T+1 结算补拉。

即使新广告分析表的数据看起来可以替代旧表，也不得直接切换周利润归集来源。任何迁移都必须作为独立财务口径项目设计、双跑和验数。

## 15. 测试与契约验证

主要测试：

- `test/live/raw_ozon/ads_api_contract_test.rb`：使用真实账号验证接口结构。
- `test/services/raw_ozon/ads_sync_test.rb`：同步、单位转换和新旧表隔离。
- `test/services/raw_ozon/ads_csv_parser_test.rb`：俄文 CSV 解析。
- `test/services/raw_ozon/ads_report_runner_test.rb`：异步报告状态与失败处理。
- `test/services/raw_ozon/ads_cpc_history_backfill_test.rb`：任务拆分。
- `test/jobs/raw_ozon/ads/cpc_history_backfill_job_test.rb`：链式补拉和幂等。
- `test/services/raw_ozon/ads_analytics_query_test.rb`：来源合并和防重复规则。
- `test/controllers/reports/ozon_ads_controller_test.rb`：页面筛选、抽屉和本地只读渲染。

真实接口契约测试默认跳过，需要显式设置：

```text
RUN_LIVE_OZON_ADS_TESTS=1
```

默认使用 `NEVASTAL`，也可通过 `OZON_LIVE_STORE_ID` 或 `OZON_LIVE_STORE_NAME` 指定店铺。

## 16. 已知限制与维护注意事项

- `/api/client/statistics/products/sku` 当前只适合今天和昨天；历史 SKU 数据必须使用异步历史报告。
- 历史补拉默认跳过已归档 CPC 活动。归档活动若需要完整 SKU 历史，必须设计明确的独立补拉范围。
- 活动 `updatedAt` 当前保存在 `raw_json`，未提升为独立列。
- `raw_json` 是审计和兼容字段，不应在高频大范围查询中代替结构化字段；当某字段成为筛选、排序或关联键时应新增正式列。
- Ozon 异步报告有并发槽位和限流，任务必须保持串行和批量限制。
- 页面中的金额统一按 RUB 展示；不要在原始层进行人民币换算。
- Seller UI 与 API 可能存在分钟级/结算级延迟，验数应固定账号、日期、活动状态范围和推广类型。
- 所有新分析需求优先扩展 `raw_ozon_ad_*`；不要为了复用代码改变 `raw_ozon_performance_*` 的写入方式或周利润口径。

## 17. 关键代码索引

- API 客户端：`app/services/raw_ozon/performance_client.rb`
- 新分析同步：`app/services/raw_ozon/ads/sync.rb`
- CSV 解析：`app/services/raw_ozon/ads/csv_parser.rb`
- 异步报告：`app/services/raw_ozon/ads/report_runner.rb`
- CPC 补拉：`app/services/raw_ozon/ads/cpc_history_backfill.rb`
- CPC 补拉 Job：`app/jobs/raw_ozon/ads/cpc_history_backfill_job.rb`
- 查询口径：`app/services/raw_ozon/ads/analytics_query.rb`
- 页面 Controller：`app/controllers/reports/ozon_ads_controller.rb`
- 页面模板：`app/views/reports/ozon_ads/`
- 新表 migration：`db/migrate/20260723082036_create_raw_ozon_ad_analytics_tables.rb`
- 定时任务：`config/recurring.yml`
- 旧周利润同步：`app/services/raw_ozon/performance_sync.rb`
