# 周利润报表 Web 版设计

## 背景

当前项目通过 `GoogleSheets::WbWeeklyReportService` 和 `GoogleSheets::OzonWeeklyReportService` 将周利润报表写入 Google Sheet 的 `WR:` tab。报表数据的核心计算已在 Rails 服务中完成：

- WB：`Ec::WbProfitAttribution`
- Ozon：`Ec::OzonProfitAttribution`

第一版 Web 界面只解决「方便查看周利润报表」这一目标，复用现有计算结果，不替代 Google Sheet 写入流程。

## 目标

新增一个只读的周利润报表页面，用户可以选择平台、店铺和日期范围，查看与 `WR:` Sheet 对应的核心信息：

- 汇总指标
- SKU 利润明细
- 未分摊费用

## 非目标

第一版不做以下能力：

- 不写回 Google Sheet。
- 不编辑 SKU 成本、平台成本、汇率或店铺信息。
- 不展示订单明细报表（`WOD:` / `OD:`）。
- 不主动触发平台数据同步。
- 不新增复杂图表或历史趋势分析。

## 后端设计

### 路由

新增两个只读接口：

```text
GET /weekly_profit_reports/accounts
GET /weekly_profit_reports
```

### 店铺接口

`GET /weekly_profit_reports/accounts` 返回可用于筛选的活跃店铺。

响应结构：

```json
{
  "success": true,
  "data": {
    "wb": [
      { "id": 1, "name": "WB 店铺名" }
    ],
    "ozon": [
      { "id": 1, "name": "Ozon 店铺名" }
    ]
  },
  "message": "ok"
}
```

数据来源：

- WB：`RawWb::SellerAccount.where(is_active: true)`
- Ozon：`RawOzon::SellerAccount.where(is_active: true)`

### 报表接口

`GET /weekly_profit_reports` 接收以下参数：

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `platform` | string | 是 | `wb` 或 `ozon` |
| `account_id` | integer | 是 | 店铺 ID |
| `from_date` | string | 是 | 开始日期，格式 `YYYY-MM-DD` |
| `to_date` | string | 是 | 结束日期，格式 `YYYY-MM-DD` |

服务选择：

- `platform=wb`：调用 `Ec::WbProfitAttribution`
- `platform=ozon`：调用 `Ec::OzonProfitAttribution`

WB 需要 `rate_cny_rub` 和 `rate_byn_rub`，Ozon 需要 `rate_cny_rub`。接口根据 `from_date.beginning_of_week` 调用 `Ec::WeeklyRate.resolve` 获取汇率。缺少汇率时返回 `422 Unprocessable Entity`，提示当前周期没有汇率。

响应结构：

```json
{
  "success": true,
  "data": {
    "platform": "wb",
    "account": { "id": 1, "name": "WB 店铺名" },
    "period": { "from_date": "2026-05-18", "to_date": "2026-05-24" },
    "rates": { "rate_cny_rub": 10.93, "rate_byn_rub": 26.41 },
    "summary": {},
    "rows": [],
    "unallocated": {}
  },
  "message": "ok"
}
```

`summary`、`rows` 和 `unallocated` 保留现有服务的字段命名，避免重新定义一套与 Google Sheet 不一致的计算口径。

### 错误处理

- 参数缺失或日期格式错误：返回 `400 Bad Request`。
- 平台不支持：返回 `400 Bad Request`。
- 店铺不存在或未启用：返回 `404 Not Found`。
- 汇率缺失：返回 `422 Unprocessable Entity`。
- 计算异常：返回 `500 Internal Server Error`，记录 Rails 日志。

## 前端设计

### 路由

新增页面：

```text
/reports/weekly-profit
```

默认首页跳转到该页面，顶部导航增加「报表」入口。

### 页面结构

页面使用现有 React + TypeScript + Ant Design 技术栈。

顶部筛选区：

- 平台选择：WB / Ozon。
- 店铺选择：根据平台切换店铺列表。
- 日期范围：开始日期、结束日期。
- 查询按钮。

汇总区：

- WB：展示销售件数、退货件数、账面小计、货物成本、税前利润、税额、税后净利、未分摊行数。
- Ozon：展示 SKU 数、销售收入、订单数、退货数、广告费、货物成本、税后净利、未分摊合计。

SKU 明细表：

- WB 列：`nm_id`、`vendor_code`、`region`、`sales_qty`、`return_qty`、`net_qty`、`settlement`、`delivery`、`storage`、`ad`、`goods_cost`、`pre_tax`、`tax`、`after_tax`。
- Ozon 列：`ozon_sku_id`、`sku_code`、`sales_revenue`、`commission`、`delivery_charge`、`total_ad_cost`、`order_count`、`net_sales_count`、`blr_count`、`export_count`、`goods_cost`、`pre_tax_profit`、`after_tax_profit`、`after_tax_margin_pct`。

未分摊费用区：

- WB：展示 `unallocated` 中的项目和金额。
- Ozon：展示 `unallocated.rows` 的 `type_id`、`type_name`、`posting_number` 和 `amount`。

### 页面状态

必须处理以下状态：

- 首次进入：展示筛选区和空态。
- 查询中：显示加载状态。
- 无数据：显示空表格和提示。
- 错误：显示接口返回的错误消息。

## 测试方案

### 后端

新增 controller 测试，覆盖：

- 店铺接口返回 WB 和 Ozon 活跃店铺。
- 缺少必填参数返回 `400`。
- 不支持的平台返回 `400`。
- 缺少汇率返回 `422`。
- WB 请求成功时返回 `summary`、`rows` 和 `unallocated`。
- Ozon 请求成功时返回 `summary`、`rows` 和 `unallocated`。

服务计算本身已有独立实现，本次不重写利润归因单元测试。

### 前端

第一版以构建验证为主：

- `pnpm build` 通过。
- 页面 TypeScript 类型检查通过。
- 本地打开页面后可以完成一次查询并展示数据、空态或错误态。

## 验收标准

- 用户可以在 Web 页面选择平台、店铺和日期范围。
- 页面能展示与现有 `WR:` Sheet 对应的汇总、SKU 明细和未分摊费用。
- 后端错误有明确 JSON 响应，前端能展示错误信息。
- 不影响现有 Google Sheet 写入服务。
- 后端测试通过，前端构建通过。
