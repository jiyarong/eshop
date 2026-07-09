# 周利润归集统一 Web 界面设计

## 背景

当前系统已经有一个 `/weekly_profit_reports` 页面，用于查看店铺级周利润归集（WR）结果，但该页面仍停留在 demo 阶段：

- 筛选模型是 `platform + account_id + from_date + to_date`
- 只支持 WR 视图
- 页面结构可用，但数据模型和交互主轴不适合后续扩展

同时，业务上已经有三类周利润归集结果在 Google Sheet 中长期使用，并且短期内会与 Web 页面共存：

- WR：店铺周利润归集
- WSU：周汇总
- WSU-DEEP：周深度汇总

本次目标不是“再做一套 Web 版数字逻辑”，而是把当前 Google Sheet 所依赖的周利润计算口径抽出来，复用到 Web 页面中，保证共存期内两边数字一致。

## 目标

在现有 `/weekly_profit_reports` 路由基础上升级为统一的周利润归集界面，支持：

- 日期范围筛选
- 归集类型筛选：`WR` / `WSU` / `WSU-DEEP`
- 仅在 `WR` 时要求选择店铺
- 由 `WR` 所选店铺自动决定使用 WB 或 Ozon 利润归集逻辑
- `WSU` / `WSU-DEEP` 不选店铺，直接出跨平台汇总结果

并满足以下约束：

- Web 与 Google Sheet 共享同一套数字逻辑
- 页面仍采用 Rails 自带页面体系：Controller + ERB + Turbo
- JSON 能力保留
- 不在页面请求里触发同步或写库

## 非目标

- 不新增 React/Vite 页面承载层
- 不更换 `/weekly_profit_reports` 页面入口
- 不在本次实现中改造 Google Sheet 写入格式或命名
- 不支持查看当前未结束自然周
- 不支持任意日期区间

## 业务约束

### 日期约束

周利润查询必须同时满足：

- 不能包含当前自然周
- `from_date` 必须是自然周周一
- `to_date` 必须是自然周周日
- 范围长度必须是 7 天的整数倍
- 默认展示上一完整自然周

允许查询单周，也允许查询 2 个或 N 个完整自然周。

### 店铺约束

- `WR` 必须选择店铺
- 店铺列表同时包含 WB 与 Ozon 活跃店铺
- 用户不单独选择平台，平台由所选店铺归属自动决定
- `WSU` / `WSU-DEEP` 不允许也不需要选择店铺

### 数字逻辑约束

- WR 页面复用现有：
  - `Ec::WbProfitAttribution`
  - `Ec::OzonProfitAttribution`
- WSU / WSU-DEEP 页面不能在 controller 里临时再算一套
- Google Sheet 中 `WeeklySummaryService` / `WeeklySummaryDeepService` 使用的行采集、聚合、摘要口径必须抽成共享查询层，供 Web 与 Sheet 共用

## 总体方案

### 继续基于现有页面壳

保留现有 `/weekly_profit_reports`：

- 继续使用当前 page title、筛选区、Turbo Frame 局部刷新、结果区与空态结构
- 继续使用 table 展示 SKU 行数据
- 继续使用卡片展示摘要型信息

不继续沿用现有 controller 的参数模型和结果结构。

### 重做数据模型，不重做入口

本次不另起新页面，而是把 `/weekly_profit_reports` 从“WR demo 页面”升级成“统一周利润归集入口”。

原因：

- 页面壳和交互模式已经合适
- 用户入口不需要迁移
- 可以减少重复页面代码
- 但后端查询分发、参数校验和结果 presenter 需要重构

## 交互设计

### 筛选顺序

页面筛选区按以下顺序展示：

1. 日期范围
2. 归集类型
3. 店铺（仅 `WR` 时显示）
4. 查询按钮

### 日期组件

继续复用现有 `shared/time_range_selector`。

但在 controller 端增加严格校验：

- 非完整自然周范围直接报错
- 包含当前周直接报错

前端不需要阻止所有非法输入，后端必须兜底。

### 归集类型

归集类型选项：

- `WR`
- `WSU`
- `WSU-DEEP`

`WR` 为默认选项。

### 店铺选择

仅当归集类型是 `WR` 时展示店铺下拉框。

店铺下拉框展示格式：

- `WB · 店铺名`
- `Ozon · 店铺名`

请求中统一提交 `store_ref`，由后端解析出平台与账号 ID。  
不再让用户单独选择 `platform`。

### 结果展示

#### WR

结果结构延续当前思路：

- 顶部元信息：店铺名、平台、查询周期
- 摘要卡片
- SKU 明细 table
- 未分摊费用 table

#### WSU

结果结构：

- 顶部元信息：查询周期
- 摘要卡片
- 汇总 table

该 table 对应 `WeeklySummaryService` 的数据行结构，而不是 WR 的 SKU 明细结构。

#### WSU-DEEP

结果结构：

- 顶部元信息：查询周期
- 摘要卡片
- SKU 深度汇总 table

该 table 对应 `WeeklySummaryDeepService` 的聚合后 SKU 结构。

## 后端设计

### 路由

保留现有：

- `GET /weekly_profit_reports`
- `GET /weekly_profit_reports/accounts`

`accounts` 接口继续保留，但返回结构要适配新的单下拉店铺选择方式。

### 请求参数

统一查询参数：

- `from_date`
- `to_date`
- `report_type`
- `store_ref`（仅 `WR` 必填）

其中：

- `report_type` 取值：`wr` / `wsu` / `wsu_deep`
- `store_ref` 建议编码为可逆字符串，例如 `wb:12` 或 `ozon:34`

### 参数校验

controller 增加统一校验：

- 缺少 `report_type`、日期参数时报 `400`
- `report_type=wr` 但缺少 `store_ref` 报 `400`
- `report_type!=wr` 但传入 `store_ref` 可忽略或报错；推荐忽略
- 日期不是 ISO8601 报 `400`
- 日期不满足“周一到周日、7 天整数倍、不含当前周”时报 `422`

### 控制器职责

`WeeklyProfitReportsController` 只负责：

- 解析参数
- 校验筛选条件
- 加载店铺选项
- 根据 `report_type` 分发到对应查询对象
- 选择对应 partial 渲染 HTML
- 返回统一 JSON 结构

controller 不直接承担 WSU / WSU-DEEP 的聚合逻辑。

## 查询层设计

### WR 查询

新增一个轻量查询包装层，例如：

- `Ec::WeeklyProfitReportQuery`

职责：

- 解析 `store_ref`
- 按平台选择：
  - `Ec::WbProfitAttribution`
  - `Ec::OzonProfitAttribution`
- 组装统一返回结构：
  - `report_type`
  - `platform`
  - `account`
  - `period`
  - `rates`
  - `summary`
  - `rows`
  - `unallocated`

### WSU 查询

将 `GoogleSheets::WeeklySummaryService` 中“非写表”部分抽为共享查询对象，例如：

- `Ec::WeeklySummaryQuery`

该对象负责：

- 解析汇率
- 复用 `collect_rows`
- 构建 WSU 行数据
- 构建摘要信息

`GoogleSheets::WeeklySummaryService` 改为依赖这个查询对象来获取行数据和摘要，再负责写表。

Web 侧直接消费该查询对象结果。

### WSU-DEEP 查询

将 `GoogleSheets::WeeklySummaryDeepService` 中“非写表”部分抽为共享查询对象，例如：

- `Ec::WeeklySummaryDeepQuery`

该对象负责：

- 复用 WSU 的底层行采集
- 做按 SKU 聚合
- 构建 deep table 数据
- 构建摘要信息

`GoogleSheets::WeeklySummaryDeepService` 改为依赖该查询对象输出。

## 结果结构设计

### 统一顶层结构

所有类型统一返回：

```json
{
  "success": true,
  "data": {
    "report_type": "wr",
    "period": {
      "from_date": "2026-06-22",
      "to_date": "2026-06-28"
    },
    "meta": {},
    "summary": {},
    "rows": [],
    "extras": {}
  },
  "message": "ok"
}
```

说明：

- `meta` 放店铺、平台、汇率等元信息
- `summary` 放卡片区摘要
- `rows` 放 table 主体数据
- `extras` 放 WR 的未分摊费用等额外区块

这样 controller 和 view 可按 `report_type` 走不同 presenter，但仍保留统一 JSON 外壳。

## 视图设计

### 主页面

继续使用：

- `app/views/weekly_profit_reports/show.html.erb`

但重做筛选区：

- 删除平台选择
- 新增归集类型选择
- 店铺框改成单下拉，并按类型显隐

页面上的展示文案全部进入 I18n。

### 结果 partial

将现有 `_results.html.erb` 拆为按类型渲染的 partial，例如：

- `_wr_results.html.erb`
- `_wsu_results.html.erb`
- `_wsu_deep_results.html.erb`
- `_summary_cards.html.erb`

顶层结果 partial 只做分发。

这样可以避免一个 partial 内堆太多 `if report_type == ...`。

## 店铺选项接口

`GET /weekly_profit_reports/accounts` 建议返回扁平化结构：

```json
{
  "success": true,
  "data": [
    { "ref": "wb:1", "platform": "wb", "name": "WB 店铺名", "label": "WB · WB 店铺名" },
    { "ref": "ozon:2", "platform": "ozon", "name": "Ozon 店铺名", "label": "Ozon · Ozon 店铺名" }
  ],
  "message": "ok"
}
```

HTML 首屏也可直接由 controller 预载这些店铺，避免必须依赖前端异步请求。

## 错误处理

### HTML

- 参数错误：返回错误 partial
- 无汇率：返回错误 partial
- 店铺不存在：返回错误 partial
- 查询异常：返回错误 partial

### JSON

继续返回：

- `success: false`
- `message`

状态码区分：

- `400 Bad Request`
- `404 Not Found`
- `422 Unprocessable Entity`
- `500 Internal Server Error`

## 测试方案

### Controller 测试

扩展 `test/controllers/weekly_profit_reports_controller_test.rb`，覆盖：

- HTML 首屏渲染新的筛选字段
- `WR` 请求要求 `store_ref`
- `WSU` / `WSU-DEEP` 请求不要求店铺
- 非完整自然周范围返回 `422`
- 当前周范围返回 `422`
- `WR` 能按 `store_ref` 分发到 WB 或 Ozon 查询
- `WSU` / `WSU-DEEP` 返回对应结构

### 查询层测试

新增服务测试：

- `Ec::WeeklyProfitReportQuery`
- `Ec::WeeklySummaryQuery`
- `Ec::WeeklySummaryDeepQuery`

重点验证：

- Web 和 Google Sheet 共用同一套行数据/摘要逻辑
- 查询对象返回结构稳定
- `WSU-DEEP` 的聚合和 summary 不偏离现有 sheet 逻辑

### 现有服务回归测试

如果抽取共享查询层，需要补或调整：

- `test/services/google_sheets/weekly_profit_report_runner_test.rb`
- `test/services/google_sheets/weekly_summary_deep_service_test.rb`

确保写表服务改成依赖共享查询对象后，原有输出口径不变。

## 验收标准

- 用户进入 `/weekly_profit_reports` 后，可先选日期、再选归集类型、按需选店铺
- `WR` 选择 WB 或 Ozon 店铺后，可得到对应店铺周利润结果
- `WSU` / `WSU-DEEP` 无需店铺即可直接出结果
- 页面使用 table 展示行数据，使用卡片展示摘要信息
- 日期范围严格限制为已完成自然周或多个完整自然周
- Web 与 Google Sheet 共用同一套数字逻辑，不新增第二套口径
