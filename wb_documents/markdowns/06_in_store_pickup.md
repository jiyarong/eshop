# 自取订单 API（Click-Collect）

**Base URL**: `https://marketplace-api.wildberries.ru`  
**Token 类别**: Маркетплейс  
**限流**: 300 req/min，200ms 间隔，Burst 20

---

## 说明

Click-Collect（自取）是买家在卖家的实体门店或指定自取点提货的模式。

---

## 工作流程

```
新订单 → 确认打包(confirm) → 准备好取货(prepare) → 买家取货(receive) 或 买家拒收(reject)
```

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v3/click-collect/orders/new` | 获取新订单列表 |
| GET | `/api/v3/click-collect/orders` | 获取已完成订单历史 |
| POST | `/api/marketplace/v3/click-collect/orders/status/confirm` | 批量确认打包 |
| POST | `/api/marketplace/v3/click-collect/orders/status/prepare` | 批量标记已准备好取货 |
| POST | `/api/marketplace/v3/click-collect/orders/status/receive` | 批量确认已取货 |
| POST | `/api/marketplace/v3/click-collect/orders/status/reject` | 批量标记拒取 |
| POST | `/api/marketplace/v3/click-collect/orders/status/cancel` | 批量取消订单 |
| POST | `/api/marketplace/v3/click-collect/orders/status/info` | 批量查询状态 |
| POST | `/api/v3/click-collect/orders/client` | 获取买家信息 |
| POST | `/api/v3/click-collect/orders/client/identity` | 验证订单归属买家（防欺诈） |

---

## 元数据接口

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/marketplace/v3/click-collect/orders/meta/info` | 批量获取元数据 |
| POST | `/api/marketplace/v3/click-collect/orders/meta/delete` | 批量删除元数据 |
| POST | `/api/marketplace/v3/click-collect/orders/meta/sgtin` | 绑定 SGTIN |
| POST | `/api/marketplace/v3/click-collect/orders/meta/uin` | 绑定 UIN |
| POST | `/api/marketplace/v3/click-collect/orders/meta/imei` | 绑定 IMEI |
| POST | `/api/marketplace/v3/click-collect/orders/meta/gtin` | 绑定 GTIN |

> **注意**: 旧版接口（单订单操作）已标记为 `Deprecated`，建议使用批量接口。
