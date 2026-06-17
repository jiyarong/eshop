# 电商管理平台 — CLAUDE.md

## 项目概述

公司自营商品，在多个电商平台上架的管理后台。

---

## 核心架构设计

### 两层数据模型

```
第一层：平台原始数据（raw_*）
    raw_wb_*    — Wildberries 平台原始数据
    raw_ozon_*  — Ozon 平台原始数据（已完成）
    raw_xxx_*   — 未来其他平台

第二层：电商核心模型（ec_*，命名空间 Ec::）
    ec_orders        — 核心订单（聚合自各平台）
    ec_order_items   — 订单明细
    ec_products      — 核心商品
    ec_skus          — 核心 SKU
    ...
```

### 设计原则

1. **原始层（raw_*）镜像平台数据**：`raw_*` 表的职责是忠实保存各平台 API 返回的原始数据，定期 sync 保持与平台一致。不做业务逻辑，只做格式标准化（编码、时区）。

2. **核心层（ec_*）屏蔽平台差异**：`Ec::` 命名空间下的模型是业务层真正使用的数据，由各平台的 raw 数据 ETL 聚合而来。核心层不直接调用平台 API。

3. **单向数据流**：平台 API → raw_* → ETL → ec_*。核心层数据只从 raw 层聚合，不反向写回平台（写回由专用 action 处理）。

4. **平台字段保留**：ec_* 表保留 `platform`（`'wildberries'`/`'ozon'`）和 `external_id`（平台侧的唯一 ID）两个字段，方便溯源。

### WB 订单映射示例

WB 订单模型特殊：1条 `raw_wb_orders` 记录 = 1件商品（不是传统 1订单N商品）。

```
raw_wb_orders（按 order_uid 聚合）  →  ec_orders（一次购物）
raw_wb_orders（按 order_uid + chrt_id 分组，COUNT=数量）  →  ec_order_items
```

`order_uid` 是 WB 实时 API 的篮子级 ID；`g_number` 是统计 API 的同义字段，通过 srid 关联回填到 `raw_wb_orders.g_number`。

---

## 目录结构

```
ecommerce_manage/
├── app/
│   ├── models/
│   │   ├── raw_wb/        # RawWb:: 命名空间（WB 原始数据）
│   │   ├── raw_ozon/      # RawOzon:: 命名空间（Ozon 原始数据）
│   │   └── ec/            # Ec:: 命名空间（核心业务模型）
│   │       ├── sku.rb                      # SKU 主表
│   │       ├── sku_store_assignment.rb     # SKU 在各店铺的上架记录
│   │       ├── sku_cost.rb                 # 货物基础成本（采购/运费/关税）
│   │       ├── sku_platform_cost.rb        # 平台成本参数 + 计算方法
│   │       ├── inventory_snapshot.rb       # 库存快照（每店铺每SKU）
│   │       └── inventory_total.rb          # 库存汇总（每SKU，含手填total_received）
│   ├── services/
│   │   ├── raw_wb/        # WB sync 服务（BaseSync/DailySync/WeeklySync/SetupSync）
│   │   ├── raw_ozon/      # Ozon sync 服务（OzonClient/BaseSync + 18 个 Syncs 模块）
│   │   ├── ec/            # ETL 服务
│   │   │   ├── inventory_snapshot_sync.rb  # 聚合 WB+Ozon 写快照表
│   │   │   ├── wb_inventory_summary.rb     # WB 库存汇总（barcode→nm_id JOIN）
│   │   │   └── ozon_inventory_summary.rb   # Ozon 库存汇总
│   │   └── google_sheets/ # Google Sheets 读写服务
│   │       ├── base_service.rb                      # 认证基类（Service Account）
│   │       ├── sku_import_service.rb                # 从 Sheet 导入 SKU 和店铺分配
│   │       ├── sku_sheet_service.rb                 # SKU 数据写回 Sheet
│   │       ├── inventory_snapshot_write_service.rb  # 库存快照写 Sheet（"Inventory" Tab）
│   │       └── inventory_snapshot_import_service.rb # 从 Sheet 回写 total_received
│   └── controllers/
│       └── raw_wb/        # RawWb:: API 控制器
├── config/routes.rb
├── db/migrate/
├── test/
│   ├── test_helper.rb
│   └── models/ec/
│       └── sku_platform_cost_test.rb  # 45 个成本计算单元测试
├── frontend/              # React + TypeScript 前端
├── wb_documents/          # WB API 调研文档
│   ├── markdowns/         # 各模块接口文档 + db_schema.md
│   └── test_api.py
└── ozon_documents/        # Ozon API 调研文档
    ├── markdowns/         # 15 个接口文档 + db_schema.md
    ├── raw_spec.json      # 完整 OpenAPI spec（369 endpoints）
    ├── test_api.py        # 接口连通性测试（15 通过 / 3 失败）
    └── test_sync.rb       # Rails sync 全流程测试脚本
```

---

## 后端（Rails 8 API）

### 运行
```bash
rails server -p 4010
```

### 关键约定
- 平台原始数据表名加平台前缀：`raw_wb_`、`raw_ozon_`，model 用 `self.table_name =` 声明
- 核心模型表名加 `ec_` 前缀，命名空间 `Ec::`
- 所有 controller 继承 `RawWb::BaseController`（核心层将继承 `Ec::BaseController`）
- jbuilder 响应格式固定为：
  ```ruby
  json.success true
  json.data do
    # ...
  end
  json.message @message || 'ok'
  ```
- `ApplicationController` 需包含三个模块才能在 API mode 使用 jbuilder：
  ```ruby
  include ActionView::Rendering
  include ActionController::ImplicitRender
  include ActionController::MimeResponds
  before_action { request.format = :json }
  ```
- 分页使用 kaminari：`@records.page(params[:page]).per(params[:per_page] || 20)`

### 迁移文件
| 文件 | 内容 |
|------|------|
| 000001 | platforms, seller_accounts |
| 000002 | categories, subjects |
| 000003 | products, product_skus |
| 000004 | product_prices, warehouses, stocks |
| 000005 | orders, supplies |
| 000006 | ad_campaigns, promotions |
| 000007 | analytics_sales_funnels, analytics_search_terms |
| 000008 | reviews, questions, chats, chat_messages, return_claims |
| 000009 | account_balances, sales_reports, sync_tasks |
| 20260509_000001 | ec_skus（SKU主表，sku_code 为主键） |
| 20260509_000002 | ec_sku_costs（货物基础成本） |
| 20260509_000003 | ec_sku_platform_costs（平台成本参数） |
| 20260509_000004 | ec_skus 加 product_name_ru 字段 |
| 20260509_000005 | ec_sku_store_assignments（SKU店铺分配） |
| 20260511_000001 | ec_sku_costs 加 pkg_volume_override_l（Ozon 直填升量） |
| 20260511_000002 | ec_sku_platform_costs 加 Ozon 运费参数 + 双市场售价字段 |
| 20260519000002 | ec_inventory_snapshots（库存快照，唯一键 sku_code+platform+account_id） |
| 20260519000003 | ec_inventory_totals（库存汇总，唯一键 sku_code，含手填 total_received） |

### 路由特殊说明
- `product_skus` / `product_prices` 嵌套在 `products` 下，`shallow: true`
- `return_claims` 嵌套在 `orders` 下（`shallow: true`），同时有顶层 `only: [:index]` 路由供前端列表页使用
- `chat_messages` 嵌套在 `chats` 下，`shallow: true`

---

## 前端（React + TypeScript + Vite）

### 运行
```bash
cd frontend
pnpm dev        # 开发（含代理）
pnpm build      # 生产构建
```

### 包管理：pnpm（不用 npm）

### 代理配置（vite.config.ts）
`/api` → `http://127.0.0.1:4010`，rewrite 去掉 `/api` 前缀。
用 `127.0.0.1` 而非 `localhost`，避免 Node IPv6/IPv4 双栈 ECONNREFUSED。

### 目录结构
```
frontend/src/
├── layouts/AppLayout.tsx       # 顶部导航，WB 下拉菜单
├── router/index.tsx            # 所有路由，默认跳转 /wb/platforms
├── pages/wb/                   # 22 个列表页（*Page.tsx）
├── services/wb/
│   ├── types.ts                # 所有 TypeScript 接口定义
│   ├── index.ts                # 通用 CRUD 工具函数
│   └── *.ts                    # 22 个资源的 API 函数
└── utils/request.ts            # axios 实例，baseURL=/api，统一错误处理
```

### 资源列表（22 个）
platforms · sellerAccounts · categories · subjects · products · productSkus ·
productPrices · warehouses · stocks · orders · supplies · adCampaigns ·
promotions · analyticsSalesFunnels · analyticsSearchTerms · reviews · questions ·
chats · returnClaims · accountBalances · salesReports · syncTasks

---

## Ozon API 接入（raw_ozon_*）

### 完成状态
15/18 个 sync 步骤正常运行，3 个因账号订阅限制无法测试（见下）。

### 认证方式
单一域名 `api-seller.ozon.ru`，Header 传 `Client-Id` + `Api-Key`（从 `RawOzon::SellerAccount` 读取，对应环境变量 `OZON_CLIENT_ID` / `OZON_API_KEY`）。

### 数据表（18 张，均在 `raw_ozon_` 前缀下）
| 表 | 说明 |
|---|---|
| seller_accounts | 账号（client_id + api_key） |
| categories | 商品类目树（9540 条，含 type 节点） |
| warehouses | 仓库 |
| products | 商品（含 offer_id / ozon_sku） |
| product_prices | 商品价格 |
| product_stocks | 商品库存 |
| postings_fbs | FBS 发货单（卖家自发货） |
| postings_fbo | FBO 发货单（Ozon 仓发货） |
| returns | 退货（FBO+FBS 合并，用 return_schema 区分） |
| supply_orders | 进货单（备货到 Ozon 仓） |
| reviews | 评价（需 Premium 订阅，暂不可用） |
| questions | 问答（需 Premium Plus，暂不可用） |
| chats | 聊天（本地代理干扰，生产环境正常） |
| finance_transactions | 财务流水 |
| finance_realization | 财务对账单 |
| analytics | 分析数据（按 SKU 维度） |
| analytics_stocks | 库存分析 |
| promotions | 促销活动 |

### Sync 服务结构
```
app/services/raw_ozon/
├── ozon_client.rb           # Net::HTTP 客户端，自动重试 429/5xx
├── base_sync.rb             # 三种分页 helper（cursor / last_id / offset）
└── syncs/
    ├── seller_info.rb
    ├── categories.rb        # 坑：type 节点用 type_id，需 uniq 去重后再 upsert
    ├── warehouses.rb
    ├── products.rb
    ├── product_prices.rb
    ├── product_stocks.rb
    ├── postings_fbs.rb
    ├── postings_fbo.rb
    ├── returns.rb           # 坑：price 字段是 Hash {currency_code, price}，需取 ['price']
    ├── supply_orders.rb     # 坑：filter.states 必须传至少 1 个枚举值
    ├── reviews.rb
    ├── questions.rb
    ├── chats.rb
    ├── finance_transactions.rb
    ├── finance_realization.rb
    ├── analytics.rb
    ├── analytics_stocks.rb
    └── promotions.rb
```

### 分页模式
| 模式 | 接口类型 | Helper |
|---|---|---|
| cursor | 商品/价格/库存 | `fetch_cursor_paginated` |
| last_id | 退货/评价/问答（last_id 初始值传 `0` 而非 `""`） | `fetch_last_id_paginated` |
| offset/page | 财务流水/分析 | `fetch_offset_paginated` |

### Ozon 订单映射（→ ec_orders）
Ozon 无"订单列表"接口，订单通过发货单（posting）获取：
```
raw_ozon_postings_fbs / raw_ozon_postings_fbo → ec_orders（按 order_number 聚合）
posting 内的 products 数组 → ec_order_items
```

### 已知限制（账号订阅）
- `sync_reviews`：需要升级订阅计划（PermissionDenied 403）
- `sync_questions`：需要 Premium Plus 订阅（PermissionDenied 403）
- `sync_chats`：本地代理 SSL 干扰，生产环境应正常

---

## WB API 调研

### 文档位置
`wb_documents/markdowns/` — 13 个 Markdown 文件，含所有接口说明和 db_schema。

### API Key
从环境变量 `WB_API_KEY` 读取。

### 主要域名
| 服务 | 域名 |
|------|------|
| 商品内容 | content-api.wildberries.ru |
| 订单/发货 | marketplace-api.wildberries.ru |
| 价格折扣 | discounts-prices-api.wildberries.ru |
| 广告 | advert-api.wildberries.ru |
| 分析 | seller-analytics-api.wildberries.ru |
| 统计 | statistics-api.wildberries.ru |
| 评价/问答 | feedbacks-questions-api.wildberries.ru |
| 财务 | finance-api.wildberries.ru |

### 已知坑
- Sales funnel API 必须传 `selectedPeriod` 字段
- 价格列表用 GET + `?limit=5&offset=0`，不是 POST body
- 反爬虫：Playwright stealth + 等待 title 从 "Почти готово" 变化
- `sales_funnel_history` API 最多回溯 7 天，无论传多大日期范围都会报 "excess limit on days"；必须手动切 7 天 chunk，且 `effective_from` 取 `[@from.to_date, 7.days.ago.to_date].max`

### stats_orders 与 stats_sales 的关系

两张表通过 `srid` 关联，代表同一笔交易的两个阶段：

| | `raw_wb_stats_orders` | `raw_wb_stats_sales` |
|---|---|---|
| API 来源 | `/api/v1/supplier/orders` | `/api/v1/supplier/sales` |
| 触发时机 | 买家**下单** | 买家**签收确认** |
| `total_price` | 商品标价 | 同上（下单时标价） |
| `for_pay` | — | WB 实付卖家（扣佣金/物流后） |
| `finished_price` | — | 最终结算价 |
| `is_cancel` | 是否取消 | — |
| `is_storno` | — | 是否冲销（退货） |

**关系：1 个 stats_order → 0 或 1 个 stats_sale**
- 取消订单（`is_cancel=true`）→ 无对应 stats_sale
- 正常签收 → 有对应 stats_sale，`sale_date` 比 `order_date` 晚数天到数周

**用途区分**：
- 分析**销量/需求**：stats_orders（含取消，看完整需求）
- 分析**收入/利润**：stats_sales 的 `for_pay`（实际到账金额）
- 销售漏斗的 `buyouts`（核销数）对应 stats_sales 记录数

---

## Ec:: 成本模型（已完成）

### 两张表的职责

```
ec_sku_costs          — 货物本身的成本（与平台无关）
                        采购价 / 到白俄运费 / 清关杂费 / 关税 / 进口增值税 / 包装尺寸
ec_sku_platform_costs — 某平台某模式下的成本参数 + 计划售价
                        唯一键：(sku_code, platform, delivery_mode, company_type)
```

### 成本计算的核心原则

**售价是成本的输入参数**，不只是收入。收单费、广告费、佣金、销售税全部以售价为基数，因此：

```
最终成本 = 固定部分（货物成本 + 运费）
         + 售价 × (收单费率 + 广告费率 + 佣金比例 + 税率)
```

`ec_sku_platform_costs` 存的是**成本参数**（费率 + 计划售价），`total_cost_cny` 等是运行时计算方法，不落库。计划售价（`target_price_rub`）是计算的锚点，周利润 = 计划单件利润 × 当周销量。

### WB 成本计算（`platform='wb'`）

```
基础运费RUB = (升量取整 - 1) × 14 + wb_logistics_base_rub
             Tab1大公司=60, Tab2小公司=46

平台运费CNY = 基础运费RUB × logistics_coeff ÷ 汇率
返程费CNY   = 平台运费CNY × 18/82
退货运费CNY = 50RUB ÷ 汇率 × 18/82   （固定 50 RUB，独立于平台运费）

最终成本 = 货物成本 + FBO到仓费 + 平台运费 + 返程费 + 退货运费
         + 仓储费 + 收单费 + 广告费 + 货损 + 杂费 + 佣金 + 销售税

销售税：
  general（大公司20%НДС）= 售价CNY × 20/120 − 进口增值税
  small  （小公司6%УСН） = 售价CNY × 6%
```

### Ozon 成本计算（`platform='ozon'`）

Ozon 按**体积（升）**计费，FBO/FBS 费率不同，且区分俄罗斯/白俄罗斯双市场：

```
去程运费RUB = (升量取整 - 3) × ozon_fwd_per_liter_rub + ozon_fwd_base_rub
              FBO: 87.44 + 15.25/L；FBS: 117.94 + 23.39/L

返程运费RUB = FBO费率（FBS也用FBO返程费率）
退货折算RUB = (去程×2 + 返程×2) ÷ 8

仓库费用：FBO = 操作费×1.5；FBS = 操作费 + 配送费×1.5

佣金/收单/广告 均基于【俄罗斯售价】计算（即使卖白俄也用RF价算费用）

卖俄罗斯最终成本 = (货物成本 − 进口增值税) + 平台费用   # 俄罗斯VAT可抵扣
卖白俄最终成本   = 货物成本 + 平台费用 + (白俄售价CNY × 20/120 − 进口增值税)
```

### 关键字段说明

| 字段 | 说明 |
|---|---|
| `wb_logistics_base_rub` | WB基础运费常数：Tab1大公司=60，Tab2小公司=46 |
| `ozon_fwd_base_rub` / `ozon_fwd_per_liter_rub` | Ozon去程费率（FBO/FBS不同） |
| `ozon_ret_base_rub` / `ozon_ret_per_liter_rub` | Ozon返程费率（固定用FBO费率） |
| `ozon_warehouse_op_rub` | 官方仓操作费（FBO:25, FBS:30） |
| `ozon_fbs_delivery_rub` | FBS专有配送费（25，FBO无此项） |
| `target_price_rub` | WB计划售价（单一市场） |
| `target_price_rf_rub` / `target_price_by_rub` | Ozon双市场计划售价（俄罗斯/白俄） |
| `pkg_volume_override_l` | 直填升量（Ozon无包装尺寸时用） |

### Google Sheets 成本模板（已对照验证）

Sheet ID：`1JbhVK4adukKD2b2KnAHHbruCsB9Y9G7xixFkVqMTrpg`

| Tab | 对应场景 |
|---|---|
| 成本模板确认1 | WB 大公司（20% НДС） |
| 成本模板确认2 | WB 小公司（6% УСН） |
| 成本模板确认3 | Ozon FBO |
| 成本模板确认4 | Ozon FBS |

读取方式：`GoogleSheets::BaseService`（Service Account 认证，credentials 在 `config/ecommerce-sheets-*.json`）。

### 测试

`test/models/ec/sku_platform_cost_test.rb` — 45 个单元测试，用四个 Tab 的真实数据逐步校验每个中间计算步骤，误差容忍 ±1 CNY。运行：

```bash
bundle exec rails test test/models/ec/sku_platform_cost_test.rb
```

---

## Google Sheets 双向同步（已完成）

### 服务器部署
- 域名：`ecommerce.evexport.cn`
- 日志：`journalctl -u ecommerce_manage_puma -f`（puma stdout 被 systemd 接管，无 production.log）

### 当前开放路由（其余业务接口暂时屏蔽）
```
GET  /up                    # health check
POST /google_sheets/ping    # 测试 Google Sheets 写入连通性
POST /google_sheets/webhook # 接收 Google Apps Script 的编辑通知
```

### Google Sheets Tab 与服务对应关系

| Sheet Tab | DB 表 | 读入服务 | 写出服务 |
|---|---|---|---|
| `SKU` | `ec_skus` | `SkuImportService` | `SkuSheetService` |
| `SKU_COST` | `ec_sku_costs` | — | `CostSheetWriteService` |
| `wb_cost` | `ec_sku_platform_costs`（WB） | — | `CostSheetWriteService` |
| `ozon_cost` | `ec_sku_platform_costs`（Ozon） | — | `CostSheetWriteService` |
| `Inventory` | `ec_inventory_snapshots` + `ec_inventory_totals` | `InventorySnapshotImportService`（仅回写 total_received） | `InventorySnapshotWriteService` |

### SKU Tab 结构（简化后，仅 4 列）
```
A: sku_code        B: product_name（中文）
C: product_name_ru D: 是否上架（是/否）
```

### 数据流
```
DB → Sheet：调用写出服务，全量清空 Tab 再重写（不做 diff）
Sheet → DB：用户编辑单元格 → Apps Script onEdit → POST /google_sheets/webhook
            → webhook 按 sheet 名分发 → SkuImportService（upsert，不删除缺失行）
```

### Apps Script 配置要点
- 必须用**可安装触发器**（非简单 `onEdit` 命名），否则 `UrlFetchApp` 无权限
- 加 `LockService` 防抖，避免连续编辑重复触发
- 监听的 Tab：`SKU`（触发 `SkuImportService`）
- `onEdit` 中 `e.source` 在手动运行时为 undefined，只能由实际编辑触发

### 手动触发同步
```bash
# DB → Sheet（SKU）
bundle exec rails runner "GoogleSheets::SkuSheetService.new.call"

# DB → Sheet（成本三张表）
bundle exec rails runner "GoogleSheets::CostSheetWriteService.new.call"

# Sheet → DB（SKU）
bundle exec rails runner "GoogleSheets::SkuImportService.new.call"
```

---

## 库存快照系统（已完成，2026-05-19）

### 两张表的职责

```
ec_inventory_snapshots — 每个 SKU × 平台 × 店铺 的实时库存快照（每日自动更新）
                          字段：sku_code, platform, account_id, store_name,
                                stock（在仓）, supply（送仓）, sold（售出）, fbs, synced_at
                          唯一键：(sku_code, platform, account_id)

ec_inventory_totals    — 每个 SKU 的跨平台汇总（手填 + 计算）
                          字段：sku_code, total_received（手填，总入库）,
                                total_supply, total_stock, total_sold, total_fbs, synced_at
                          唯一键：sku_code
```

### 迁移文件
| 文件 | 内容 |
|---|---|
| 20260519000002 | ec_inventory_snapshots |
| 20260519000003 | ec_inventory_totals |

### 数据流

```
RawWb::DailySync / RawOzon::DailySync（每日 8:00/8:30）
  → Ec::InventorySnapshotSync（每日 9:00，聚合写 ec_inventory_snapshots + ec_inventory_totals）
  → GoogleSheets::InventorySnapshotWriteService（同在 9:00，写 Google Sheets "Inventory" Tab）
```

`upsert_all` 时 `update_only` 不含 `total_received`，保留运营手填数据。

### 汇总服务计算逻辑（已对照 DESIGN_v9 验证，2026-05-19）

#### Ozon（`Ec::OzonInventorySummary`）
- STORE_NAMES: `{1=>"Nevastal", 3=>"Nevastal2", 4=>"Domos", 5=>"Nanokit"}`
- **FBO 送仓** = `raw_ozon_supply_orders` status=COMPLETED，按 ozon_sku 聚合 items 数量
- **FBO 库存** = `raw_ozon_product_stocks.present_fbo`（实时快照；样本用 free_to_sell_amount，差值 ±2 在容差内）
- **FBO 售出** = 送仓 − 库存（派生）
- **FBS 净销量** = delivered posting items 数量 − cancelled posting items 数量（§3.3）
  - 数据源：`raw_ozon_postings_fbs` status=delivered/cancelled → `raw_ozon_posting_items` posting_type=fbs
- **行生成范围** = `(supply_totals.keys + fbs_totals.keys).uniq`，有 FBS 无送仓的 SKU 也生成行（§4.2）
- SKU 映射链：`raw_ozon_products.raw_json['sku']` → `offer_id`（Article）

#### WB（`Ec::WbInventorySummary`）
- STORE_NAMES: `{2=>"TaxiLink", 3=>"WorldChoice"}`
- **FBW 送仓** = `raw_wb_supply_items.accepted_qty`，按 nm_id 聚合
- **FBW 库存** = `raw_wb_stocks` 通过 barcode→product_skus→products JOIN，按 nm_id 聚合
  - 注意：WB stats stocks API 只返回近期变更行，需定期全量同步：`RawWb::DailySync.run(days: 500, sync_keys: [:sync_stocks])`
- **FBW 售出** = 送仓 − 库存（派生）
- **FBS** = `raw_wb_orders` delivery_type='fbs' 的 COUNT，每条 order = 1 件（§3.6）
  - `/api/v3/orders` 单次最多 30 天，`sync_orders` 用 `date_chunks(chunk_days: 30)` 分段拉取完整 @from..today 范围
  - 历史补全：`RawWb::DailySync.run(days: 500, sync_keys: [:sync_orders])`（约 17 个 30 天 chunk）
- **行生成范围** = `(supply_totals.keys + stock_map.keys + fbs_totals.keys).uniq`（§4.2）

#### 已验证准确度（对比 Inventory_v9_2026-05-19.xlsx）
- DB 共 26 个去重 SKU，样本有效行 50 条（跨6家店铺）
- 完全一致：42/50 行（84%）；含 FBS ±1 容差后：50 行中 48 行准确（96%）
- 含 FBO 实时快照漂移（±1~2）：23/26 SKU 准确（88.5%）
- 剩余 3 个 SKU 差距均为 SKU code 命名不一致或送仓数据未同步，非计算逻辑问题
- 17 个完全对齐的 SKU：CYQ97-BK/WT、JD-ZQTB-206/310、JDLJ-01WS8、JXZ-GREY-01、JXZ-WHITE-02、JZDJ-02WS/02YS/YS、JZJJ-001、KJ-217-WT、KJ-228-BK/SV/WT、XCQ707

### 派生列（白俄仓推算 / 总可售）

这两列是**只读公式**，不落库，不通过 webhook 回填：

```
白俄仓推算 = 总入库 − 总送仓 − FBS总计   (Sheets 公式)
总可售     = 白俄仓推算 + 总库存          (Sheets 公式)
```

### Google Sheets "Inventory" Tab 结构

- Tab 名：`"Inventory"`（英文，方便俄区员工）
- 3 行表头：第1行英文分组（Article/Name/store名/Summary/Manual/Auto/Meta），第2行中文，第3行俄文
- FIXED_COLS = 3（sku_code / 产品名(中) / 产品名(俄)）
- HEADER_ROWS = 3（数据从第4行开始，row_n = idx + 4）
- 冻结前3行 + 前3列
- 手填列（总入库）黄底；派生列灰底（公式只读）
- TOTAL_RECEIVED_COL = MANUAL_START（列索引由常量自动推算）

### Webhook 分发

`GoogleSheetsController#webhook` 中 `when "Inventory"` → `InventorySnapshotImportService`
只回写 `total_received` 字段，派生列不落库。

### Apps Script（待更新）

监听 Tab 名需从 `"库存快照"` 改为 `"Inventory"`。

### 手动触发

```bash
# 更新快照并写 Sheet
bundle exec rails runner "Ec::InventorySnapshotSync.run; GoogleSheets::InventorySnapshotWriteService.new.call"

# 仅刷新 Sheet（不重新拉 API）
bundle exec rails runner "GoogleSheets::InventorySnapshotWriteService.new.call"
```

### 已接入店铺（6家）

| 店铺 | 平台 | account_id | 类型 |
|---|---|---|---|
| Nevastal | ozon | 1 | FBO |
| Nevastal2 | ozon | 3 | FBO |
| Domos | ozon | 4 | FBO |
| Nanokit | ozon | 5 | FBO |
| WorldChoice | wb | 3 | FBW |
| TaxiLink | wb | 2 | FBW |

### Schedule 设计要点（已验证，2026-05-19）

#### 周一时间线（最密集）
```
5:30  WbWeeklySync(days:8) 全量 13步
6:00  OzonPerformanceSync(W-2, W-1)
6:10  WbWeeklySync(pre-pull: ad_campaigns/finance_details/paid_storage/ad_settled_fees)
7:30  OzonDailySync(days:15, accrual_by_day)
8:00  WbDailySync(days:2) 全量
8:30  CbrRateFetcher + OzonDailySync(days:2) 全量
9:00  InventorySnapshotSync + Sheets
13:00 WeeklyProfitReportRunner
```

#### 数据安全兜底
- **WB stocks 全量**：月2日 3:00，`DailySync(days:500, sync_keys: [:sync_stocks])`
  WB stocks API 只返回近期变动行，不全量拉取会漏掉长期不动的库存
- **WB 周日 catchup**：每周日 2:00，`DailySync(days:8, sync_keys: [:sync_orders, :sync_supplies, :sync_supply_items, :sync_stats_orders, :sync_stats_sales])`
  这5个步骤不在 WeeklySync STEPS 中；WB stats API 延迟 T+1~3，days:2 可能漏掉晚结算数据

#### whenever 已知坑
`every :month, on: X` 的 `on:` 参数存在 off-by-one bug（`on: 2` 生成 day 1）。
月度任务一律改用 raw cron 语法：`every '0 3 2 * *' do`

### WB supply_items sync 已知坑

`raw_wb/syncs/supply_items.rb` 有两处 API 响应格式差异：
- `/api/v1/supplies` 直接返回 Array（不是 `{supplies: [...]}`），需 `resp.is_a?(Array) ? resp : Array(resp['supplies'] || [])`
- `/api/v1/supplies/:id/goods` 同理
- `limit: 1000` 必须放 body hash 里，不能作为第4位置参数传给 `WbClient#post`

---

## Ozon 利润归集

### 报表概述

**周利润报表（Ozon WR）** 按 SKU × 销售区域（白俄/出口）汇总，适合看某个商品这周赚了多少。每周自动生成上两周数据。

所有输出字段统一为**人民币（CNY）**，汇率在调用时传入。

### 整体数据流

```
每周一 6:00   OzonPerformanceSync(W-2, W-1)  →  raw_ozon_performance_sku_spends
每周一 7:30   OzonDailySync(days:15)          →  raw_ozon_accrual_by_day（刷新财务结算数据）
每周一 13:00  WeeklyProfitReportRunner
               → OzonProfitAttribution（计算）→ Google Sheet OzonWR:Wn-店名
```

报表生成全程只读 DB，不调 Ozon API。

### 数据源

| 数据 | 来源表 |
|---|---|
| 所有费用行 | `raw_ozon_accrual_by_day`（按日期范围） |
| 广告费 | `raw_ozon_performance_sku_spends`（overlapping period 查询） |
| 目的国（白俄/出口） | `raw_ozon_posting_destinations` |
| 货物成本/进口增值税 | `ec_sku_costs` |
| SKU 映射 | `raw_ozon_posting_items` + `ec_skus` |

### SKU 映射策略

`ozon_sku_id → offer_id`：从 `raw_ozon_posting_items` 全量加载，同一 ozon_sku 可能历史上对应多个 offer_id（平台录入变更）。优先选能在 `ec_skus` 中命中的 offer_id；全部不命中时取最后一条。

### 费用分类（type_id）

| 常量 | type_id | 字段 |
|---|---|---|
| `DELIVERY_TYPE_IDS` | 16,28,29,30,31,32,98 | `delivery_charge` |
| `RETURN_TYPE_IDS` | 9,45,59,60,61 | `return_delivery` |
| `STORAGE_TYPE_IDS` | 15,46,**78** | `storage_fee` |
| `DISPATCH_TYPE_IDS` | 33,**71** | `dispatch_fee` |
| `DEFECT_TYPE_IDS` | 14 | `defect_fee` |
| `AD_TYPE_IDS` | 41,54 | 由 Performance API 独立归集，不走 by-day |
| `UNALLOCATED_TYPE_IDS` | 93,94,96 | → `unalloc_rows` |
| type_id=0 | SaleRevenue（合成值） | `sales_revenue` |
| type_id=69 | SaleCommission | `commission` |
| type_id=1 | Acquiring（支付手续费） | `payment_fee` |
| type_id=12 | CrossDock | `crossdock_fee`（sync 阶段已回填 sku） |

> type_id=71（SellerReturn 出货费）和 type_id=78（临时仓储）是实测发现的 type_id，已加入分类集合。

### CrossDock 回填机制

CrossDock 行（type_id=12）从 API 返回时 `ozon_sku_id=NULL`，`supply_order_number` 是纯数字（非标准三段式 posting）。

**回填发生在 sync 时**（`sync_finance_accrual_by_day` 末尾调用 `resolve_and_backfill_crossdock_skus`），三步链路：

```
/v3/supply-order/list  (filter.order_number_search)  → order_id
/v3/supply-order/get   (order_ids)                   → bundle_id（is_crossdock: true）
/v1/supply-order/bundle (bundle_ids, 必须单个查)      → {sku: quantity}，取最大 quantity 的 SKU
```

回填后 `accrual_by_day.ozon_sku_id` 有值，归集时直接读，无 API 调用。

### Acquiring（type_id=1）归属规则

- 构建 `current_pkeys`：本周期内所有 SaleRevenue 行（正负均含）的 `posting_key`（posting_number 前两段）
- 某 SKU 的 Acquiring 行：仅当其 `posting_key` ∈ `current_pkeys[sku]` 时归属，否则进 `unalloc_rows`
- 老单退货的 Acquiring 退还（负值）通过 posting_key 正确归属

### 区域划分与订单计数

目的地来自 `raw_ozon_posting_destinations`：`is_by=true` 为白俄本地，`false` 为出口。

订单计数按 **posting 级净额**（非行级）：

```
net = sum(同一 posting 所有 SaleRevenue 行)
net > 0  → blr/export_count +1，blr_sale += net（白俄）
net < 0  → blr/export_count -1（退货，允许为负）
net = 0  → 跳过
```

白俄 VAT 税基（`blr_sale`）只累计正净额，不含退货负值。

### 利润链计算

```
book_profit          = sales + commission + delivery + payment + dispatch +
                       packing + return + storage + defect + crossdock + other
book_profit_after_ad = book_profit - (ppc + promotion)
goods_cost           = -(net_sales_count × cost_cny × rate_cny_rub)
pre_tax_profit       = book_profit_after_ad + goods_cost

import_vat_rub       = import_vat_cny × rate_cny_rub
blr_tax              = -(max(blr_sale × 20/120 - max(blr_count, 0) × import_vat_rub, 0))
export_refund        = export_count × import_vat_cny × rate_cny_rub   # 可为负（净退货周）
after_tax_profit     = pre_tax_profit + blr_tax + export_refund
```

### 广告费同步与归一化

广告费来自两个渠道，均存入 `raw_ozon_performance_sku_spends`：

| 渠道 | 接口 | ad_type | 字段 |
|---|---|---|---|
| PPC（按点击）| `POST /api/client/statistics/json`（异步，per-campaign） | `ppc` | `spend` |
| SEARCH_PROMO（搜索推广）| `POST /api/client/statistic/products/generate`（异步 CSV） | `promotion` | `combo_spend + cpo_spend` |
| ALL_SKU_PROMO（全部商品推广）| `GET /api/client/statistics/all_sku_promo/orders/generate`（异步 CSV，按订单聚合至 SKU） | `promotion` | `allsku_spend` |

SEARCH_PROMO 与 ALL_SKU_PROMO 在 sync 阶段按 SKU 合并后写同一条记录，`spend = combo + cpo + allsku`。

归集时用 **overlapping 查询**（`period_from <= from_date AND period_to >= to_date`）读取广告费，再通过 `rescale_ad_costs_to_accrual` 将 per-SKU 花费按比例归一到 `accrual_by_day` type_id=41/54 的实际总额，消除 API 异步报告与财务结算之间的时序差。

### Sheet 格式

Tab 命名：`OzonWR:W{n}-{店名}`，例 `OzonWR:W21-NEVASTAL`

**上半部分：SKU 明细表**（双行中/俄表头，末行合计）
28 列：SKU ID / 品号 / 区域 / 销售额 / 佣金 / 配送费 / 支付手续费 / 出货费 / 包装费 / 退货运费 / 仓储费 / 残损费 / CrossDock费 / 下单数 / 退货数 / 净销量 / 广告费 / 广告占比% / 其他费用 / 账面小计 / 成交订单 / 退货订单 / 货物成本 / 税前利润 / 白俄VAT / 出口退税 / 税后净利 / 利润率%

**下半部分：纵向汇总区**（明细下方隔 3 行）
数据周期 → 汇率 → 各费用合计 → 账面小计 → 广告明细（PPC/Promotion） → 货物成本 → 税前利润 → 税额 → 未归属费用 → 税后净利 / 利润率 → 目的地拆分（白俄/出口订单数）

### 手动触发

```ruby
# 重跑单店铺周报
GoogleSheets::OzonWeeklyReportService.run_all(
  from_date:    '2026-05-18',
  to_date:      '2026-05-24',
  rate_cny_rub: 10.7318,
  account_ids:  [1]
)

# 调试用（不写 Sheet）
svc = Ec::OzonProfitAttribution.new(
  account_id: 1, from_date: '2026-05-18', to_date: '2026-05-24', rate_cny_rub: 10.7318
).call
svc.results      # Array<Hash>，每个 SKU 一条
svc.unallocated  # 未归属费用汇总
svc.summary      # { total_after_tax:, ... }
```

### 代码对照

| 逻辑 | 文件 |
|---|---|
| Ozon WR 核心计算 | `app/services/ec/ozon_profit_attribution.rb` |
| Ozon WR 写 Sheet | `app/services/google_sheets/ozon_weekly_report_service.rb` |
| PPC sync | `app/services/raw_ozon/syncs/performance_ppc_sku_spends.rb` |
| Promotion sync（含 ALL_SKU_PROMO）| `app/services/raw_ozon/syncs/performance_promotion_sku_spends.rb` |

### 已知数据局限

- `accrual_by_day` 按**结算日**计，部分订单的 SaleRevenue 可能在下周结算 → 当周 orders_count 会比实际签收数少
- 汇率在调用时手动传入；ALL_SKU_PROMO 不可用时（账号未开通）自动降级，SEARCH_PROMO 数据仍有效，总广告费由 `rescale_ad_costs_to_accrual` 兜底归一

---

## Ozon 订单明细报表（OD）

### 报表概述

**订单明细报表（OD）** 把 Ozon 财务数据展开到每笔 posting × SKU，适合逐单对账和排查异常。OD 在 WR（`OzonProfitAttribution`）的基础上向下拆：WR 先算好 SKU 级的广告费、越库费、货物成本；OD 把这些总费用按正向 posting 数量均摊，再对每笔 posting 逐行展开。

所有费用字段单位为**卢布（RUB）**；货物成本和税务字段单位为**人民币（CNY）**。

### 整体数据流

```
OzonProfitAttribution（WR）── SKU 级聚合（广告费、越库费、计数、白俄/出口拆分）
         ↓
OzonOrderDetailReport（OD）── 逐 posting 展开，分摊 SKU 级费用
         ↓
GoogleSheets::OzonOrderDetailSheetService ── 写 Tab "OD:Wn-店名"
```

### 设计原则

- **全程只读 DB，不调 Ozon API**：越库费（CrossDock）在 `sync_finance_accrual_by_day` 末尾通过 `resolve_and_backfill_crossdock_skus` 已将 `ozon_sku_id` 回填到 DB；报表生成时直接读，无 API 调用。
- **OD 不独立重算，借用 WR 结果**：`OzonOrderDetailReport` 先跑一次 `OzonProfitAttribution`，取 SKU 级广告费、越库费、货物成本、税务参数；再按 posting 粒度展开和分摊。

### 费用分摊规则

| 费用 | 分摊方式 |
|---|---|
| 广告费（PPC + Promotion） | WR 该 SKU 总广告费 ÷ 正向 posting 数（pos_ct） |
| 越库费（CrossDock） | WR 该 SKU 总越库费 ÷ 正向 posting 数（pos_ct） |
| 货物成本 | 按成交/退货行分别分摊：成交 = unit_cost；退货 = 回收 unit_cost（+unit_cost 入 after_tax） |
| 税务（白俄 VAT / 出口退税） | 按单笔 posting 计算，不依赖 WR 总量除以 OD 计数 |

> **白俄 VAT per posting**：`blr_sale × 20/120 − blr_ct × import_vat_rub`，结果为负值扣减。  
> **出口退税 per posting**：`import_vat_cny × rate_eff`（per unit），不受 WR 计数影响。

### 越库费与 Python 版的差异（已确认 Ruby 正确）

Python 版（`phase1_order_detail.py`）在报表生成时调用 Ozon API（`_resolve_crossdock_bundle`）解析供货单 SKU 构成，API 失败时静默返回空，导致越库费归零。Ruby 版在 sync 阶段已通过 DB 回填，报表只读 DB，越库费始终准确。

W21 Nevastal 实测：Ruby 账面利润比 Python 低 352.36（= 6 笔 KJ-217-GD 每笔 -371.85 × 6 / 6 + 其他），差额来源于越库费 -2231.1，属 Ruby 正确、Python 漏计。

### Sheet 格式

Tab 命名：`OD:{week_label}-{shop_name}`，例 `OD:W21-Nevastal`

**Section 1：订单明细**（双行中/俄表头，按结算日排序）

32 列：品号 / SKU / 商品名称 / 订单号 / 下单时间 / 结算日 / 签收时间 / 订单类型 / 城市 / 国家 / 配送方式 / 配送模式 / 发货仓 / 支付方式 / 销售收入 / 平台佣金 / 配送费 / 支付手续费 / 退仓取件费 / 打包费 / 退货处理费 / 退货暂存费 / 越库费(分摊) / 账面利润 / 广告费(分摊) / 扣广告后 / 货物成本(分摊) / 税前毛利 / 白俄增值税 / 出口退税 / 税后净利 / 税后利润率%

**Section 2：汇总对账**（明细下方隔 3 行，纵向）

包含：数据周期 / 汇率 / 订单计数（成交/退货/取消/仓储退/白俄/出口）/ 金额对账（与 SKU 报告三项 diff，均带 ✅/❌）/ 利润链汇总 / 孤儿广告明细（如有）/ 税后净利（含/不含未分摊）

### 对账逻辑

OD 汇总行内置与 WR（SKU 口径）的三项 diff 校验：

| 校验项 | 期望 |
|---|---|
| 销售收入 diff | ≈ 0（两侧均来自 accrual_by_day type_id=0） |
| 账面利润 diff | 正常为 0；若有越库费来自 WR 分摊则与 Python 有偏差 |
| 广告费 diff | 孤儿广告（无成交 SKU 的广告费）导致 diff，属正常 |

### 手动触发

```ruby
# 单店铺
GoogleSheets::OzonOrderDetailSheetService.new(
  account_id:   1,
  from_date:    '2026-05-18',
  to_date:      '2026-05-24',
  rate_cny_rub: 10.7318,
  week_label:   'W21',
  shop_name:    'Nevastal'
).call

# 全店铺
GoogleSheets::OzonOrderDetailSheetService.run_all(
  from_date:    '2026-05-18',
  to_date:      '2026-05-24',
  rate_cny_rub: 10.7318
)
```

### 代码对照

| 逻辑 | 文件 |
|---|---|
| OD 核心计算 | `app/services/ec/ozon_order_detail_report.rb` |
| OD 写 Sheet | `app/services/google_sheets/ozon_order_detail_sheet_service.rb` |
| 目的地查询（DB） | `app/services/raw_ozon/syncs/posting_destinations.rb` |

### 调试用单次调用

```ruby
# OD（不写 Sheet）
svc = Ec::OzonOrderDetailReport.new(
  account_id: 1, from_date: '2026-05-18', to_date: '2026-05-24', rate_cny_rub: 10.7318
).call
svc.order_rows  # Array<Hash>，每笔 posting×SKU 一行
svc.summary     # totals + cross-check vs SKU report
```

---

## WB 利润归集

### 报表概述

WB 财务数据经过两个维度的报表加工：

**周利润报表（WR）** 按商品（nmId）× 销售区域（白俄/出口）汇总，适合看某个商品这周赚了多少。每周自动生成上两周数据。

**订单明细报表（WOD）** 把同一数据展开到每笔订单（shkId），适合排查单笔异常或对账。WOD 是在 WR 计算结果之上二次展开的，不是独立重算。

两份报表共用同一批原始财务数据，但 net（账面小计）公式不同——WOD 额外扣减了罚款、补收运费、自提点费用，因此 WOD 汇总净利略低于 WR，属正常。

### 整体数据流

```
每周一 5:30   WeeklySync  →  raw_wb_finance_details（财务明细，含 vw 字段）
                          →  raw_wb_paid_storages（仓储费，RUB）
                          →  raw_wb_ad_settled_fees（广告费，RUB）
每周一 13:00  WeeklyProfitReportRunner
               → WbProfitAttribution（WR 计算）→ Google Sheet WR:Wn-店名
               → WbOrderDetailReport（WOD 展开）→ Google Sheet WOD:Wn-店名
```

报表生成全程只读 DB，不调 WB API。

### 货币单位与换算

所有输出字段统一为**白俄卢布（BYN）**。三种货币来源的换算规则：

| 来源货币 | 换算方式 | 适用场景 |
|---|---|---|
| BYN | 直接取 `finance_details` 原始值 | 财务明细已是 BYN |
| RUB（仓储费） | ÷ rate_byn_rub，无缓冲 | `raw_wb_paid_storages` |
| CNY（货物成本） | × rate_cny_rub × **1.03** ÷ rate_byn_rub | 1.03 = 运费/清关损耗缓冲 |

汇率每周录入一次，存于 `ec_weekly_rates` 表，报表调用时读取。

### 数据来源

| 数据 | 来源表 |
|---|---|
| 财务明细行 | `raw_wb_finance_details`（按 `sale_dt` 日期范围） |
| 仓储费 | `raw_wb_paid_storages`（按 `calc_date`，RUB 计） |
| 广告费 | `raw_wb_ad_settled_fees`（按 `period_from/to` 精确匹配，RUB 计） |
| 广告-商品映射 | `raw_wb_ad_campaigns` + `raw_wb_ad_campaign_products` + `raw_wb_ad_sku_spends` |
| 货物成本 | `ec_sku_costs`（`goods_cost_cny` / `import_vat_cny`） |

### 财务行的分类

WB 财务 API 每一行都带 `seller_oper_name`（操作类型，俄文）。归集时按以下规则处理：

| 操作类型 | 处理方式 | 计入 WR net？ |
|---|---|---|
| Продажа（成交） | settlement += for_pay；记录 sales_qty、tax_base、acquiring | 是（settlement） |
| Возврат（退货） | settlement -= for_pay；记录 return_qty | 是（settlement 取反） |
| Логистика（配送） | delivery += delivery_rub | 是 |
| Коррекция логистики（配送修正） | delivery += delivery_rub | **仅 WOD** 匹配，WR 不匹配 |
| Возмещение издержек（WB 内部调整） | reimb += rebill_logistic_cost；logistics_reimb += vw（负值） | 否，仅展示 |
| Возмещение за выдачу（自提点） | pickup += ppvz_reward + vw | 否，仅展示 |
| Штраф（罚款） | penalty += penalty | 否，仅展示（WOD 计入 net） |
| Хранение（白俄仓储） | 跳过，nm_id=0 → 进未归属行 | — |
| Удержание（广告扣款） | 跳过，由广告 API 替代（nmId=0 无法拆分到商品） | — |

> **Sheet 中"自提点费用"列** = `logistics_reimb + pickup` 合并展示，两者都是 WB 内部调整项。

### 区域划分

每条财务行带 `report_type`：**1 = 白俄本地，2 = 出口**。归集粒度为 `(nm_id, report_type)`，同一商品在两个区域的利润分别计算。

### nmId 归属策略

部分财务行（配送、罚款等）没有 nmId，只有 shkId（订单号）。按以下优先级归属：

1. **直接归属**：行本身 nmId > 0 → 直接归到该商品
2. **订单号反查**：nmId=0 但有 shkId → 从成交行建立的 shkId→nmId 映射表反查
3. **未归属**：shkId 也找不到 → 进 `unallocated`，报表末尾单独展示，不影响 after_tax 合计

---

## WR 周利润报表计算逻辑

### 利润链公式

```
账面小计(net) = 结算额 - 配送费 - 仓储费 - 广告费
               （收单费 / 罚款 / 补收运费 / 自提点费用 仅展示，不扣减）

净销量        = max(成交数 - 退货数, 0)
货物成本      = 净销量 × goods_cost_cny × (rate_cny_rub × 1.03 / rate_byn_rub)
税前利润      = net - 货物成本

税额(OSN大公司) = 税基 × 20/120 - 净销量 × import_vat_per_unit_byn
税额(УСН小公司) = 税基 × 6%

税后净利      = 税前利润 - 税额
```

### 仓储费处理

仓储费有**两个不重叠的来源**，处理方式不同：

| 来源 | 内容 | 处理方式 |
|---|---|---|
| `raw_wb_paid_storages.warehouse_price_rub` | 俄罗斯仓库费，per-nmId，RUB | 全归出口（Type2）区域；÷ rate_byn_rub；**全量加载，不过滤 nmId**（含当周无销售的 SKU） |
| `finance_details` `Хранение` 行 | 白俄仓库费，nm_id=0，BYN | 自动进 unallocated，显示在未归属合计 |

> 仓储费全部归出口区域。若某商品当周只有白俄销售，其出口行会显示负利润，属正常（仓在俄罗斯，费用归出口）。

### 广告费处理：隐含汇率机制

WB 对白俄账户用**隐含汇率**（不等于央行汇率）将广告 RUB 换算为 BYN 扣款。隐含汇率从当周 `Удержание` 行反推：

```
implied_rate = 广告总额(RUB) ÷ Удержание 扣款总额(BYN)
```

若两者之一为零，降级使用 CBR 汇率。各商品广告费按以下优先级分摊：
1. `ad_sku_spends` 表中的实际花费比例
2. 降级：均分给 `ad_campaign_products` 中的各 nmId

分摊后按各商品白俄/出口**销量比例**，分别计入两个区域 bucket。

### 货物成本 SKU 映射

WB 财务行里的 `vendor_code` 需要映射到内部 `sku_code` 才能查到货物成本：
1. `VENDOR_CODE_ALIASES` 别名表（手工维护，处理编码不一致的情况）
2. 大小写不敏感匹配 `ec_sku_costs.sku_code`

### Sheet 格式（WR）

Tab 命名：`WR:W{n}-{店名}`，例 `WR:W21-Такси Линк`

**上半部分：SKU 明细表**（双行中/俄表头，末行合计）
22 列：nmId / 品号 / 区域 / 下单数 / 退货 / 净销量 / 标价收入 / 结算额 / 收单费 / 配送费 / 补收运费 / 自提点费用 / 罚款 / 仓储费 / 广告费 / 账面小计 / 税基 / 进口VAT(CNY) / 货物成本 / 税前利润 / 税额 / 税后净利

**下半部分：纵向汇总区**（明细下方隔 3 行）
数据周期 → 汇率 → 税制 → 各费用合计 → 账面小计 → 货物成本 → 税前利润 → 税额 → 未归属费用 → 税后净利 / 利润率

---

## WOD 订单明细报表计算逻辑

### 设计思路

WOD 在 WR 的基础上向下拆：WR 先算好每个 nmId 的仓储费、广告费、货物成本总量；WOD 把这些总费用 ÷ 成交数，得到每单的分摊成本，再对每笔 shkId 逐行展开。

**WOD net 与 WR net 的区别**：WOD 额外扣减了罚款、补收运费、自提点费用，因此 WOD 汇总净利 < WR 净利，差额 = 这三类费用之和，属正常。

### 每笔订单的费用归属规则

一个 shkId 代表一次购物事件，可能包含多条财务行（成交行 + 退货行）：

```
配送费 / 罚款 / 补收运费 / 自提点费用：
  → 整个 shkId 只算一次（不按行数分摊）
  → 【配对分组】若同一 shkId 当周既有成交又有退货：
      费用只归到成交行，退货行的这些字段全部置 0
      （防止同一笔费用被成交+退货分别计算造成双重扣减）

仓储费 / 广告费 / 货物成本：
  → 仅成交行承担，退货行置 0
  → 金额 = WR 该商品总费用 ÷ 成交件数（per-unit 分摊）
```

### 孤儿成本

有些费用行有 shkId，但整周没有对应的成交/退货行（例如纯物流行）——这些是孤儿成本，在 Sheet 末尾单独列一行（橙底），不并入明细，但计入总计。

孤儿行的归入条件（与 WR 对称，保证两侧残差为零）：shkId 能反查到 nmId，**或**行本身 nmId > 0。不满足条件的行在 WR 里也被排除，两侧同步，残差始终为零。

### Sheet 格式（WOD）

Tab 命名：`WOD:W{n}-{店名}`，例 `WOD:W21-Такси Линк`

33 列：nmId / 品号 / 品牌 / 商品名称 / shkId / 交易类型（成交/退货）/ 区域 / 区域代码 / 下单时间 / 签收时间 / 国家 / 发货仓 / 自提点/地址 / 配送方式 / 折后标价 / SPP% / 客户支付 / 佣金率% / 结算额(forPay) / 收单费 / 配送费 / 罚款 / 补收运费 / 自提点费用 / 仓储费(分摊) / 广告费(分摊) / 账面小计 / 税基 / 货物成本(分摊) / 税前毛利 / VAT净额 / 税后净利 / 利润率%

末尾两行：
- **孤儿行**（橙底斜体）：未能归属到具体订单的孤儿费用
- **总计行**（金底加粗）：明细合计 + 孤儿合计

---

## 线上调试 — Rails Runner 正确用法

在生产容器内执行临时 Ruby 脚本（只读调试）：

```bash
# 1. 本地写脚本
cat > /tmp/debug.rb << 'RUBY'
# ... ruby 代码 ...
RUBY

# 2. 上传到宿主机 → 复制进容器 → 执行
scp /tmp/debug.rb root@eshop.evexport.cn:/tmp/debug.rb && \
  ssh root@eshop.evexport.cn "docker cp /tmp/debug.rb eshop_manage-web-<VERSION>:/tmp/debug.rb && \
  docker exec eshop_manage-web-<VERSION> bin/rails runner /tmp/debug.rb" \
  2>&1 | grep -v "image_processing\|image variants"
```

**关键注意事项：**
- 获取账号必须通过 `Ec::Store`，不能直接用 `RawWb::SellerAccount.first`（token 来源不对会 401）：
  ```ruby
  store = Ec::Store.where(platform: 'wb', is_active: true).first
  account = store.raw_wb_account
  client = RawWb::WbClient.new(account.api_token)
  ```
- 容器 VERSION 从 `docker ps` 或 kamal 日志里取，当前为 `2b76f771d6e8d15ffaca475a7486571688464915`
- `bin/kamal app exec --reuse` 方式在多行代码含中文/括号时 shell 转义会出错，推荐文件方式

---

## 运维与调度

### 自动调度

```
每周一 5:30   WeeklySync（全量拉取财务/仓储/广告数据）
每周一 13:00  WeeklyProfitReportRunner → 生成上周（W-1）报表
每周四 3:30   WeeklySync（补拉广告数据，应对 WB 延迟结算）
```

报表前置条件：`ec_weekly_rates` 表已录入对应周的汇率。

### 手动操作

```ruby
# 录入汇率
Ec::WeeklyRate.create!(week_start: '2026-05-18', rate_cny_rub: 10.73, rate_byn_rub: 26.56)

# 重跑全店铺 WR + WOD
GoogleSheets::WbWeeklyReportService.run_all(from_date: '2026-05-18', to_date: '2026-05-24')
GoogleSheets::WbOrderDetailSheetService.run_all(from_date: '2026-05-18', to_date: '2026-05-24')

# 仅重跑单店铺 WOD
GoogleSheets::WbOrderDetailSheetService.run_all(
  from_date: '2026-05-18', to_date: '2026-05-24',
  account_ids: [2]
)
```

---

## 代码对照

| 逻辑 | 文件 |
|---|---|
| WR 核心计算 | `app/services/ec/wb_profit_attribution.rb` |
| WOD 核心计算 | `app/services/ec/wb_order_detail_report.rb` |
| WR 写 Sheet | `app/services/google_sheets/wb_weekly_report_service.rb` |
| WOD 写 Sheet | `app/services/google_sheets/wb_order_detail_sheet_service.rb` |
| 调度入口 | `app/services/google_sheets/weekly_profit_report_runner.rb` |
| 财务行关键字常量 | `app/models/raw_wb/finance_detail.rb`（`SALE_KEYWORD` 等） |
| vendorCode 别名表 | `wb_profit_attribution.rb` 顶部 `VENDOR_CODE_ALIASES` |

### 调试用单次调用

```ruby
# WR（不写 Sheet）
svc = Ec::WbProfitAttribution.new(
  account_id: 2, from_date: '2026-05-18', to_date: '2026-05-24',
  rate_cny_rub: 10.93, rate_byn_rub: 26.41
).call
svc.results      # Array<Hash>，每个 nmId×reportType 一条，金额均为 BYN
svc.unallocated  # 未归属行汇总
svc.summary      # { tax_regime:, total_after_tax:, ... }

# WOD（不写 Sheet）
svc = Ec::WbOrderDetailReport.new(
  account_id: 2, from_date: '2026-05-18', to_date: '2026-05-24',
  rate_cny_rub: 10.93, rate_byn_rub: 26.41
).call
svc.order_rows    # Array<Hash>，每笔成交/退货一行
svc.orphan_costs  # 孤儿成本汇总 { delivery:, penalty:, rebill:, pickup:, net:, after_tax: }
svc.summary       # 含 grand_after_tax / sku_total_after_tax / residual
```

### 财务行关键字完整说明（`seller_oper_name`）

| 常量 | 关键字（俄文） | 字段取值 |
|---|---|---|
| `SALE_KEYWORD` | `Продажа` | for_pay, acquiring_fee, quantity, retail_price_with_disc |
| `RETURN_KEYWORD` | `Возврат` | for_pay（取反）, quantity |
| `LOGISTIC_KEYWORD` | `Логистика` | delivery_rub |
| `CORR_LOGISTIC_KEYWORD` | `Коррекция логистики` | delivery_rub（仅 WOD） |
| `REIMB_KEYWORD` | `Возмещение издержек` | rebill_logistic_cost（reimb）；vw（logistics_reimb，负值） |
| `PICKUP_KEYWORD` | `Возмещение за выдачу` | ppvz_reward + vw（pickup） |
| `PENALTY_KEYWORD` | `Штраф` | penalty |
| `STORAGE_KEYWORD` | `Хранение` | 跳过（nm_id=0，进未归属） |
| `DEDUCT_KEYWORD` | `Удержание` | 跳过（由广告 API 替代） |

---

## 已知注意事项

- **WR 与 WOD 净利差值**：差额 = 罚款 + 补收运费 + 自提点费用之和，属正常
- **仓储费全归出口区域**：若某商品当周仅有白俄销售，仓储费仍在出口行，出口行会显示负利润
- **`vw` 字段需 WeeklySync 填充**：`raw_wb_finance_details.vw` 由 `sync_finance_details`（WeeklySync 步骤）写入，手动补历史数据必须用 `WeeklySync`，不能用 `DailySync`
- **广告费按需补拉**：若 `ad_settled_fees` 缺数据，`ensure_ad_fees_synced!` 会自动触发 WeeklySync 补拉
- **别名表需手工维护**：新增 WB vendorCode ≠ sku_code 的 SKU 时，需更新 `VENDOR_CODE_ALIASES`
- **`import_vat`** 列输出保持 CNY（`import_vat_cny`），仅税务计算内部折算 BYN
