# FBS 订单 API（卖家仓发货）

**Base URL**: `https://marketplace-api.wildberries.ru`  
**Token 类别**: Маркетплейс  
**限流**: 300 req/min，200ms 间隔，Burst 20（Personal/Service）；409 错误计 10 次

---

## FBS 工作流程

```
新订单(new) → 加入供货单(confirm) → 打包&贴标 → 送达 WB 分拣中心(complete)
                                                  ↑
                                           支持按箱打包(trbx)
```

---

## 一、订单管理

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v3/orders/new` | 获取所有新订单（当前时刻待处理） |
| GET | `/api/v3/orders` | 获取订单历史（最多30天，游标分页） |
| POST | `/api/v3/orders/status` | 批量查询订单状态 |
| GET | `/api/v3/supplies/orders/reshipment` | 获取需要补发的订单 |
| PUT | `/api/v3/orders/{orderId}/cancel` | 取消订单 |
| POST | `/api/v3/orders/stickers` | 获取订单贴标（PDF/SVG/ZPL） |
| POST | `/api/v3/orders/stickers/cross-border` | 跨境订单贴标 |
| GET | `/api/v3/orders/status/history` | 跨境订单状态历史 |
| POST | `/api/v3/orders/client` | 获取买家信息（订单维度） |

**订单状态（supplierStatus）**:

| 状态 | 描述 | 触发方式 |
|------|------|----------|
| `new` | 新订单 | 系统生成 |
| `confirm` | 打包中 | 将订单加入供货单 |
| `complete` | 已发货 | 将供货单传递发货 |
| `cancel` | 卖家取消 | 调用取消接口 |
| `cancel_carrier` | 承运商取消（仅跨境） | 承运商操作 |

**wbStatus（WB 系统内部状态）**:
- `waiting` - 等待中
- `sorted` - 已分拣
- `delivered` - 已送达
- `declined` - 已拒收

**订单核心字段**:
```json
{
  "id": 987654321,           // 订单 ID（sborochnoye zadaniye ID）
  "orderUid": "uuid-string", // 订单 UUID
  "article": "MY-SKU-001",   // 卖家 SKU
  "colorCode": "",
  "rid": "xxx",              // 外部参考 ID
  "createdAt": "2024-01-01T10:00:00Z",
  "offices": ["Коледино"],   // 目标 WB 仓库
  "skus": ["4607133781434"],
  "id": 987654321,
  "warehouseId": 123,        // 卖家仓库 ID
  "nmId": 12345678,          // WB 商品 ID
  "chrtId": 99887766,        // 规格 ID
  "price": 115000,           // 金额（分）
  "convertedPrice": 115000,
  "currencyCode": 643,       // RUB
  "deliveryType": "fbs",
  "comment": "",
  "scanPrice": null,
  "isZeroOrder": false,
  "requiredMeta": ["sgtin"], // 必填元数据类型
  "optionalMeta": ["imei"],  // 选填元数据类型
  "userInfo": { "id": 0 }
}
```

---

## 二、元数据（Маркировка）

用于强制标识追踪（医药/烟草/鞋类/电子等）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/marketplace/v3/orders/meta` | 批量获取订单元数据 |
| DELETE | `/api/v3/orders/{orderId}/meta` | 删除订单元数据 |
| PUT | `/api/v3/orders/{orderId}/meta/sgtin` | 绑定商品标识码（SGTIN） |
| PUT | `/api/v3/orders/{orderId}/meta/uin` | 绑定 UIN（唯一识别码） |
| PUT | `/api/v3/orders/{orderId}/meta/imei` | 绑定 IMEI |
| PUT | `/api/v3/orders/{orderId}/meta/gtin` | 绑定 GTIN |
| PUT | `/api/v3/orders/{orderId}/meta/expiration` | 绑定保质期 |
| PUT | `/api/marketplace/v3/orders/{orderId}/meta/customs-declaration` | 绑定报关单号（GTD） |

---

## 三、供货单（供货 Supply）

供货单是将多个订单打包在一起发往 WB 仓库的容器。

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v3/supplies` | 创建新供货单 |
| GET | `/api/v3/supplies` | 获取供货单列表 |
| POST | `/api/marketplace/v3/supplies/{supplyId}/orders` | 向供货单添加订单 |
| GET | `/api/v3/supplies/{supplyId}` | 获取供货单详情 |
| DELETE | `/api/v3/supplies/{supplyId}` | 删除供货单 |
| GET | `/api/marketplace/v3/supplies/{supplyId}/order-ids` | 获取供货单内订单 ID 列表 |
| PATCH | `/api/v3/supplies/{supplyId}/deliver` | 将供货单传递到发货（提交发货） |
| GET | `/api/v3/supplies/{supplyId}/barcode` | 获取供货单 QR 码 |

**供货单字段**:
```json
{
  "id": "WB-GI-XXXXXXXX",  // 供货单 ID
  "done": false,
  "createdAt": "2024-01-01T10:00:00Z",
  "closedAt": null,
  "scanDt": null,
  "name": "my-supply-1",
  "type": "fbs"
}
```

---

## 四、箱子管理（Trbx）

用于多件合一箱装发货。

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v3/supplies/{supplyId}/trbx` | 获取供货单箱子列表 |
| POST | `/api/v3/supplies/{supplyId}/trbx` | 向供货单添加箱子 |
| DELETE | `/api/v3/supplies/{supplyId}/trbx` | 从供货单移除箱子 |
| POST | `/api/v3/supplies/{supplyId}/trbx/stickers` | 获取箱子贴标 |

---

## 五、通行证（车辆进入仓库）

部分 WB 仓库需要提前申请车辆通行证。

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v3/passes/offices` | 获取需要通行证的仓库列表 |
| GET | `/api/v3/passes` | 获取通行证列表 |
| POST | `/api/v3/passes` | 创建通行证 |
| PUT | `/api/v3/passes/{passId}` | 更新通行证 |
| DELETE | `/api/v3/passes/{passId}` | 删除通行证 |
