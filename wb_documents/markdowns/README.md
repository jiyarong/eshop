# WildBerries API 文档总结

> 调研日期：2026-04-28  
> 文档来源：https://dev.wildberries.ru/docs/openapi/

## 文档索引

| 文件 | 内容 |
|------|------|
| [01_overview.md](./01_overview.md) | API 概述、认证、限流、通用规则 |
| [02_products.md](./02_products.md) | 商品管理（内容、分类、卡片、价格、库存） |
| [03_orders_fbs.md](./03_orders_fbs.md) | FBS 订单（卖家仓发货） |
| [04_orders_dbs.md](./04_orders_dbs.md) | DBS 订单（卖家配送） |
| [05_orders_fbw.md](./05_orders_fbw.md) | FBW 供货（WB仓履约） |
| [06_in_store_pickup.md](./06_in_store_pickup.md) | 自取订单（Click-Collect） |
| [07_promotion.md](./07_promotion.md) | 营销推广（广告活动、促销） |
| [08_analytics.md](./08_analytics.md) | 数据分析（销售漏斗、搜索报告） |
| [09_reports.md](./09_reports.md) | 统计报表（库存、订单、销售） |
| [10_user_communication.md](./10_user_communication.md) | 用户沟通（问答、评价、聊天） |
| [11_financial_reports.md](./11_financial_reports.md) | 财务报表（余额、对账单、文档） |
| [db_schema.md](./db_schema.md) | 数据库结构设计 |

## WB 销售模式

WB 支持 4 种销售/履约模式：

| 模式 | 说明 |
|------|------|
| **FBS** (Fulfillment by Seller) | 卖家自有仓库存货，接单后送往 WB 分拣中心 |
| **DBS** (Delivery by Seller) | 卖家自行直接配送给买家 |
| **FBW** (Fulfillment by WB) | 卖家将货物提前存入 WB 仓库，WB 负责履约 |
| **Click-Collect** (自取) | 买家在卖家门店自提 |

## API 基础域名

| 分类 | 域名 |
|------|------|
| 商品内容 | `https://content-api.wildberries.ru` |
| 订单/仓储 | `https://marketplace-api.wildberries.ru` |
| FBW 供货 | `https://supplies-api.wildberries.ru` |
| 推广广告 | `https://advert-api.wildberries.ru` |
| 分析 | `https://seller-analytics-api.wildberries.ru` |
| 统计报表 | `https://statistics-api.wildberries.ru` |
| 评价/问答 | `https://feedbacks-api.wildberries.ru` |
| 财务 | `https://finance-api.wildberries.ru` |
