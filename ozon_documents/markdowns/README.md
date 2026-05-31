# Ozon Seller API 文档索引

**API 版本**: 2.1（369 个接口）  
**来源**: [Ozon Seller API OpenAPI Spec](https://github.com/miilv/ozon-seller-api-skill)  
**Base URL**: `https://api-seller.ozon.ru`  
**认证**: 请求 Header 中携带 `Client-Id` 和 `Api-Key`

---

## 文档列表

| 文件 | 接口数 | 说明 |
|------|--------|------|
| [01_overview.md](01_overview.md) | 7 | 概览与认证（角色、Token、权限） |
| [02_products.md](02_products.md) | 41 | 商品管理（上传、编辑、属性、条形码、品牌） |
| [03_prices_stocks.md](03_prices_stocks.md) | 22 | 价格、折扣、库存更新 |
| [04_warehouses.md](04_warehouses.md) | 24 | 仓库管理（FBS 仓库配置、配送区域） |
| [05_orders_fbs.md](05_orders_fbs.md) | 75 | FBS 订单（卖家仓发货，最复杂） |
| [06_orders_fbo.md](06_orders_fbo.md) | 25 | FBO 订单（Ozon 仓发货） |
| [07_orders_fbp.md](07_orders_fbp.md) | 45 | FBP/DBS 订单（快递上门/自提点） |
| [08_returns.md](08_returns.md) | 20 | 退货与取消 |
| [09_communication.md](09_communication.md) | 19 | 聊天、评价、问答 |
| [10_promotions.md](10_promotions.md) | 38 | 促销活动、满减、溢价 |
| [11_analytics.md](11_analytics.md) | 6 | 销售数据分析 |
| [12_reports.md](12_reports.md) | 15 | 异步报表任务 |
| [13_finance.md](13_finance.md) | 13 | 财务流水、对账报表 |
| [14_logistics.md](14_logistics.md) | 5 | Ozon 物流配送 |
| [15_other.md](15_other.md) | 14 | 数字商品、通知推送、Beta 接口 |
| [db_schema.md](db_schema.md) | — | raw_ozon_* 建议表结构（19 张表） |

---

## 核心概念

### 发货模式（Delivery Schema）

| 模式 | 说明 |
|------|------|
| **FBO** | Ozon 仓发货（Fulfillment by Ozon）— 商品存放 Ozon 仓库，Ozon 完成打包配送 |
| **FBS** | 卖家仓发货（Fulfillment by Seller）— 商品在卖家仓库，卖家打包后交给 Ozon 物流 |
| **rFBS** | 卖家仓发货（第三方物流）— 卖家使用自选快递公司 |
| **FBP/DBS** | 自提点/上门自提（Draft-Based Posting）— 用户到自提点或安排上门取货 |

### 核心实体关系

```
Category (类目)
    └── Product (商品, offer_id)
            ├── ProductPrice (价格)
            ├── ProductStock (库存, 按仓库)
            └── Posting (发货单, posting_number)
                    ├── PostingItem[] (商品明细)
                    ├── Return (退货)
                    └── FinanceTransaction (财务流水)
```

### 关键 ID 说明

| 字段 | 含义 |
|------|------|
| `offer_id` | 卖家自定义 SKU，跨平台的业务主键 |
| `sku` (整数) | Ozon 内部 SKU ID，同一商品在不同仓库可能有不同 sku |
| `product_id` | Ozon 商品 ID（= `id` in product info），与 sku 的关系是 1:N |
| `posting_number` | 发货单唯一号（如 `12345678-0001-1`），相当于 WB 的 `order_uid` |
| `order_number` | 订单号（一个 order 可拆成多个 posting） |

### 与 WB 对比

| 维度 | Wildberries | Ozon |
|------|------------|------|
| 订单键 | `order_uid`（1行=1件商品） | `posting_number`（1行含多件） |
| 统计 API | 需要 `g_number` 关联 | 直接在 posting 中 |
| 仓库 | WB 统一仓 + 卖家仓 | FBO + FBS + rFBS + FBP |
| 认证 | 单 Token | Client-Id + Api-Key 组合 |
| 限流 | 300 req/min（部分接口） | 按接口不同（1–60 req/s） |
