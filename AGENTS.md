# AGENTS.md

本文件记录本项目当前业务上下文和实现约束，供后续 Agent 进入仓库时快速对齐。通用行为规范仍以会话系统指令和用户最新要求为准。

## 项目定位

这是一个电商经营数据管理项目，后端使用 Rails 8。项目会从 WB、Ozon 等平台同步原始数据，经过 `Ec::*` 
## 后端开发
- 不要直接创建migration文件，而是使用rails generate migration命令生成migration文件，确保文件名和类名一致。
- 本项目本地 Web 默认端口为 `4010`, 开发完成后不需要打开网页帮我验证，直接运行 Rails 测试即可。

## 前端方向
- 实现功能后不需要帮我运行yarn build或vite build等前端构建命令，除非用户明确要求。
- 新报表页面使用 Rails 自带页面体系：Controller + ERB + Turbo/Hotwire 风格交互。
- 当前 Rails 项目是 `api_only` 配置，但已经通过 `ApplicationController` 支持明确的 HTML 请求。
- JSON API 仍要保留 `.json` 路径能力，避免破坏已有接口测试和后续集成。
- 页面上展示给用户看的文本都应通过 Rails I18n 管理，不要在 ERB、helper、controller 或前端脚本中新增硬编码展示文案。
- 现有页面布局在 `app/views/layouts/application.html.erb`

## 当前报表现状

- 报表导航当前包含：
  - `/weekly_profit_reports`
  - `/reports/inventory`
  - `/reports/skus`
  - `/reports/costs`
- 新报表优先继续走 Rails 页面，不要新开 React/Vite 报表承载层。

### 库存报表

- 入口：`GET /reports/inventory`
- 详情入口：`GET /reports/inventory/:sku_code`
- 当前页面读取链路：
  - 列表页：`ReportsController#inventory` + `Ec::InventoryPageRowQuery`
  - 详情页：`ReportsController#inventory_detail` + `Ec::InventoryPageDetailQuery`
  - SKU 汇总：`Ec::SkuInventoryOverview`
- 当前库存基础表：
  - `ec_sku_inventory_levels` / `Ec::SkuInventoryLevel`
  - `ec_sku_batches` / `Ec::SkuBatch`
  - `ec_order_items`、`ec_orders`
  - `raw_wb_goods_returns`、`raw_ozon_returns`
  - `raw_wb_supply_items`、`raw_ozon_supply_orders`
- 平台库存快照刷新：
  - 定时任务：`config/recurring.yml` 中的 `Ec::SkuInventorySnapshotSync.run`
  - 频率：生产每小时一次
  - 写入方式：抓平台当前库存后写入 `Ec::SkuInventoryLevel`，并维护 `is_latest`
- 页面查询约束：
  - `/reports/inventory` 和详情页 GET 请求保持只读
  - 不要在页面请求里直接调平台 API
  - 不要在页面请求里触发同步、写库或补数据
- 旧机制状态：
  - `Ec::InventorySnapshot`
  - `Ec::InventoryTotal`
  - `Ec::InventorySnapshotSync`
  - `GoogleSheets::InventorySnapshotWriteService`
  - `GoogleSheets::InventorySnapshotImportService`
  - `Ec::OperationTaskGenerator`
  - 以上整套旧库存快照/汇总机制已从项目移除，不应再作为当前实现参考

## 生产部署

- 生产部署使用 Kamal：`kamal deploy -c config/deploy.yml`。
- Kamal 配置文件是 `config/deploy.yml`，镜像构建使用根目录 `Dockerfile`。
- 不要把 `config/deploy.rb`（Mina）当作当前生产部署入口；排查 production 部署、镜像、assets 问题时优先看 Kamal 配置和 Dockerfile。
- production 缺少 Rails assets（例如 Propshaft 报 `application.js` missing）时，应检查 Docker image 构建阶段是否安装 Node 依赖并执行 `assets:precompile`，以及最终镜像内是否包含 `public/assets/.manifest.json` 和对应 digest 资源。

除非用户明确要求，Agent 不需要也不应主动启动 Web server，不主动运行 `npm run build`、`npm run build:css`、`vite build` 等前端构建命令；这些由用户自行运行。需要验证时，优先运行相关 Rails 测试，或在最终说明中明确列出未运行的前端构建。

## 数据与测试注意事项

- `test/test_helper.rb` 中 `use_transactional_tests = false`，测试必须清理自己创建的数据。
- 新测试数据尽量使用唯一 SKU 或唯一 token，避免中断后残留数据导致唯一索引冲突。
- 工作区经常存在无关脏改动，例如 `.idea/`、`config/database.yml`、根目录 `node_modules/`、`docs/` 临时文件、`yarn.lock`。不要回滚或提交这些无关改动。
- 提交时只 `git add` 本次任务相关路径。

## 订单与 SKU 关联策略

- 订单报表、库存销量、SKU 销量等统计逻辑不要用 `ec_order_items.sku_code` 作为 SKU 归属依据。
- SKU 与订单商品的归属应从 `ec_sku_products` 硬关联：
  - 先通过 `ec_sku_products.sku_code` 确定内部 SKU。
  - 必须同时限定 `ec_sku_products.store_id = ec_order_items.store_id` 和 `ec_sku_products.platform = ec_order_items.platform`。
  - Ozon 使用 `ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id`。
  - WB 使用 `ec_sku_products.product_id = ec_order_items.platform_sku_id`。
- `ec_order_items.sku_code` 可能由导入流程写入，但只能作为冗余展示/排查线索；报表统计不能用它兜底匹配，避免未绑定或误绑定商品被算入 SKU。
- `offer_id` 不参与订单到 SKU 的报表统计归属匹配，除非后续业务明确重新定义绑定规则。

## 时间展示策略

- 用户资料使用 `users.time_zone` 保存时间展示时区，默认值是 `Asia/Shanghai`。
- Rails 页面展示业务时间时优先使用 `display_time(...)` helper，不要在 ERB 中直接 `strftime`。
- `display_time(...)` 按当前用户所选时区渲染，空值统一展示为 `-`，默认格式为 `%Y-%m-%d %H:%M`。
- 与日期筛选边界相关的页面逻辑，应使用同一用户时区计算当天起止时间，避免筛选日期与表格展示日期不一致。
