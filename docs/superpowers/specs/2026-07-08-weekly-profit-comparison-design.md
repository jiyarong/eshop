# 周利润报表环比设计

## 背景

当前 `/weekly_profit_reports` 已统一承载三类周利润结果：

- `WR`：单店铺周利润归集
- `WSU`：跨平台跨店铺周汇总
- `WSU-DEEP`：SKU 深度周汇总

这三类结果已经共用同一套后端查询逻辑，并与 Google Sheet 周报复用同一套数字来源。当前页面能展示“本期值”，但还没有统一的“上一周期对比”能力。

用户要求为所有适合对比的周利润数字增加“环比”展示，规则如下：

- 以上一等长完整自然周范围作为基准。
- 以当前查询范围为本期，计算对比百分比。
- 页面中所有适合对比的数字都显示红绿箭头和百分比。
- 不能为 Web 页面另写一套数字逻辑，必须继续共用服务端查询结果。

## 目标

为 `WR`、`WSU`、`WSU-DEEP` 增加统一的环比能力，使 Web 页面可以直接渲染：

- 当前值
- 上一周期值
- 变化值
- 环比百分比
- 数学方向（升 / 降 / 平）
- 业务语义颜色（好 / 坏 / 中性）

实现后：

- 页面展示与服务端查询保持一致。
- 后续 Google Sheet 如需复用环比能力，不需要重新定义计算规则。
- 不新增第二套页面层计算逻辑。

## 非目标

- 当前阶段不要求 Google Sheet 立即展示环比。
- 不改现有利润公式、汇率口径、成本归集口径。
- 不增加任意日期对比器，仅支持“上一等长完整自然周范围”。
- 不在前端临时计算业务环比，避免与服务层分叉。

## 核心规则

### 对比周期

当前周期仍使用用户选择的 `from_date..to_date`，且必须满足现有约束：

- `from_date` 为周一
- `to_date` 为周日
- 查询范围长度为 `7 * N`
- 当前自然周不可查询

上一周期定义为“当前周期向前平移同样天数”：

- `span_days = (to_date - from_date).to_i + 1`
- `prev_from = from_date - span_days`
- `prev_to = to_date - span_days`

由于当前周期已经是完整自然周范围，且长度总是 `7 * N`，所以上一周期天然也仍然落在自然周边界上。

示例：

- 当前：`2026-06-01..2026-06-28`
- 长度：28 天
- 上一周期：`2026-05-04..2026-05-31`

### 环比计算

每个可比较指标统一输出以下结构：

```json
{
  "current": 128400.0,
  "previous": 114200.0,
  "delta_value": 14200.0,
  "delta_pct": 12.43,
  "trend": "up",
  "semantic": "positive"
}
```

字段含义：

- `current`：当前周期值
- `previous`：上一周期值
- `delta_value`：`current - previous`
- `delta_pct`：`(current - previous) / previous * 100`
- `trend`：纯数学方向
  - `up`
  - `down`
  - `flat`
  - `none`
- `semantic`：业务语义，用于页面颜色
  - `positive`
  - `negative`
  - `neutral`
  - `none`

### 空值与边界规则

- 若上一周期无对应值，返回：
  - `previous = nil`
  - `delta_value = nil`
  - `delta_pct = nil`
  - `trend = "none"`
  - `semantic = "none"`
- 若当前与上一周期都为 `0`：
  - `delta_value = 0`
  - `delta_pct = 0`
  - `trend = "flat"`
  - `semantic = "neutral"`
- 不使用 `∞` 或类似无穷符号，统一显示 `-`

### 业务语义上色

不是所有字段都按“值变大=绿色”处理，而是按业务语义分类：

#### 正向指标

上升视为好，下降视为差：

- 销量
- 销售额
- 税前毛利
- 税后净利
- 利润率
- ROI
- 年化收益
- 年化净利
- 平均每单利润

#### 反向指标

上升视为差，下降视为好：

- 广告费
- 货物成本
- 税额
- 佣金
- 配送费 / 物流费 / 仓储费
- 未分摊费用

#### 中性指标

纯标识字段不做环比：

- SKU
- 平台
- 店铺
- nm_id
- vendor_code
- region
- ozon_sku_id
- sku_code

## 方案选择

采用“服务端统一产出 current + previous + delta”的方案。

原因：

1. 当前系统已经要求 Web 与 Google Sheet 共用一套数字逻辑。
2. 很多指标不是简单前端相减，尤其：
   - 汇总卡片
   - 未分摊费用
   - 利润率 / 占比 / ROI 等派生指标
3. 若把环比逻辑放在视图层，后续 Sheet 复用时又会形成第二套规则。

因此，环比计算必须落在查询层或查询层紧邻的对比构建层，而不是前端 helper。

## 返回结构设计

三类 query 均保留现有返回结构，同时新增统一 `comparison` 节点。

```json
{
  "report_type": "wsu",
  "period": {
    "from_date": "2026-06-01",
    "to_date": "2026-06-28"
  },
  "comparison": {
    "period": {
      "from_date": "2026-05-04",
      "to_date": "2026-05-31"
    },
    "summary": {},
    "rows": {}
  }
}
```

定义：

- `comparison.period`：上一周期范围
- `comparison.summary`：摘要卡片对应的环比结构
- `comparison.rows`：表格行对应的环比结构，按唯一主键索引

`comparison.rows` 不直接复制完整当前行，而是返回“该行哪些字段可比较”的对比 map。

例如 `WSU`：

```json
{
  "rows": {
    "KJ-228|WB|WB Test Shop": {
      "net_sales": { "...": "..." },
      "revenue": { "...": "..." },
      "ads": { "...": "..." }
    }
  }
}
```

这样可以避免污染原始 `rows` 结构，同时让页面按需查找比较结果。

## 查询层设计

### 公共能力

新增一个统一的比较构建模块，建议放在 `Ec::WeeklyReportComparisonSupport` 或并入现有 `Ec::WeeklySummarySupport` 的同层级支持模块中，职责包括：

- 计算上一周期范围
- 计算单字段比较结构
- 根据字段类型决定业务语义
- 构建摘要比较 map
- 构建行级比较 map

对 `WR`、`WSU`、`WSU-DEEP`，都采用：

1. 先查询当前周期结果
2. 再查询上一周期结果
3. 用统一比较器生成 `comparison`

### WR

`Ec::WeeklyProfitReportQuery` 当前只返回单店铺当前周期结果，需要补上一周期相同店铺结果。

处理方式：

1. 使用同一 `store_ref`
2. 用上一周期 `prev_from..prev_to`
3. 调同一 attribution service 再取一遍
4. 当前行与上一周期行按平台内唯一键匹配

匹配键：

- WB：优先 `vendor_code`，回退 `nm_id`
- Ozon：优先 `sku_code`，回退 `ozon_sku_id`

摘要卡片全部做环比。

行级可比较字段：

- WB：
  - `sales_qty`
  - `return_qty`
  - `net_qty`
  - `settlement`
  - `delivery`
  - `storage`
  - `ad`
  - `goods_cost`
  - `pre_tax`
  - `tax`
  - `after_tax`
- Ozon：
  - `sales_revenue`
  - `commission`
  - `delivery_charge`
  - `total_ad_cost`
  - `order_count`
  - `net_sales_count`
  - `blr_count`
  - `export_count`
  - `goods_cost`
  - `pre_tax_profit`
  - `after_tax_profit`
  - `after_tax_margin_pct`

未分摊费用也做环比。WR 的 `comparison.extras.unallocated` 可单独挂一个比较节点，避免与普通 rows 混在一起。

### WSU

`Ec::WeeklySummaryQuery` 已有上一周期数据采集能力，但当前只把一小部分“上周值”内联到行里：

- `previous_net_sales`
- `previous_revenue`
- `sales_change_pct`
- `revenue_change_pct`

这套旧字段应移除，统一改成 `comparison.rows` 结构，原因：

- 现在不只是销量和销售额，而是所有适合数字都要环比
- 旧结构会与新统一 comparison 重复

摘要卡片全部做环比。

行级可比较字段：

- `net_sales`
- `revenue`
- `ads`
- `goods_cost`
- `pre_tax`
- `tax`
- `after_tax`
- `margin_pct`

匹配键：

- `[sku, platform, shop]`

### WSU-DEEP

`Ec::WeeklySummaryDeepQuery` 当前已按 SKU 聚合，天然适合做 SKU 级环比。

摘要卡片全部做环比。

行级可比较字段：

- `net_sales`
- `revenue`
- `ads`
- `goods_cost`
- `pre_tax`
- `tax`
- `after_tax`
- `margin_pct`
- `average_profit_per_order`
- `ad_ratio_pct`
- `cost_return_pct`
- `projected_roi_pct`
- `annualized_return_pct`
- `annualized_net_profit_cny`

匹配键：

- `sku`

## 视图设计

### 总体原则

不新增表格列，避免把表横向撑爆；采用“主值 + 次行环比”的模式。

### 摘要卡片

每张卡片显示两行：

1. 当前值
2. 环比信息：箭头 + 百分比 + `vs 上一周期`

示例：

- `¥128,400`
- `↗ 12.4% vs 上一周期`

### 表格单元格

每个可比较数值列显示为两行：

1. 第一行：当前值
2. 第二行：小字号环比信息

示例：

```text
1,280
↗ 8.0%
```

### 颜色规则

- `semantic = positive`：绿色
- `semantic = negative`：红色
- `semantic = neutral`：灰色
- `semantic = none`：灰色 `-`

注意：

- 当前值本身保持默认文本色
- 只有第二行环比信息着色
- 避免整格大面积红绿污染

### 页面说明

在摘要区增加一行说明：

- `环比基准：上一等长自然周范围`

同时在 `comparison.period` 可用时，在辅助文案中展示真实对比日期范围，避免歧义。

## Google Sheet 兼容性

当前阶段不要求 Sheet 立刻展示环比，但查询层会产出统一比较结果。这样后续若要把环比同步到 Google Sheet，可以直接消费同一份 comparison 结构，而不是重新定义：

- 上一周期范围
- 百分比计算
- 好坏语义

这保证了 Web 与 Sheet 的一致性前提仍然成立。

## 风险与取舍

### 多周期查询成本增加

每次 Web 查询都会再取一遍上一周期数据，查询成本约翻倍。

这是有意接受的取舍，因为：

- 当前页面是交互式查询页，不是高频列表轮询
- 相比在前端重复实现逻辑，服务端统一计算更重要

如后续性能显著受影响，再考虑缓存 comparison 结果，但当前设计不提前引入缓存层。

### 行匹配不一定完美

上一周期可能出现：

- 当前有、上期无
- 上期有、当前无
- 标识字段变化

当前策略是：

- 只对当前行寻找上一周期对应项
- 找不到则返回 `none`
- 不额外在表格里展示“已消失行”

这符合“以本期为基准”的需求。

### 比率字段口径

利润率、广告占比、ROI 等字段统一按“相对上一值的百分比变化”算，而不是按百分点变化展示。

原因：

- 所有字段环比口径一致
- 页面展示方式统一

## 测试方案

至少补以下测试：

### Query 层

1. `WR` 会查询上一周期相同店铺结果并生成 `comparison.period`
2. `WSU` 会移除旧的专用 `previous_* / *_change_pct` 行字段，改为统一 comparison
3. `WSU-DEEP` 会为 SKU 聚合结果生成 comparison
4. 上一周期无汇率或无匹配行时，comparison 返回 `none`
5. 收入类字段上升时 `semantic = positive`
6. 成本类字段上升时 `semantic = negative`
7. 当前与上一周期均为 0 时，返回 `flat + neutral`

### Controller / View 层

1. 摘要卡片渲染环比次行
2. 表格数值列渲染主值 + 次行环比
3. 无 comparison 时显示 `-`
4. 页面会展示对比基准说明

### JavaScript / 前端样式

若需要 helper 或局部脚本配合样式切换，则补最小渲染测试；本次不要求前端自行计算 delta。

## 实施结果预期

完成后：

- `WR`、`WSU`、`WSU-DEEP` 都能对当前查询范围自动附带上一周期 comparison
- 页面上所有适合比较的数字都能显示红绿箭头和百分比
- 成本类字段颜色遵循业务好坏而不是数学正负
- Web 与后续 Google Sheet 继续共用同一套数字逻辑，不会再分叉
