# 2026-07-09 销售漏斗接口调研记录

> 状态：临时记录，供后续继续追接口、定首版字段方案使用。
>
> 范围：Wildberries（WB）与 Ozon 的“销售漏斗/近似漏斗”公开接口、当前系统已有落库、与后台页面字段差异。

## 1. 当前产品方向共识

- 首版可以先不做 SKU 漏斗详情，不依赖按天明细。
- 首版核心可以收敛为区间列表：
  - 顶部时间范围选择器沿用现有通用 range picker
  - 列表以 `SKU + 店铺` 为一行
  - 先支持单店铺
  - WB 与 Ozon 后续可以统一到一个列表页面里展示
- 运营主场景偏自然周，但 UI 允许任意日期范围。

## 2. WB：公开销售漏斗接口结论

### 2.1 已确认接口

- `POST /api/analytics/v3/sales-funnel/products`
- `POST /api/analytics/v3/sales-funnel/products/history`
- `POST /api/v2/search-report/product/search-texts`

Base URL：

- `https://seller-analytics-api.wildberries.ru`

### 2.2 `sales-funnel/products` 公开响应里实际有什么

公开示例与线上实测都表明，这个接口返回的是商品区间级漏斗，主要字段包括：

- 商品维度：
  - `nmId`
  - `title`
  - `vendorCode`
  - `brandName`
  - `subjectId`
  - `subjectName`
  - `tags`
  - `productRating`
  - `feedbackRating`
  - `stocks.wb`
  - `stocks.mp`
  - `stocks.balanceSum`
- 本期 `selected`：
  - `openCount`
  - `cartCount`
  - `orderCount`
  - `orderSum`
  - `buyoutCount`
  - `buyoutSum`
  - `cancelCount`
  - `cancelSum`
  - `avgPrice`
  - `avgOrdersCountPerDay`
  - `shareOrderPercent`
  - `addToWishlist`
  - `timeToReady`
  - `localizationPercent`
  - `wbClub.*`
  - `conversions.addToCartPercent`
  - `conversions.cartToOrderPercent`
  - `conversions.buyoutPercent`
- 上期 `past`：同结构
- 环比 `comparison`：`*Dynamic` 和 `conversions.*`

### 2.3 `sales-funnel/products` 公开响应里没有什么

当前公开示例与线上实测都没有看到：

- `viewCount`
- `viewToOpenConversion`
- `CTR`
- `impressions`
- `展示量`

结论：

- 这个接口给的是“页面浏览之后”的后半段漏斗，不是后台完整的“展示 -> 浏览 -> 加购 -> 下单 -> 成交”链路。

### 2.4 与 WB 后台页面真实 JSON 的关系

后台页面抓到过如下字段（同一商品）：

- `viewCount`
- `openCardCount`
- `addToCartCount`
- `addToWishlistCount`
- `orderCount`
- `orderSum`
- `buyoutCount`
- `buyoutSum`
- `buyoutPercent`
- `viewToOpenConversion`
- `openToCartConversion`
- `cartToOrderConversion`
- `prev*`

已确认映射关系：

- 公开 `openCount` -> 后台 `openCardCount`
- 公开 `cartCount` -> 后台 `addToCartCount`
- 公开 `addToWishlist` -> 后台 `addToWishlistCount`
- 公开 `orderCount` -> 后台 `orderCount`
- 公开 `orderSum` -> 后台 `orderSum`
- 公开 `buyoutCount` -> 后台 `buyoutCount`
- 公开 `buyoutSum` -> 后台 `buyoutSum`
- 公开 `cancelCount` -> 后台 `cancelCount`
- 公开 `cancelSum` -> 后台 `cancelSum`
- 公开 `conversions.addToCartPercent` -> 后台 `openToCartConversion`
- 公开 `conversions.cartToOrderPercent` -> 后台 `cartToOrderConversion`
- 公开 `conversions.buyoutPercent` -> 后台 `buyoutPercent`

仍然缺失：

- 后台 `viewCount`
- 后台 `viewToOpenConversion`

因此：

- 公开 openapi 不能直接复刻后台完整漏斗列表。

### 2.5 与后台页面数值对照后的确认

对照店铺 `TaxiLink`、商品：

- `vendorCode = LDD001-BK`
- `nmId = 1135117446`

后台页面关键值：

- `展示量 = 48,324`
- `页面浏览 = 2,165`
- `商品加购 = 225`
- `加入收藏夹 = 109`
- `下单商品量 = 13`
- `订单金额 = 2,760 Br`
- `实际成交数量 = 5`
- `取消订单商品 = 0`

同类区间下，公开接口实测值接近：

- `openCount = 2180`
- `cartCount = 226`
- `addToWishlist = 109`
- `orderCount = 13`
- `orderSum = 2760`
- `buyoutCount = 5`
- `cancelCount = 0`

由此确认：

- `openCount` 更接近后台“页面浏览”
- 不是后台“展示量”

### 2.6 `CTR` 的当前判断

后台口径：

- `CTR = 页面浏览 / 展示量`
- 即 `viewToOpenConversion = openCardCount / viewCount`

因为公开 `sales-funnel/products` 没有 `viewCount`，所以：

- 公开接口当前拿不到完整 `CTR`
- 也无法从当前字段可靠反推

### 2.7 `search-texts` 接口结论

实测 `POST /api/v2/search-report/product/search-texts` 返回的是搜索词维度数据，不是商品整体漏斗。主要字段包括：

- `text`
- `nmId`
- `vendorCode`
- `name`
- `price`
- `frequency.current`
- `weekFrequency`
- `medianPosition.current`
- `avgPosition.current`
- `openCard.current`
- `addToCart.current`
- `openToCart.current`
- `orders.current`
- `cartToOrder.current`
- `visibility.current`

这个接口的 `visibility` 不是后台 `viewCount`，`openCard.current` 也只是搜索词语境下的局部值，不能替代商品总漏斗。

### 2.8 `sales-funnel/products/history` 的边界

- 这个接口提供按天/按周历史。
- 官方说明最多支持最近 1 周。
- 如果后续要做 SKU 详情按天趋势，普通实时接口只能覆盖最近 7 天。

## 3. Ozon：当前系统已有的“漏斗近似数据”

### 3.1 当前主数据源

当前最接近销售漏斗的数据源是：

- `POST /v1/analytics/data`

当前代码调用参数：

- `dimension: ['sku']`
- `metrics`：
  - `revenue`
  - `ordered_units`
  - `returns`
  - `cancellations`
  - `hits_view_pdp`
  - `hits_tocart`
  - `session_view`
  - `adv_view_all`

### 3.2 真实响应结构

线上实测真实结构：

- 顶层：
  - `result`
  - `timestamp`
- `result`：
  - `data`
  - `totals`
- `data[*]`：
  - `dimensions`（数组）
  - `metrics`（数组）

重要说明：

- 真实响应中没有 `result.dimension`
- 真实响应中没有 `result.metrics`
- `metrics` 是纯数组，必须按请求顺序自行映射

### 3.3 实测可用 metric

已实测可用：

- `revenue`
- `ordered_units`
- `returns`
- `cancellations`
- `hits_view_pdp`
- `hits_tocart`
- `session_view`

已实测报错：

- `adv_view_all`
  - 返回 `400 {"code":3,"message":"deprecated metrics used"}`

结论：

- 当前 Ozon 同步逻辑里继续请求 `adv_view_all` 不稳，应视为废弃字段。

### 3.4 当前系统落库

当前落在：

- `raw_ozon_analytics`

字段包括：

- `account_id`
- `date_from`
- `date_to`
- `dimension_keys`
- `dimension_values`
- `ordered_units`
- `revenue`
- `returns_count`
- `cancellations`
- `hits_view_pdp`
- `hits_tocart`
- `session_view`
- `adv_view_all`
- `raw_json`
- `synced_at`

注意：

- 当前代码对真实响应结构的解析假设不准确，需要修正。

### 3.5 当前同步机制

- Ozon analytics 放在 `RawOzon::WeeklySync`
- 生产定时：
  - 每周二 `03:00` 执行 `RawOzon::WeeklySync.run(days: 8)`
- 当前不是小时级，也不是日级
- 当前更像“近 8 天区间聚合快照”

### 3.6 Ozon 搜索相关数据

另有：

- `POST /v1/analytics/product-queries`
- `POST /v1/analytics/product-queries/details`

这组更偏搜索分析，不是主销售漏斗。

## 4. 跨平台列表的当前可行范围

如果首版先做 `SKU + 店铺` 行级列表，而不做 SKU 漏斗详情，当前可行。

建议能对齐的前置字段：

- `SKU`
- `店铺`
- `平台`
- `负责人`
- `页面浏览 / PDP View`
- `加购`
- `下单`
- `取消`

可作为平台冗余字段放后面：

- WB：
  - `buyoutCount`
  - `buyoutSum`
  - `buyoutPercent`
  - `addToWishlist`
  - `localizationPercent`
  - `stocks.*`
- Ozon：
  - `returns`
  - `revenue`
  - `session_view`

当前不能强行对齐的点：

- WB 后台 `展示量`
- WB `CTR`
- Ozon 是否存在同口径“展示量”

## 5. 当前阶段的最稳建议

### 5.1 如果只做区间列表

可以先做：

- WB：基于 `sales-funnel/products` 的“页面浏览之后”漏斗
- Ozon：基于 `analytics/data` 的 SKU 区间聚合

这样能先满足：

- 时间范围内店铺/SKU 对比
- 环比对比
- 运营日常周视角盯盘

### 5.2 如果要复刻 WB 后台完整列表

还缺：

- `viewCount`
- `viewToOpenConversion / CTR`

下一步更有效的方向不是继续猜公开接口，而是：

- 直接抓 WB 卖家后台“销售漏斗阶段”页面真实请求
- 确认后台 JSON 来源是否为私有接口或未公开报表接口

## 6. 后续待办

- [ ] 抓 WB 卖家后台“销售漏斗阶段”页面的真实请求接口
- [ ] 确认后台 `viewCount`、`viewToOpenConversion` 是否可通过可编程方式拿到
- [ ] 修正 Ozon `analytics/data` 当前解析逻辑
- [ ] 基于现有公开能力，整理跨平台 `SKU + 店铺` 首版字段清单
- [ ] 决定首版是否接受“WB 无展示量/CTR，仅显示页面浏览后的后半段漏斗”
