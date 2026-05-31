# DBS 订单 API（卖家自行配送）

**Base URL**: `https://marketplace-api.wildberries.ru`  
**Token 类别**: Маркетплейс  
**限流**: 300 req/min，200ms 间隔，Burst 20

---

## DBS 工作流程

```
新订单(new) → 确认开始打包(confirm) → 发货(deliver) → 已送达/拒收(receive/reject)
```

卖家自行将商品送达买家，WB 只负责撮合和结算。

---

## 一、订单管理

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v3/dbs/orders/new` | 获取所有新订单 |
| GET | `/api/v3/dbs/orders` | 获取已完成订单历史（最多30天） |
| POST | `/api/v3/dbs/groups/info` | 获取同一事务下的付费配送信息 |
| POST | `/api/v3/dbs/orders/client` | 获取买家信息 |
| POST | `/api/marketplace/v3/dbs/orders/b2b/info` | 获取 B2B 买家信息 |
| GET | `/api/v3/dbs/orders/delivery-date` | 获取订单预计送达日期 |

---

## 二、状态管理

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/marketplace/v3/dbs/orders/status/info` | 批量查询订单状态 |
| POST | `/api/marketplace/v3/dbs/orders/status/cancel` | 批量取消订单 |
| POST | `/api/marketplace/v3/dbs/orders/status/confirm` | 批量确认开始打包 |
| POST | `/api/marketplace/v3/dbs/orders/status/deliver` | 批量标记已发货 |
| POST | `/api/marketplace/v3/dbs/orders/status/receive` | 批量确认买家已收货 |
| POST | `/api/marketplace/v3/dbs/orders/status/reject` | 批量标记买家拒收 |
| POST | `/api/marketplace/v3/dbs/orders/stickers` | 获取快递单贴标（发往 WB 自提点时使用） |

---

## 三、元数据（强制标识）

与 FBS 一致，用于需要追溯的商品品类。

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/marketplace/v3/dbs/orders/meta/info` | 批量获取元数据 |
| POST | `/api/marketplace/v3/dbs/orders/meta/delete` | 批量删除元数据 |
| POST | `/api/marketplace/v3/dbs/orders/meta/sgtin` | 绑定 SGTIN |
| POST | `/api/marketplace/v3/dbs/orders/meta/uin` | 绑定 UIN |
| POST | `/api/marketplace/v3/dbs/orders/meta/imei` | 绑定 IMEI |
| POST | `/api/marketplace/v3/dbs/orders/meta/gtin` | 绑定 GTIN |
| POST | `/api/marketplace/v3/dbs/orders/meta/customs-declaration` | 绑定报关单号 |

---

## DBS 与 FBS 的主要区别

| 维度 | FBS | DBS |
|------|-----|-----|
| 仓库 | 卖家仓 → WB 分拣中心 | 卖家仓 → 买家 |
| 贴标 | WB 统一格式 | 用 `/stickers` 接口获取 |
| 付费配送 | 无 | 有（通过 groups/info 查询） |
| 供货单 | 需要创建 Supply | 不需要 |
| B2B | 不涉及 | 支持 B2B 信息接口 |
