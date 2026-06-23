# Wildberries DBW Orders API

> **DBW (Delivery by WB Courier)** — WB 快递员配送模式
>
> Base URL: `https://marketplace-api.wildberries.ru`
>
> Token 类型: **Marketplace**
>
> 功能：管理 DBW 配货订单、状态、标签标识

---

## 目录

- [DBW Assembly Orders](#dbw-assembly-orders)
- [DBW Label Identifiers](#dbw-label-identifiers)

---

## DBW Assembly Orders

### 工作流程

1. [获取新订单](#1-get-new-orders)
2. [转配货](#6-transfer-to-assembly)（status → `confirm`）
3. 获取[快递员信息](#9-courier-info），将仓库联系人绑定到仓库
4. [获取、打印贴纸](#7-get-orders-stickers)
5. [转发货](#8-transfer-assembly-orders-to-delivery)（status → `complete`）
6. 等待快递员取件并配送
7. 买家签收 → `receive`；拒收 → `reject`

### 状态说明

**supplierStatus**（由卖家触发）：

| 状态 | 说明 | 进入方式 |
|------|------|----------|
| `new` | 新订单 | — |
| `confirm` | 配货中 | 调用转配货 |
| `complete` | 配送中 | 调用转发货 |
| `receive` | 买家已收货 | 快递员更改 |
| `reject` | 买家拒收 | 快递员更改 |
| `cancel` | 卖家取消 | 调用取消 |
| `cancel_missed_call` | 无法联系买家取消 | 自动 |

**wbStatus**: `waiting`, `sold`, `canceled`, `canceled_by_client`, `declined_by_client`, `defect`, `canceled_by_missed_call`, `postponed_delivery`

> DBW 方法统一限速（联系人列表、标签标识获取/删除、配货订单）：1 分钟 300 请求，间隔 200 ms，突发 20 请求。4XX 计为 10 次。

---

### 1. GET New Orders

```
GET /api/v3/dbw/orders/new
```

**描述**: 返回当前所有新 DBW 订单。

**认证**: `HeaderApiKey`

**响应码**: `200` Success | `401` | `402` | `403` | `429`

**响应示例 (200)**:

```json
{
  "orders": [{
    "address": { "fullAddress": "...", "longitude": 44.519068, "latitude": 40.20192 },
    "salePrice": 504600,
    "requiredMeta": ["uin"],
    "comment": "Упакуйте в пленку, пожалуйста",
    "options": { "isB2b": true },
    "orderUid": "165918930_629fbc924b984618a44354475ca58675",
    "groupId": "7a2c8810-1db2-4011-9682-5c7fa33afd83",
    "article": "one-ring-7548",
    "colorCode": "RAL 3017",
    "rid": "f884001e44e511edb8780242ac120002",
    "createdAt": "2022-05-04T07:56:29Z",
    "skus": ["6665956397512"],
    "id": 13833711,
    "warehouseId": 658434,
    "nmId": 123456789,
    "chrtId": 987654321,
    "price": 1014,
    "convertedPrice": 1014,
    "currencyCode": 933,
    "convertedCurrencyCode": 643,
    "cargoType": 1,
    "isZeroOrder": false
  }]
}
```

---

### 2. GET Get Information on Completed Orders

```
GET /api/v3/dbw/orders
```

**描述**: 返回已完成订单（已取消或已售出）。单次最多查询 30 天。

**Query 参数**:

| 参数 | 必填 | 说明 |
|------|------|------|
| `limit` | 是 | integer [1..1000] |
| `next` | 是 | integer <int64>，从 0 开始 |
| `dateFrom` | 是 | integer，Unix 时间戳 |
| `dateTo` | 是 | integer，Unix 时间戳 |

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

---

### 3. POST Get Delivery Date and Time

```
POST /api/v3/dbw/orders/delivery-date
```

**描述**: 获取买家选择的配送日期和时间。

**请求体**:

```json
{"orders": [1234567890]}
```

**响应示例 (200)**:

```json
{
  "orders": [{
    "dTimeFrom": "11:11",
    "dTimeTo": "22:22",
    "dTimeFromOld": "12:30",
    "dTimeToOld": "22:30",
    "dDateOld": "2025-01-28",
    "dDate": "2025-02-20",
    "id": 1234567890
  }]
}
```

---

### 4. POST Buyer Information

```
POST /api/marketplace/v3/dbw/orders/client
```

**描述**: 根据订单 ID 返回买家信息。

**请求体**: `{"orders": [987654321,123456789]}`

**响应示例 (200)**:

```json
{
  "orders": [{
    "replacementPhone": "79871234567",
    "phone": "+79871234567",
    "firstName": "Иван",
    "fullName": "Иванов Иван Иванович",
    "additionalPhones": ["1234554321"],
    "additionalPhoneCodes": [12345],
    "orderId": 1345678910,
    "phoneCode": 0
  }]
}
```

---

### 5. POST Get Orders Statuses

```
POST /api/v3/dbw/orders/status
```

**描述**: 根据订单 ID 列表返回订单状态。

**请求体**: `{"orders": [5632423]}`

**响应示例 (200)**:

```json
{
  "orders": [{
    "id": 5632423,
    "supplierStatus": "new",
    "wbStatus": "string"
  }]
}
```

---

### 6. PATCH Transfer to Assembly

```
PATCH /api/v3/dbw/orders/{orderId}/confirm
```

**描述**: 将订单转至 `confirm`（配货中）。

**Path 参数**: `orderId` — 订单 ID

**响应码**: `204` Confirmed | `400` | `401` | `402` | `403` | `404` | `409` | `429`

---

### 7. POST Get Orders Stickers

```
POST /api/v3/dbw/orders/stickers
```

**描述**: 返回 DBW 订单贴纸。支持 SVG、ZPLV、ZPLH、PNG。

**限制**:

- 单次最多 100 个订单
- 仅 `confirm` 和 `complete` 状态
- 尺寸：580x400（58x40）或 400x300（40x30）

**Query 参数**:

| 参数 | 必填 | 说明 |
|------|------|------|
| `type` | 是 | Enum: `svg`, `zplv`, `zplh`, `png` |
| `width` | 是 | Enum: 58, 40 |
| `height` | 是 | Enum: 40, 30 |

**请求体**: `{"orders": [5346346]}`

**响应示例 (200)**:

```json
{
  "stickers": [{
    "orderId": 5346346,
    "partA": "231648",
    "partB": "97523",
    "barcode": "!uKEtQZVx",
    "file": "<base64/SVG>"
  }]
}
```

---

### 8. POST Transfer Assembly Orders to Delivery

```
POST /api/marketplace/v3/dbw/orders/status/deliver
```

**描述**: 将 `confirm` 状态订单转至 `complete`（配送中）。

**请求体**: `{"ordersIds": [1234678898]}`

**响应示例 (200)**:

```json
{
  "requestId": "03615778-eb9e-4f55-b4Of-fd3ac0fad2сc",
  "results": [{
    "orderId": 42131238,
    "isError": true,
    "errors": [{"code": 409, "detail": "MetaValidationFail", "metaDetails": [{"key": "sgtin", "value": "1234567890123", "decision": "sgtinInvalidFormat"}]}]
  }, {
    "orderId": 4279781545,
    "isError": false
  }]
}
```

---

### 9. POST Courier Info

```
POST /api/v3/dbw/orders/courier
```

**描述**: 根据订单 ID 返回快递员联系信息和车牌号。适用于 `confirm` 和 `complete` 状态。

**请求体**: `{"orders": [987654321,123456789]}`

**响应示例 (200)**:

```json
{
  "orders": [{
    "courierInfo": {
      "contacts": {
        "carNumber": "х111хх11",
        "fullName": "Иванов Иван Иванович",
        "phone": "71230971931",
        "pTimeFrom": "2025-09-06T08:00:00Z",
        "pTimeTo": "2025-09-06T11:00:00Z"
      },
      "mustBeAssigned": true,
      "updatedAt": "2025-09-06T11:33:10+03:00"
    },
    "orderID": 2876979713
  }]
}
```

---

### 10. PATCH Cancel the Order

```
PATCH /api/v3/dbw/orders/{orderId}/cancel
```

**描述**: 将订单移至 `cancel`（卖家取消）。

**Path 参数**: `orderId`

**响应码**: `204` Canceled | `400` | `401` | `402` | `403` | `404` | `409` | `429`

**限速**: Personal/Service/Base with secret：1 分钟 300 请求；Base：1 小时 10 请求

---

## DBW Label Identifiers

> 用于管理 DBW 订单的标签标识。
>
> 支持的标识：`imei`、`uin`、`gtin`、`sgtin`（Честный ЗНАК）

---

### 1. POST Get Order Label Identifiers

```
POST /api/marketplace/v3/dbw/orders/meta/details
```

**描述**: 返回订单标签标识及其验证状态。

**请求体**: `{"ordersIds": [1234678898]}`

**响应示例 (200)**:

```json
{
  "requestId": "f1787bd2d1fdс35d6f537316514у4a05",
  "orders": [{
    "orderId": 123456,
    "isError": false,
    "errors": [],
    "metaDetails": [{"key": "sgtin", "value": "123456789012345", "decision": "sgtinIntroduced"}]
  }]
}
```

---

### 2. POST Delete Assembly Orders Label Identifiers

```
POST /api/marketplace/v3/dbw/orders/meta/delete
```

**描述**: 删除指定类型的标签标识值。每次请求只能删除一种类型。

**请求体**:

```json
{
  "key": "sgtin",
  "ordersIds": [123456789]
}
```

**key 枚举**: `imei`, `uin`, `gtin`, `sgtin`

---

### 3. GET Get Order Label Identifiers (Deprecated)

```
GET /api/v3/dbw/orders/{orderId}/meta
```

**描述**: ⚠️ 已弃用，将于 7 月 27 日移除。请使用 [POST /api/marketplace/v3/dbw/orders/meta/details](#1-post-get-order-label-identifiers)。

**Path 参数**: `orderId`

---

### 4. POST Add Labeling Codes Chestny ZNAK to Assembly Orders

```
POST /api/marketplace/v3/dbw/orders/meta/sgtin
```

**描述**: 设置 Честный ЗНАK 数据矩阵码。仅适用于 `confirm` 状态且 `sgtin` 在标识列表中的订单。

**请求体**:

```json
{
  "orders": [{
    "orderId": 123456,
    "sgtins": ["123456789012345678", "1234567890123456"]
  }]
}
```

**响应示例 (200)**:

```json
{
  "requestId": "03615778-eb9e-4f55-b4Of-fd3ac0fad2сc",
  "results": [{
    "orderId": 42131238,
    "isError": true,
    "errors": [{"code": 409, "detail": "FailedToUpdateMeta"}]
  }, {
    "orderId": 4279781545,
    "isError": false
  }]
}
```

---

### 5. PUT Add UIN to the Order

```
PUT /api/v3/dbw/orders/{orderId}/meta/uin
```

**描述**: 设置 UIN。一个订单只能有一个 UIN，仅适用于 `confirmed` 状态。

**Path 参数**: `orderId`

**请求体**: `{"uin": "1234567890123456"}`

**响应码**: `204` Updated | `400` | `401` | `402` | `403` | `404` | `409` | `429`

**限速**: 添加标识：1 分钟 1000 请求，间隔 60 ms

---

### 6. PUT Add IMEI to the Order

```
PUT /api/v3/dbw/orders/{orderId}/meta/imei
```

**描述**: 设置 IMEI。一个订单只能有一个 IMEI，仅适用于 `confirmed` 状态。

**请求体**: `{"imei": "123456789012345"}`

---

### 7. PUT Add GTIN to the Order

```
PUT /api/v3/dbw/orders/{orderId}/meta/gtin
```

**描述**: 设置 GTIN。一个订单只能有一个 GTIN，仅适用于 `confirmed` 状态。

**请求体**: `{"gtin": "1234567890123"}`
