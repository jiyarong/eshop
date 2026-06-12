# AGENTS.md

本文件记录本项目当前业务上下文和实现约束，供后续 Agent 进入仓库时快速对齐。通用行为规范仍以会话系统指令和用户最新要求为准。

## 项目定位

这是一个电商经营数据管理项目，后端使用 Rails 8。项目会从 WB、Ozon 等平台同步原始数据，经过 `Ec::*` 服务聚合后，原先主要写入 Google Sheets 供人工查看。

当前目标是逐步把 Google Sheets 输出内容迁移为 Rails 原生网页展示，减少对 Sheet 页面查看的依赖。

## 前端方向

- 不要继续新增 `frontend/` 下的 React/Vite 页面来承载新报表。
- 新报表页面使用 Rails 自带页面体系：Controller + ERB + Turbo/Hotwire 风格交互。
- 当前 Rails 项目是 `api_only` 配置，但已经通过 `ApplicationController` 支持明确的 HTML 请求。
- JSON API 仍要保留 `.json` 路径能力，避免破坏已有接口测试和后续集成。
- 现有页面布局在 `app/views/layouts/application.html.erb`，报表导航已经包含：
  - `/weekly_profit_reports`：周利润报表
  - `/reports/inventory`：库存
  - `/reports/skus`：SKU
  - `/reports/costs`：成本

## 已落地的网页报表

### 周利润报表

入口：`GET /weekly_profit_reports`

相关文件：

- `app/controllers/weekly_profit_reports_controller.rb`
- `app/views/weekly_profit_reports/show.html.erb`
- `app/views/weekly_profit_reports/_results.html.erb`
- `app/views/weekly_profit_reports/_error.html.erb`
- `test/controllers/weekly_profit_reports_controller_test.rb`

业务逻辑：

- WB 使用 `Ec::WbProfitAttribution`。
- Ozon 使用 `Ec::OzonProfitAttribution`。
- Web 查询必须保持只读：
  - 汇率使用 `Ec::WeeklyRate.find_by(...)`，不要在 GET 查询中调用 `resolve` 自动拉取或写入。
  - Ozon Web 查询传入 `sync_missing_ad_costs: false`，避免 GET 请求补同步广告费。
- JSON 接口保留：
  - `GET /weekly_profit_reports/accounts`
  - `GET /weekly_profit_reports.json`

### 库存报表

入口：`GET /reports/inventory`

相关文件：

- `app/controllers/reports_controller.rb`
- `app/views/reports/inventory.html.erb`
- `test/controllers/reports_controller_test.rb`

数据来源：

- `Ec::InventorySnapshot`
- `Ec::InventoryTotal`
- `Ec::Sku`

展示内容：

- 店铺库存：SKU、商品名、平台、店铺、库存、送仓、售出、FBS、同步时间。
- 库存汇总：总入库、总送仓、总库存、总售出、FBS 总计、白俄仓推算、总可售。

### SKU 主数据

入口：`GET /reports/skus`

数据来源：

- `Ec::Sku`

展示内容：

- SKU 编码、中文商品名、俄文商品名、是否上架。

### 成本报表

入口：`GET /reports/costs`

数据来源：

- `Ec::SkuCost`
- `Ec::SkuPlatformCost`
- `Ec::Sku`

展示内容：

- SKU 成本：采购价、运费、清关、关税、进口增值税、货物总成本、升量、杂费、货损率。
- WB 成本：配送模式、公司类型、目标售价、收入、平台运费、广告费、最终成本、利润、利润率。
- Ozon 成本：俄罗斯/白俄售价、收入、平台运费、最终成本、利润。

第一版只读展示，不做编辑、导入、写回。

## Google Sheets 输出服务分组

优先迁移为网页展示的服务：

- `GoogleSheets::InventorySnapshotWriteService` → `/reports/inventory`
- `GoogleSheets::SkuSheetService` → `/reports/skus`
- `GoogleSheets::CostSheetWriteService` → `/reports/costs`
- `GoogleSheets::WbWeeklyReportService` / `GoogleSheets::OzonWeeklyReportService` → 已由 `/weekly_profit_reports` 覆盖核心利润视图，后续可继续增强分节展示。
- `GoogleSheets::WbOrderDetailSheetService` / `GoogleSheets::OzonOrderDetailSheetService` → 后续适合新增订单明细页面，按平台、店铺、周期筛选。

暂不优先迁移：

- `GoogleSheets::WeeklyReportService`：早期 `auto-*` 周报，含硬编码店铺/SKU 列表，除非用户确认仍在使用。
- `GoogleSheets::*ImportService`：属于从 Sheet 回写数据库的维护流程，不等同于只读网页报表。

## 测试与验证

本项目本地 Web 默认端口为 `4010`。

## 生产部署

- 生产部署使用 Kamal：`kamal deploy -c config/deploy.yml`。
- Kamal 配置文件是 `config/deploy.yml`，镜像构建使用根目录 `Dockerfile`。
- 不要把 `config/deploy.rb`（Mina）当作当前生产部署入口；排查 production 部署、镜像、assets 问题时优先看 Kamal 配置和 Dockerfile。
- production 缺少 Rails assets（例如 Propshaft 报 `application.js` missing）时，应检查 Docker image 构建阶段是否安装 Node 依赖并执行 `assets:precompile`，以及最终镜像内是否包含 `public/assets/.manifest.json` 和对应 digest 资源。

除非用户明确要求，Agent 不需要也不应主动启动 Web server，不主动运行 `npm run build`、`npm run build:css`、`vite build` 等前端构建命令；这些由用户自行运行。需要验证时，优先运行相关 Rails 测试，或在最终说明中明确列出未运行的前端构建。

Rails 测试优先使用：

```bash
rbenv exec ruby bin/rails test test/controllers/weekly_profit_reports_controller_test.rb
rbenv exec ruby bin/rails test test/controllers/reports_controller_test.rb
```

如果同时验证已落地报表页面：

```bash
rbenv exec ruby bin/rails test test/controllers/reports_controller_test.rb test/controllers/weekly_profit_reports_controller_test.rb
```

前端 React/Vite 不是新报表方向，但如果改动了 `frontend/` 相关文件，需要至少运行：

```bash
cd frontend
./node_modules/.bin/tsc -b
./node_modules/.bin/vite build
```

当前本机 Node 版本可能低于 Vite 建议版本，`vite build` 可能输出 Node 版本和 chunk 大小警告；只要 exit 0，可视为构建通过。

## 数据与测试注意事项

- `test/test_helper.rb` 中 `use_transactional_tests = false`，测试必须清理自己创建的数据。
- 新测试数据尽量使用唯一 SKU 或唯一 token，避免中断后残留数据导致唯一索引冲突。
- 工作区经常存在无关脏改动，例如 `.idea/`、`config/database.yml`、根目录 `node_modules/`、`docs/` 临时文件、`yarn.lock`。不要回滚或提交这些无关改动。
- 提交时只 `git add` 本次任务相关路径。

## 实现风格

- 变更保持小而直接，优先复用现有 `Ec::*` 业务服务和数据库模型。
- GET 页面查询应保持只读，不触发同步、拉取外部数据或写库。
- 页面以密集、可扫描的运营工具风格为主，不做营销式首页。
- 表格可横向滚动，字段多时不要强行压缩到一屏。
- 新增报表优先写 controller integration test，再实现页面。

## 时间展示策略

- 用户资料使用 `users.time_zone` 保存时间展示时区，默认值是 `Asia/Shanghai`。
- Rails 页面展示业务时间时优先使用 `display_time(...)` helper，不要在 ERB 中直接 `strftime`。
- `display_time(...)` 按当前用户所选时区渲染，空值统一展示为 `-`，默认格式为 `%Y-%m-%d %H:%M`。
- 与日期筛选边界相关的页面逻辑，应使用同一用户时区计算当天起止时间，避免筛选日期与表格展示日期不一致。
