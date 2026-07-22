# WB 多自然周利润归集设计

## 背景

当前 `Ec::WbProfitAttribution` 主要按单个自然周使用，周利润结果同时被 Google Sheet 周报和 Web 查询复用。底层明细数据中：

- `RawWb::FinanceDetail`、`RawWb::PaidStorage` 可按任意日期范围过滤。
- `RawWb::AdSettledFee` 的常规同步存储策略是按自然周（周一到周日）分段落库。

这导致一个不一致：

- 单周查询天然可用。
- 当 `from_date..to_date` 跨 2 个或 N 个完整自然周时，`Ec::WbProfitAttribution` 仍按整段 `period_from = from_date AND period_to = to_date` 精确匹配 `RawWb::AdSettledFee`。
- 如果库中只有逐周缓存而没有整段缓存，跨周查询会漏掉广告费，导致结果不能稳定复用到 Web 和 Google Sheet 共存场景。

Ozon 侧 `Ec::OzonProfitAttribution` 已支持完整自然周范围的逐周拼接。WB 需要补齐同类能力，但不要求把多周结果做到逐周汇率精确。

## 目标

为 `Ec::WbProfitAttribution` 增加“跨 2 个或 N 个完整自然周”的广告费拼接能力，使其在以下条件下可稳定出数：

- `from_date` 落在周一，`to_date` 落在周日。
- 查询范围是 14 天及以上，且天数是 7 的整数倍。
- 每个自然周都有对应的 `RawWb::AdSettledFee` 缓存。

实现后，Google Sheet 和后续 Web 页面继续共用 `Ec::WbProfitAttribution` 这一套数字逻辑。

## 非目标

- 不改 `Ec::WbProfitAttribution` 的利润公式、税务公式、仓储或货物成本逻辑。
- 不把多周查询改成逐周独立汇率后再汇总。
- 不在页面请求里补同步 `RawWb::AdSettledFee`。
- 不改 Ozon 逻辑。
- 不直接实现新的周利润筛选页面。

## 设计约束

- 单个自然周的结果必须保持与当前口径一致。
- 多周查询的汇率继续沿用调用方传入的一组 `rate_cny_rub` / `rate_byn_rub`。
  - 这是有意接受的近似。
  - 单周查询仍是主要场景，必须保持 100% 周口径。
- 页面与 Google Sheet 的共享逻辑以服务层为准，不能在 Web controller 里单独拼一套数字。
- 广告费缓存命中必须严格按 `period_from` 和 `period_to` 精确匹配。
  - 局部缓存（例如自然周中的 `2026-06-23..2026-06-25`）不能参与整周 `2026-06-22..2026-06-28` 查询。
  - 多周查询也只能合并每个完整自然周的精确 pair，不能把范围内重叠但不相等的缓存一起带入。

## 方案

### 核心思路

保留 `Ec::WbProfitAttribution` 的现有调用方式和现有分摊算法，只改广告费读取阶段：

1. 优先使用整段 `from_date..to_date` 的 `RawWb::AdSettledFee` 精确缓存。
2. 如果没有精确缓存，且查询范围满足“多个完整自然周”，则尝试按周拼接：
   - 生成 `[[week1_mon, week1_sun], [week2_mon, week2_sun], ...]`
   - 仅当每周缓存都存在时，合并这些周的 `RawWb::AdSettledFee`
3. 如果既没有整段缓存，也不能完整命中逐周缓存，则保持现状：
   - 不额外补同步
   - 广告费按当前逻辑表现为缺失或部分缺失

这样可以保证：

- 单周场景完全不变。
- 多周完整自然周场景在已有逐周缓存时可以自动合并广告费。
- 页面只读约束不被破坏。

### 服务改动

在 `Ec::WbProfitAttribution` 内新增两个私有方法：

- `resolve_ad_fee_periods`
- `multi_week_range?`

行为定义如下。

#### `resolve_ad_fee_periods`

返回值：

- `[[from_date, to_date]]`：命中整段缓存
- `[[week1_mon, week1_sun], [week2_mon, week2_sun], ...]`：命中多周逐周缓存
- `nil`：无法安全解析广告费周期

判定顺序：

1. 若存在 `RawWb::AdSettledFee.where(account_id: @account_id, period_from: @from_date, period_to: @to_date)`，直接返回整段范围。
2. 若不是完整自然周多周范围，返回 `nil`。
3. 生成逐周范围。
4. 仅当每周范围都存在至少一条 `RawWb::AdSettledFee` 记录时，返回这些周范围。
5. 否则返回 `nil`。

命中规则补充：

- 只能认精确 `period_from = x` 且 `period_to = y` 的缓存。
- 不能因为某条缓存与目标范围“有重叠”就纳入。
- 这条规则同时适用于单周查询和多周逐周拼接。

#### `multi_week_range?`

当且仅当以下条件全部满足时返回 `true`：

- 总天数大于等于 14 天
- 总天数能被 7 整除
- `@from_date.cwday == 1`
- `@to_date.cwday == 7`

### `load_ad_costs` 调整

当前实现只查单段：

- `period_from = @from_date`
- `period_to = @to_date`

改为：

1. 先调用 `resolve_ad_fee_periods`
2. 用返回的周期数组构造一个 OR scope
3. 将命中的所有 `RawWb::AdSettledFee` 合并为统一的 `fees`
4. 后续广告活动、SKU 花费占比、隐含汇率、按销量拆白俄/出口的逻辑全部保持不变

这样广告费合并只发生在“读缓存”这一层，不会动到现有利润链路。

### 周期命中安全性

`Ec::WbProfitAttribution` 读取广告费缓存时只能使用两类周期：

- 整段查询的精确 `[@from_date, @to_date]`
- 多周查询拆出的每个精确自然周 `[week_start, week_end]`

禁止使用任何“范围有重叠但不完全相等”的缓存记录。这样可以避免：

- 局部按需缓存污染整周查询
- 多条不同粒度缓存在同一范围里被重复累计
- 页面和 Google Sheet 因缓存粒度不同而得到不同结果

## 行为示例

### 示例 1：单周查询

- 输入：`2026-06-01..2026-06-07`
- 有精确周缓存
- 结果：沿用当前逻辑，不变

### 示例 2：两周查询，库里只有逐周缓存

- 输入：`2026-06-01..2026-06-14`
- 不存在整段 `period_from=2026-06-01, period_to=2026-06-14`
- 存在：
  - `2026-06-01..2026-06-07`
  - `2026-06-08..2026-06-14`
- 结果：广告费读取自动拼接两周数据，再进入当前分摊流程

### 示例 3：两周查询，但第二周缓存缺失

- 输入：`2026-06-01..2026-06-14`
- 第一周存在，第二周不存在
- 结果：不做半套拼接，`resolve_ad_fee_periods` 返回 `nil`
- 服务保持当前行为，不在读页面时触发同步

## 风险与取舍

### 汇率近似

多周查询仍使用调用方传入的一组汇率。这样做会让跨周 CNY/BYN 折算不是逐周精确，但符合当前业务要求：

- 单周口径必须严格正确
- 多周口径可接受近似，只用于排查问题和观察趋势

### 缓存完备性

该方案依赖 `RawWb::AdSettledFee` 的逐周缓存齐全。若某些周未同步：

- 不会在页面查询中自动补数
- 不会静默拼接部分周
- 输出会继续体现当前数据缺失状态

这是刻意保守的行为，避免页面 GET 隐式写库。

## 测试方案

新增 `Ec::WbProfitAttribution` 服务测试，至少覆盖：

1. 单周范围命中整段缓存时，仍按整段读取广告费。
2. 两周完整自然周范围且没有整段缓存、但每周缓存齐全时，会合并两周 `RawWb::AdSettledFee`。
3. 两周范围但缺少任一周缓存时，不走逐周拼接。
4. 非完整自然周范围时，不走逐周拼接。
5. 存在周中局部缓存时，整周查询不会误读这些缓存。
6. 多周查询只会合并每周精确缓存，不会读入范围内重叠但不相等的缓存。

测试重点放在 `load_ad_costs` 的周期解析和广告费合并，不重写整套利润公式测试。

## 实施结果预期

完成后：

- `Ec::WbProfitAttribution` 可像 Ozon 一样支持跨 N 个完整自然周的广告费缓存拼接。
- 后续 WR / WSU / WSU-DEEP 的 Web 查询层可以继续复用现有服务，不必为 WB 另写一套跨周广告费逻辑。
- 单周 Google Sheet 周利润口径保持不变。
