# Wildberries API 文档 — 综合导读

> 本文档是整个 `docs/platfom_apis/wb/` 目录的入口和索引，帮助快速定位需要的 API 文档。
>
> 文件编号规则：`01`–`11`，按业务场景分类，无严格依赖顺序。

---

## 一、文件一览

| # | 文件名 | 中文标题 | 行数 | 核心 Base URL | Token 分类 |
|---|--------|----------|------|---------------|------------|
| 01 | `01-dbs-orders.md` | DBS 订单 API | 833 | `https://marketplace-api.wildberries.ru` | Marketplace |
| 02 | `02-fbs-orders.md` | FBS 订单 API | 838 | `https://marketplace-api.wildberries.ru` | Marketplace |
| 03 | `03-dbw-orders.md` | DBW 订单 API | 476 | `https://marketplace-api.wildberries.ru` | Marketplace |
| 04 | `04-product-management.md` | 商品管理 API | 930 | `https://content-api.wildberries.ru` | Content |
| 05 | `05-customer-communication-api.md` | 客户沟通 API | 1124 | `https://marketplace-api.wildberries.ru` | Marketplace |
| 06 | `06-data-api.md` | 数据/分析 API | 1148 | `https://seller-analytics-api.wildberries.ru` | Analytics |
| 07 | `07-fbw_supplies_api.md` | FBW 供货 API | 646 | `https://supplies-api.wildberries.ru` | Supplies |
| 08 | `08-in_store_orders_api.md` | 店内自提 API | 973 | `https://marketplace-api.wildberries.ru` | Marketplace |
| 09 | `09-marketing_api.md` | 营销与广告 API | 1502 | 多域名（见下文） | Promotion / 其他 |
| 10 | `10-reports_api.md` | 报表 API | 1611 | `https://statistics-api.wildberries.ru` / `https://seller-analytics-api.wildberries.ru` | Statistics / Analytics |
| 11 | `11-tariffs-api.md` | 费率与佣金 API | 457 | `https://common-api.wildberries.ru` | 任意 Token |

---

## 二、按业务场景快速定位

### 订单处理

| 场景 | 入口文件 |
|------|----------|
| DBS（自发货）订单全生命周期 | [`01-dbs-orders.md`](./01-dbs-orders.md) |
| FBS（商家发货）订单全生命周期 | [`02-fbs-orders.md`](./02-fbs-orders.md) |
| DBW（商家仓配货）订单全生命周期 | [`03-dbw-orders.md`](./03-dbw-orders.md) |
| 店内自提（In-Store Pickup）装配订单 | [`08-in_store_orders_api.md`](./08-in_store_orders_api.md) |

### 商品与内容

| 场景 | 入口文件 |
|------|----------|
| 商品创建、编辑、分类、特性、媒体、价格、库存 | [`04-product-management.md`](./04-product-management.md) |

### 客服与沟通

| 场景 | 入口文件 |
|------|----------|
| 聊天消息、模板、通知、文件上传、评价回复 | [`05-customer-communication-api.md`](./05-customer-communication-api.md) |

### 仓储与供货

| 场景 | 入口文件 |
|------|----------|
| FBW（Fulfillment by WB）供货计划、箱单、标签 | [`07-fbw_supplies_api.md`](./07-fbw_supplies_api.md) |

### 营销推广

| 场景 | 入口文件 |
|------|----------|
| 广告活动管理、出价、关键词、搜索词、统计、媒体素材、促销日历、商品推荐 | [`09-marketing_api.md`](./09-marketing_api.md) |

### 数据分析

| 场景 | 入口文件 |
|------|----------|
| 销售漏斗分析、搜索词分析、商品卡分析、竞品分析、RFM、AB 测试 | [`06-data-api.md`](./06-data-api.md) |

### 报表（异步下载）

| 场景 | 入口文件 |
|------|----------|
| 库存/订单/销售报表、仓库库存、强制标签商品、留存率、扣款、入库、退货、缺货 | [`10-reports_api.md`](./10-reports_api.md) |

### 费率与成本

| 场景 | 入口文件 |
|------|----------|
| 佣金比例、仓储费（箱/托盘）、供货费、退货费 | [`11-tariffs-api.md`](./11-tariffs-api.md) |

---

## 三、Base URL 速查

| Base URL | 所属 API | 文件 |
|----------|----------|------|
| `https://marketplace-api.wildberries.ru` | 订单、客户沟通、店内自提 | `01` `02` `03` `05` `08` |
| `https://content-api.wildberries.ru` | 商品管理、商品推荐 | `04` `09` |
| `https://seller-analytics-api.wildberries.ru` | 数据分析、Seller Analytics 报表 | `06` `10` |
| `https://statistics-api.wildberries.ru` | Statistics 报表 | `10` |
| `https://advert-api.wildberries.ru` | 广告活动/推广/统计 | `09` |
| `https://advert-media-api.wildberries.ru` | 媒体广告素材 | `09` |
| `https://dp-calendar-api.wildberries.ru` | 促销日历 | `09` |
| `https://supplies-api.wildberries.ru` | FBW 供货 | `07` |
| `https://common-api.wildberries.ru` | 费率/佣金 | `11` |

---

## 四、Token 分类与文件对应

| Token 分类 | 适用文件 | 说明 |
|------------|----------|------|
| Marketplace | `01` `02` `03` `05` `08` | 订单、客服、自提类 API |
| Content | `04` | 商品管理；部分 `09`（Recommendations）需要此分类及高级订阅 |
| Analytics | `06` `10`（部分） | 数据分析和 Seller Analytics 报表 |
| Statistics | `10`（主要部分） | 统计报表（Main Reports） |
| Promotion | `09` | 广告活动管理、统计、搜索词等 |
| Supplies | `07` | FBW 供货 |
| Prices and Discounts | `09`（促销日历） | 促销日历 API |
| 任意 Token | `11` | 费率/佣金 |
| 需要特殊权限 | `09`（Recommendations） | 需要 Advanced/Premium Jam 订阅或 Plan Builder 对应选项 |

---

## 五、各文件详细概要

### 01 — `01-dbs-orders.md` (DBS Orders API)

- **类似平台逻辑**：淘宝/拼多多商家自己联系物流发货
- **核心流程**：获取新订单 → 接受订单 → 创建发货 → 打印标签 → 标记发货 → 完成
- **主要 endpoints**：
  - `GET /api/v3/orders/new` — 获取新订单（支持 srid）
  - `POST /api/v3/orders/{id}/accept` — 接受/拒绝订单
  - `POST /api/v3/orders/{id}/cancel` — 取消订单
  - `POST /api/v3/orders/stickers` — 创建/获取标签
  - `PUT /api/v3/orders/{id}/meta/shipOrder` — 标记发货（支持单件/多件）
  - `POST /api/v3/orders/{id}/complete` — 完成订单
- **特色**：支持 SRID 替代方案、多包裹发货、COGS（已废弃）、集成方地址确认

### 02 — `02-fbs-orders.md` (FBS Orders API)

- **类似平台逻辑**：商家把货送到 WB 仓库，由 WB 配送
- **核心流程**：获取新订单 → 创建供货计划 → 打包 → 打印标签/码 → 标记发货 → 跟踪状态
- **主要 endpoints**：
  - `GET /api/v3/orders/new` — 获取新订单
  - `POST /api/v3/orders/{id}/cancel` — 取消订单（买方/卖方）
  - `POST /api/v3/orders/stickers` — 创建标签
  - `POST /api/v3/orders/{id}/meta/shipOrder` — 标记发货（含装箱编码）
  - `GET /api/v3/supplies` — 获取供货列表
  - `POST /api/v3/supplies` — 创建供货
- **特色**：装箱码（barcode）管理、供货（Supply）概念、多重标签（单/多箱）

### 03 — `03-dbw-orders.md` (DBW Orders API)

- **类似平台逻辑**：商家在自己的仓库配货，WB 上门取件
- **核心流程**：获取新订单 → 打包（包装确认） → WB 取货 → 交接 → 完成
- **主要 endpoints**：
  - `GET /api/v3/orders/new` — 获取新订单
  - `POST /api/v3/orders/{id}/cancel` — 取消订单
  - `POST /api/v3/orders/{id}/meta/shipOrder` — 标记发货（出库确认）
  - `POST /api/v3/orders/pack` — 包装确认（传递体积/重量）
  - `GET /api/v3/orders/{id}` — 获取订单详情（含 pickup 信息）
- **特色**：需要「包装确认」步骤传递包裹尺寸和重量，WB 据此安排取货

### 04 — `04-product-management.md` (Product Management API)

- **核心**：商品的完整生命周期管理，是运营人员最常用的 API 分组
- **主要模块**：
  - 商品卡片管理 — 创建/编辑/获取/删除（`/api/v3/merchant/...`）
  - 分类与特性（`/api/v3/parent/subject`、特性字典）
  - 媒体管理 — 图片上传（S3 直传/字节流）、视频
  - 价格管理 — 设置价格、折扣、促销价
  - 库存管理 — 更新/获取库存（`/api/v3/stocks/...`）
  - 仓库管理 — 获取仓库列表、COGS（已废弃）
  - 商品信息增强 — 自定义参数、Templates、评级、标签
  - 高级搜索/筛选
- **特色**：价格和折扣接口多版本并存（V2/V3），部分已废弃需注意

### 05 — `05-customer-communication-api.md` (Customer Communication API)

- **核心**：与买家沟通的全套渠道
- **主要模块**：
  - 聊天（Chats）— 获取/发送消息、上传文件、已读标记
  - 消息模板（Templates）— 管理预设回复模板
  - 聊天室管理（Rooms）— 创建/转接/关闭
  - 通知管理（Notifications）— 发送推送通知
  - 文件上传 — 上传图片/文件供聊天使用
  - 评价管理（Feedbacks）— 获取评价、回复评价、查看统计
  - 评价问题（Questions）— 获取/回答买家提问
- **特色**：Webhook 支持（消息/评价等事件通知）、评价管理含统计与回复

### 06 — `06-data-api.md` (Analytics and Data API)

- **核心**：Wildberries 数据分析能力，辅助运营决策
- **主要模块**：
  - 销售漏斗（Sales Funnel）— 从浏览到购买的全链路转化
  - 搜索词分析（Search Phrases）— 搜索词表现、关联搜索词
  - 商品卡分析（Card Analysis）— 单品流量/转化数据
  - 竞品分析（Competitors）— 对标商品、品类分析
  - RFM 分析 — 用户分层
  - AB 测试 — 商品卡 A/B 测试管理
  - 广告商数据 — DAP（已废弃）、媒体广告指标
  - 报告与导出 — 数据导出功能
- **特色**：大部分接口需要 Analytics 分类 Token；包含已废弃接口需注意

### 07 — `07-fbw_supplies_api.md` (FBW Supplies API)

- **核心**：Fulfillment by Wildberries 的供货流程
- **主要模块**：
  - 供货计划（Supplies）— 创建/获取/编辑
  - 箱单管理（Boxes）— 添加到供货计划、打印标签
  - 供货标签（Supply Labels）— 生成/打印标签及 QR 码
  - 供货文档 — 生成供货文档 PDF
- **特色**：专用 Base URL（`supplies-api.wildberries.ru`），专属于 FBW 场景

### 08 — `08-in_store_orders_api.md` (In-Store Pickup API)

- **核心**：线下自提（店内取货）场景的订单管理
- **主要模块**：
  - 装配订单（Assembly Orders）— 获取/转入/通知可取货/核验买家/收货/拒收
  - 标签标识符（Labels）— 获取 Chestny ZNAK/UIN/IMEI/GTIN 标识详情及删除
- **流程**：获取新订单 → 转入装配 → 获取买家信息 → 通知可取货 → 核验收货人 → 通知收货/拒收
- **特色**：一个完整的线下交付流程闭环；涉及俄罗斯强制标签法规（Chestny ZNAK）

### 09 — `09-marketing_api.md` (Marketing and Promotions API)

- **核心**：广告投放与促销推广
- **主要模块**：
  - 广告活动（Campaigns）— 创建/管理/统计
  - 广告投放管理 — 出价、预算、时段、地域
  - 搜索词（Search Clusters）— 关键词管理、搜索词报告
  - 广告统计（Statistics）— 广告效果数据
  - 媒体素材（Media）— 广告图片/视频管理
  - 财务（Finances）— 广告支出/充值
  - 促销日历（Promotions Calendar）— 获取促销活动时间表
  - 商品推荐（Recommendations）— 推荐商品设置
- **特色**：涉及 4 个不同 Base URL；Promotion Token 为主；部分功能需要高级订阅

### 10 — `10-reports_api.md` (Reports API)

- **核心**：异步报表下载，适合数据导出与对账
- **主要模块**：
  - Main Reports（Statistics API）— 库存(旧)、订单、销售报表
  - 仓库库存报表（Warehouses Inventory）
  - 强制标签商品报表
  - 留存率报表（Retention Reports）
  - 扣款报表（Deduction Reports）
  - 入库报表
  - 退货报表（Returns Reports）
  - 缺货报表
  - Self-Employed Reports
- **特点**：多数报表使用异步模式（先 `POST` 创建任务，轮询状态，再下载结果）；部分接口为新旧版本并存

### 11 — `11-tariffs-api.md` (Tariffs API)

- **核心**：费用查询，适合做成本核算
- **主要接口**：
  - `GET /api/v1/tariffs/commission` — 商品类目佣金比例
  - `GET /api/v1/tariffs/box` — 箱式仓储费
  - `GET /api/v1/tariffs/pallet` — 托盘仓储费
  - `GET /api/v1/tariffs/supply` — 供货费
  - `GET /api/v1/tariffs/return` — 退货费（退给商家）
- **特色**：任意 Token 均可用；个人 Token 限流宽松，Base Token 限流最严；支持多语言 `locale` 参数

---

## 六、鉴权方式

所有 API 统一使用 **HeaderApiKey** 鉴权：

```
Authorization: Bearer <your-api-token>
```

Token 在 [WB 开发者后台](https://dev.wildberries.ru/) 创建，需根据目标 API 选择正确的 Token 分类（见第四章）。

---

## 七、限流规则概览

各 API 限流策略各不相同，常见模式：

| 模式 | 示例 |
|------|------|
| 固定窗口（XX 请求 / YY 分钟） | 大部分订单/商品 API |
| 突发配额（Burst） | 费率 API（个人 Token 2 burst） |
| 全局/应用级限流 | 数据/分析 API 通常按应用限制 |
| 异步报表轮询建议间隔 | 报表 API 通常建议 1–5 分钟轮询 |

> 具体限流参数请查阅各文件对应章节，不要假设统一限流标准。

---

## 八、编辑说明

- 所有文档按 `XX-英文短名.md` 命名，使用中文编写。
- 文档整理来源为 Wildberries 官方 OpenAPI 规范（`.html.md` 格式）和官方开发者文档。
- 在代码中集成时，应直接查阅对应编号文件中的 endpoint 详情、参数表、请求/响应示例。
