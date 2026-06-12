# SKU 详情页设计规格

## 目标

新增一个只读 SKU 详情页，把单个 SKU 的基础配置、成本测算、各店铺销量和历史销量趋势集中展示，减少用户在 SKU 主数据、成本报表、销量统计页面之间来回切换。

## 范围

第一版只做 Rails 原生网页展示，不做编辑、导入、导出、写回或触发同步。

建议路由：

- `GET /reports/skus/:sku_code`

建议入口：

- `/reports/skus` 的 SKU 编码跳转到详情页。
- 详情页提供返回 SKU 列表和跳转 ERP 编辑页的链接。

ERP 的 `/erp/skus/:id` 继续承担 SKU 维护入口，避免把经营查看和主数据维护混在一起。

## 页面整体结构

页面顶部展示 SKU 概览，不放入 tab：

- SKU 编码
- 中文商品名
- 俄文商品名
- 上架状态
- 类目
- 主 SKU
- 负责人
- 最近 30 天净销量
- 最近 30 天销售额
- 最近 30 天退货数
- 涉及店铺数

概览下方展示 4 个 tab：

1. 基础配置
2. 成本情况
3. 各店铺销量情况
4. 销量历史趋势

tab 第一版使用普通链接或 GET 参数切换，例如 `?tab=costs`。默认 tab 为 `basic`。本规格不包含 Turbo Frame 局部刷新。

## Tab 1：基础配置

展示 SKU 静态资料和店铺上架配置。

基础信息：

- SKU 编码
- 中文商品名
- 俄文商品名
- 类目
- 主 SKU
- 上架状态
- 创建时间
- 更新时间

商品属性：

- 颜色
- 规格
- 尺寸
- 重量 kg
- 体积 L
- 型号
- 品质
- 特点

管理信息：

- 负责人
- 备注

店铺上架配置表：

- 平台
- 店铺
- 是否启用
- 外部 ID
- 上架日期
- 负责人

数据来源：

- `Ec::Sku`
- `Ec::MasterSku`
- `Ec::SkuCategory`
- `Ec::SkuStoreAssignment`

## Tab 2：成本情况

展示 SKU 基础成本和平台测算成本。字段优先复用现有成本报表和 `Ec::SkuPlatformCost` 的计算方法。

SKU 基础成本：

- 采购价 CNY
- 到白俄运费 CNY
- 清关杂费 CNY
- 关税额 CNY
- 进口增值税 CNY
- 货物总成本 CNY
- 包装尺寸
- 升量 L
- 杂费 CNY
- 货损率

WB 成本表：

- 配送模式
- 公司类型
- 目标售价 RUB
- 收入 CNY
- 平台运费 CNY
- 广告费 CNY
- 最终成本 CNY
- 利润 CNY
- 利润率

Ozon 成本表：

- 配送模式
- 公司类型
- 俄罗斯售价 RUB
- 白俄售价 RUB
- 俄罗斯收入 CNY
- 白俄收入 CNY
- 平台运费 CNY
- 俄罗斯最终成本 CNY
- 白俄最终成本 CNY
- 俄罗斯利润 CNY
- 白俄利润 CNY

展示规则：

- 缺失成本时显示空状态，不报错。
- 利润为负时使用醒目的负数样式。
- 成本计算只读取数据库已有数据，不触发导入或同步。

数据来源：

- `Ec::SkuCost`
- `Ec::SkuPlatformCost`

## Tab 3：各店铺销量情况

展示当前 SKU 在不同店铺的横向表现。

默认筛选：

- 时间范围：最近 30 天
- 平台：全部
- 店铺：全部

筛选项：

- 开始日期
- 结束日期
- 平台
- 店铺

汇总卡片：

- 销售件数
- 退货件数
- 净销量
- 订单数
- 销售额
- 均价

店铺销量表按平台和店铺聚合：

- 平台
- 店铺
- 销售件数
- 退货件数
- 净销量
- 订单数
- 销售额
- Payout
- 佣金
- 折扣
- 均价
- 履约模式
- 最近出单时间

数据口径：

- SKU 匹配沿用现有 `/reports/sku_sales` 逻辑：匹配 `ec_order_items.sku_code` 或 `ec_order_items.offer_id`。
- `returned` 订单计入退货件数，不计入销售件数。
- 净销量等于销售件数减退货件数。

数据来源：

- `Ec::OrderItem`
- `Ec::Order`
- `Ec::OrderFulfillment`
- `Ec::Store`

## Tab 4：销量历史趋势

展示当前 SKU 的销量和销售额时间变化。

默认筛选：

- 时间范围：最近 90 天
- 周期：日
- 维度：店铺

筛选项：

- 开始日期
- 结束日期
- 周期：日、周、月
- 维度：店铺、平台、汇总

图表：

- 净销量折线
- 销售额折线

明细表：

- 周期
- 平台
- 店铺
- 销售件数
- 退货件数
- 净销量
- 订单数
- 销售额
- Payout
- 佣金
- 折扣
- 均价
- 履约模式

数据口径与各店铺销量情况保持一致。

## 控制器与视图建议

建议在 `ReportsController` 增加 `sku_detail` action，保持现有报表页面集中在一个 controller。

建议新增或修改：

- `config/routes.rb`
- `app/controllers/reports_controller.rb`
- `app/views/reports/sku_detail.html.erb`
- `app/views/reports/skus.html.erb`
- `test/controllers/reports_controller_test.rb`

视图风格沿用现有报表页面：

- 使用 `panel`
- 表格使用 `table-scroll`
- 汇总指标使用 `summary-grid`
- 页面保持密集、可扫描
- 字段较多的表格允许横向滚动

## 权限

沿用报表权限：

- `require_permission!(:view_reports)`

编辑链接跳转 ERP 页面时，仍由 ERP controller 自己校验管理权限。

## 空状态与异常

- SKU 不存在时返回 404。
- 没有成本数据时显示“暂无成本数据”。
- 没有销量数据时显示“当前筛选范围内没有订单数据”。
- 日期参数非法时回退默认日期范围。
- tab 参数非法时回退 `basic`。

## 测试验收

Controller integration test 覆盖：

- SKU 列表页的 SKU 编码链接到详情页。
- 详情页默认展示基础配置 tab。
- 成本 tab 展示 SKU 基础成本、WB 成本和 Ozon 成本。
- 店铺销量 tab 按店铺展示当前 SKU 数据，不混入其他 SKU。
- 趋势 tab 按周期展示当前 SKU 数据。
- 不存在的 SKU 返回 404。
- 非法日期参数不会报错，并回退默认范围。

建议运行：

```bash
rbenv exec ruby bin/rails test test/controllers/reports_controller_test.rb
```
