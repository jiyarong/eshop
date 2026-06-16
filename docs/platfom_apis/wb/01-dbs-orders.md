# Wildberries DBS Orders API

> **DBS (Delivery by Seller)** — 卖家自发货模式
> 
> Base URL: `https://marketplace-api.wildberries.ru`
> 
> Token 类型: **Marketplace**

---

## 目录

- [DBS Assembly Orders](#dbs-assembly-orders)
- [DBS Label Identifiers](#dbs-label-identifiers)

---

## DBS Assembly Orders

### 工作流程

1. [获取新订单](#1-get-new-orders-list) 并保存，直至可进行配货
2. [转配货](#8-transfer-to-assembly)（status → `confirm`）
3. [转发货](#10-transfer-to-delivery)（status → `deliver`）
4. 转配货后可获取[买家信息](#4-buyer-information)
5. 送达后通知[已收货](#11-notify-that-the-orders-are-received) 或 [已拒收](#12-notify-that-the-orders-are-declined)

---

### 1. GET New Orders List

```
GET /api/v3/dbs/orders/new
```

**描述**: 获取当前所有新订单列表。

**认证**: `HeaderApiKey`

**速率限制**:

| 周期 | 限制 | 间隔 | 突发 |
|------|------|------|------|
| 1 min | 300 请求 | 200 ms | 20 请求 |

> 4XX 响应码每个请求计为 10 次。

**响应码**: `200` Success | `401` Unauthorized | `402` Payment required | `403` Access denied | `429` Too many requests

**响应示例 (200)**:

```json
{
  "orders": [{
    "salePrice": 504600,
    "requiredMeta": ["uin"],
    "comment": "Упакуйте в пленку, пожалуйста",
    "options": {"isB2b": true},
    "address": {
      "fullAddress": "Chelyabinsk Region, Chelyabinsk, 51st Arabkir Street, Building 10A, Apartment 42",
      "longitude": 44.519068,
      "latitude": 40.20192
    },
    "orderUid": "165918930_629fbc924b984618a44354475ca58675",
    "groupId": "7a2c8810-1db2-4011-9682-5c7fa33afd83",
    "article": "one-ring-7548",
    "colorCode": "RAL 3017",
    "rid": "f884001e44e511edb8780242ac120002",
    "createdAt": "2022-05-04T07:56:29Z",
    "deliveryType": "dbs",
    "skus": ["6665956397512"],
    "id": 13833711,
    "warehouseId": 658434,
    "nmId": 123456789,
    "chrtId": 987654321,
    "price": 1014,
    "finalPrice": 1014,
    "convertedFinalPrice": 1014,
    "convertedPrice": 1014,
    "currencyCode": 643,
    "convertedCurrencyCode": 643,
    "cargoType": 1,
    "isZeroOrder": false,
    "wbStickerId": 123456
  }]
}
```

---

### 2. GET Information on Completed Orders

```
GET /api/v3/dbs/orders
```

**描述**: 获取已完成订单信息（已取消或已售出）。每次请求最多 30 个日历日的数据。

**认证**: `HeaderApiKey`

**查询参数**:

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | integer [1..1000] | ✅ | 分页参数，限制返回数据量 |
| `next` | integer (int64) | ✅ | 分页参数，起始值为 0，后续使用响应中的 `next` |
| `dateFrom` | integer | ✅ | Unix 时间戳，开始日期 |
| `dateTo` | integer | ✅ | Unix 时间戳，结束日期 |

**速率限制**: 与 DBS Assembly Orders 相同（1 min / 300 请求）

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

**响应示例 (200)**:

```json
{
  "next": 13833711,
  "orders": [{
    "address": {
      "fullAddress": "Chelyabinsk Region, Chelyabinsk, 51st Arabkir Street, Building 10A, Apartment 42",
      "longitude": 44.519068,
      "latitude": 40.20192
    },
    "deliveryType": "string",
    "options": {"isB2b": true},
    "orderUid": "165918930_629fbc924b984618a44354475ca58675",
    "groupId": "7a2c8810-1db2-4011-9682-5c7fa33afd83",
    "article": "one-ring-7548",
    "colorCode": "RAL 3017",
    "rid": "f884001e44e511edb8780242ac120002",
    "createdAt": "2022-05-04T07:56:29Z",
    "skus": ["6665956397512"],
    "id": 13833711,
    "warehouseId": 658434,
    "nmId": 12345678,
    "chrtId": 987654321,
    "scanPrice": 50,
    "price": 1014,
    "convertedPrice": 1014,
    "currencyCode": 643,
    "convertedCurrencyCode": 643,
    "convertedFinalPrice": 1014,
    "finalPrice": 1014,
    "cargoType": 1,
    "comment": "Упакуйте в пленку, пожалуйста",
    "isZeroOrder": false,
    "wbStickerId": 123456
  }]
}
```

---

### 3. POST Paid Delivery Information

```
POST /api/v3/dbs/groups/info
```

**描述**: 获取同一仓库、同一买家交易下的配货订单的付费配送信息。

**认证**: `HeaderApiKey`

**请求体** (`application/json`, required):

| 字段 | 类型 | 说明 |
|------|------|------|
| `groups` | Array of strings ≤ 1000 | `groupId` 值列表，可从新订单和已完成订单获取 |

**请求示例**:

```json
{"groups": ["7a2c8810-1db2-4011-9682-5c7fa33afd83", "5a8f4523-4cf2-5691-9682-5a7fd33afd73"]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

**响应示例 (200)**:

```json
[{
  "groupID": "0596a30a-d11c-4210-a231-ee1c39d61fe4",
  "deliveryCost": 1108,
  "convertedDeliveryCost": 29803,
  "currencyCode": 933,
  "convertedCurrencyCode": 643
}]
```

---

### 4. POST Buyer Information

```
POST /api/v3/dbs/orders/client
```

**描述**: 通过订单 ID 获取买家信息。

**认证**: `HeaderApiKey`

**请求体** (`application/json`, required):

| 字段 | 类型 | 说明 |
|------|------|------|
| `orders` | Array of integers | 配货订单 ID 列表 |

**请求示例**:

```json
{"orders": [987654321, 123456789]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `404` | `429`

**响应示例 (200)**:

```json
{
  "orders": [{
    "replacementPhone": "79871234567",
    "firstName": "string",
    "fullName": "Иванов Иван Иванович",
    "orderID": 134567,
    "phone": "+79871234567",
    "phoneCode": 1234567,
    "additionalPhoneCodes": ["12345", "65498"]
  }]
}
```

---

### 5. POST B2B Buyer Information

```
POST /api/marketplace/v3/dbs/orders/b2b/info
```

**描述**: 通过配货订单 ID 获取 B2B 买家数据：TIN（INN）、KPP、公司名称。

**认证**: `HeaderApiKey`

**请求体** (`application/json`, required):

| 字段 | 类型 | 说明 |
|------|------|------|
| `ordersIds` | Array of integers ≤ 1000 | 配货订单 ID 列表 |

**请求示例**:

```json
{"ordersIds": [123456, 234567]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

**响应示例 (200)**:

```json
{
  "requestId": "03615778-eb9e-4f55-b4O4-fd3ac0fad2сc",
  "results": [
    {"orderId": 4299281547, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}]},
    {"orderId": 4279781545, "isError": false, "data": {"orgName": "ИП Иванов И.И.", "inn": "8888888888", "kpp": ""}}
  ]
}
```

---

### 6. POST Delivery Date and Time

```
POST /api/v3/dbs/orders/delivery-date
```

**描述**: 获取买家选择的订单配送日期和时间。

**认证**: `HeaderApiKey`

**请求体** (`application/json`, required):

| 字段 | 类型 | 说明 |
|------|------|------|
| `orders` | Array of integers [1..1000] | 订单 ID 列表 |

**请求示例**:

```json
{"orders": [1234567890]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

**响应示例 (200)**:

```json
{
  "orders": [{
    "dTimeFrom": "11:11",
    "dTimeTo": "22:22",
    "dTimeFromOld": "12:30",
    "dTimeToOld": "22:30",
    "dDateOld": "2025-01-28",
    "dDate": "2026-01-26",
    "dDateFrom": "12.01.2026",
    "dDateTo": "14.01.2026",
    "id": 1234567890
  }]
}
```

---

### 7. POST Assembly Order Statuses

```
POST /api/marketplace/v3/dbs/orders/status/info
```

**描述**: 根据配货订单 ID 列表返回订单状态。

**认证**: `HeaderApiKey`

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `ordersIds` | Array of integers ≤ 1000 | 配货订单 ID 列表 |

**请求示例**:

```json
{"ordersIds": [123456, 234567]}
```

**`supplierStatus` (卖家状态)**:

| 状态 | 描述 | 触发方式 |
|------|------|----------|
| `new` | 新订单 | — |
| `confirm` | 配货中 | [Transfer to Assembly](#8-transfer-to-assembly) |
| `deliver` | 配送中 | [Transfer to Delivery](#10-transfer-to-delivery) |
| `receive` | 买家已收货 | [Notify Received](#11-notify-that-the-orders-are-received) |
| `reject` | 买家拒收 | [Notify Declined](#12-notify-that-the-orders-are-declined) |
| `cancel` | 卖家已取消 | [Cancel Orders](#8-cancel-assembly-orders) |
| `cancel_missed_call` | 联系不上买家已取消 | 自动变更 |

**`wbStatus` (WB 平台状态)**:

| 状态 | 说明 |
|------|------|
| `waiting` | 配货订单处理中 |
| `sold` | 买家已收货 |
| `canceled` | 已取消 |
| `canceled_by_client` | 买家取消 |
| `declined_by_client` | 买家首小时内取消 |
| `defect` | 因缺陷取消 |
| `ready_for_pickup` | 已到提货点 |
| `canceled_by_missed_call` | 联系不上买家取消 |

**响应码**: `200` | `400` | `401` | `402` | `403` | `404` | `429`

**响应示例 (200)**:

```json
{
  "orders": [
    {"supplierStatus": "confirm", "wbStatus": "waiting", "errors": [], "orderId": 123456},
    {"supplierStatus": "", "wbStatus": "", "errors": [{"code": 404, "detail": "NotFound"}], "orderId": 789012}
  ]
}
```

---

### 8. POST Cancel Assembly Orders

```
POST /api/marketplace/v3/dbs/orders/status/cancel
```

**描述**: 将 `new` 和 `confirm` 状态的订单转为 `cancel`。不能取消 `deliver` 状态的订单。

**认证**: `HeaderApiKey`

**速率限制**:

| 周期 | 限制 | 间隔 | 突发 |
|------|------|------|------|
| 1 s | 1 请求 | 1 s | 10 请求 |

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `ordersIds` | Array of integers ≤ 1000 | 配货订单 ID 列表 |

**请求示例**:

```json
{"ordersIds": [123456, 234567]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

---

### 9. POST Transfer to Assembly

```
POST /api/marketplace/v3/dbs/orders/status/confirm
```

**描述**: 将 `new` 状态的订单转为 `confirm`（配货中）。

**认证**: `HeaderApiKey`

**速率限制**: 1 s / 1 请求

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `ordersIds` | Array of integers ≤ 1000 | 配货订单 ID 列表 |

**请求示例**:

```json
{"ordersIds": [123456, 234567]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

**响应示例 (200)**:

```json
{
  "requestId": "03615778-eb9e-4f55-b4Of-fd3ac0fad2сc",
  "results": [
    {"orderId": 4299281547, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}]},
    {"orderId": 4279781545, "isError": false}
  ]
}
```

---

### 10. POST Stickers for Assembly Orders (Delivery to Pickup Point)

```
POST /api/marketplace/v3/dbs/orders/stickers
```

**描述**: 获取配货订单的标签贴纸（仅限配送至提货点）。适用于 `confirm` 和 `deliver` 状态。格式：580×400 px PDF。

**认证**: `HeaderApiKey` (支持 Personal、Service Token)

**查询参数**:

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | string | ✅ | 固定值: `pdf` |
| `width` | integer | ✅ | 固定值: `58` |
| `height` | integer | ✅ | 固定值: `40` |

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `orders` | Array of int64 [1..100] | 配货订单 ID 列表 |

**请求示例**:

```json
{"orders": [5346346]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

**响应示例 (200)**:

```json
{
  "stickers": [{
    "orderId": 5346346,
    "partA": "231648",
    "partB": "9753",
    "barcode": "!uKEtQZVx",
    "file": "JVBER...ZWYKMTM5MQolJUVPRg=="
  }]
}
```

---

### 11. POST Transfer to Delivery

```
POST /api/marketplace/v3/dbs/orders/status/deliver
```

**描述**: 将 `confirm` 状态转为 `deliver`（配送中）。

**认证**: `HeaderApiKey`

**速率限制**: 1 s / 1 请求

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `ordersIds` | Array of integers ≤ 1000 | 配货订单 ID 列表 |

**请求示例**:

```json
{"ordersIds": [123456, 234567]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

---

### 12. POST Notify Orders Are Received

```
POST /api/marketplace/v3/dbs/orders/status/receive
```

**描述**: 将 `deliver` 状态转为 `receive`（买家已收货）。

**认证**: `HeaderApiKey`

**速率限制**: 1 s / 1 请求

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `orders` | Array of objects (OrderCodeRequest) ≤ 1000 | 需包含 `code` 和 `orderId` |

**请求示例**:

```json
{"orders": [{"code": "741852", "orderId": 123456}]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

---

### 13. POST Notify Orders Are Declined

```
POST /api/marketplace/v3/dbs/orders/status/reject
```

**描述**: 将 `deliver` 状态转为 `reject`（买家拒收）。

**认证**: `HeaderApiKey`

**速率限制**: 1 s / 1 请求

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `orders` | Array of objects (OrderCodeRequest) ≤ 1000 | 需包含 `code` 和 `orderId` |

**请求示例**:

```json
{"orders": [{"code": "741852", "orderId": 123456}]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

---

## DBS Label Identifiers

> Token 类型: **Marketplace**

### 可用的标签标识符类型

| 标识符 | 说明 |
|--------|------|
| `imei` | IMEI 码 |
| `uin` | 唯一识别号 |
| `gtin` | GTIN 码 |
| `sgtin` | Chestny ZNAK 数据矩阵码 |
| `customsDeclaration` | 海关报关单号 |

---

### 14. POST Get Assembly Orders Label Identifiers

```
POST /api/marketplace/v3/dbs/orders/meta/details
```

**描述**: 返回配货订单的标签标识符及其验证状态。

**认证**: `HeaderApiKey`

**速率限制** (获取/删除): 1 min / 300 请求

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `ordersIds` | Array of integers ≤ 1000 | 配货订单 ID 列表 |

**请求示例**:

```json
{"ordersIds": [123456, 234567]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

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

### 15. POST Get Assembly Orders Label Identifiers (Deprecated)

```
POST /api/marketplace/v3/dbs/orders/meta/info
```

⚠️ **已弃用**，将于指定日期移除。请使用 [meta/details](#14-post-get-assembly-orders-label-identifiers)。

**速率限制**: 1 min / 150 请求

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `ordersIds` | Array of integers ≤ 1000 | 配货订单 ID 列表 |

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

---

### 16. POST Delete Assembly Orders Label Identifiers

```
POST /api/marketplace/v3/dbs/orders/meta/delete
```

**描述**: 删除配货订单的标签标识符值。每次请求只能删除一种类型。

**认证**: `HeaderApiKey`

**速率限制**: 1 min / 150 请求

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `key` | string | ✅ | Enum: `imei`, `uin`, `gtin`, `sgtin`, `customsDeclaration` |
| `orderIds` | Array of integers ≤ 1000 | ✅ | 配货订单 ID 列表 |

**请求示例**:

```json
{"key": "imei", "orderIds": [123456, 234567]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `409` | `429`

---

### 17. POST Add Data Matrix Codes (Chestny ZNAK)

```
POST /api/marketplace/v3/dbs/orders/meta/sgtin
```

**描述**: 为 `confirm` 状态的订单设置 Chestny ZNAK 标签码。

**认证**: `HeaderApiKey`

**速率限制** (添加):

| 类型 | 周期 | 限制 | 间隔 | 突发 |
|------|------|------|------|------|
| Personal | 1 min | 500 | 120 ms | 20 |
| Service | 1 min | 500 | 120 ms | 20 |
| Base (secret) | 1 min | 500 | 120 ms | 20 |
| Base | 1 h | 10 | 6 min | 1 |

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `orders` | Array of objects (SGTINs) ≤ 1000 | 每个对象含 `orderId` 和 `sgtins` 数组 |

**请求示例**:

```json
{"orders": [{"orderId": 123456, "sgtins": ["123456789012345678", "1234567890123456"]}]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

---

### 18. POST Add UIN

```
POST /api/marketplace/v3/dbs/orders/meta/uin
```

**描述**: 为 `confirmed` 状态的订单设置 UIN（每个订单只能有一个）。

**认证**: `HeaderApiKey`

**速率限制**: 1 min / 500 请求

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `orders` | Array of objects (UIN) ≤ 1000 | 每个对象含 `orderId` 和 `uin` |

**请求示例**:

```json
{"orders": [{"orderId": 123456, "uin": "1234568909091232"}]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `409` | `429`

---

### 19. POST Add IMEI

```
POST /api/marketplace/v3/dbs/orders/meta/imei
```

**描述**: 为 `confirmed` 状态的订单设置 IMEI（每个订单只能有一个）。

**认证**: `HeaderApiKey`

**速率限制**: 1 min / 500 请求

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `orders` | Array of objects (IMEI) ≤ 1000 | 每个对象含 `orderId` 和 `imei` |

**请求示例**:

```json
{"orders": [{"orderId": 123456, "imei": "654321741987258"}]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `409` | `429`

---

### 20. POST Add GTIN

```
POST /api/marketplace/v3/dbs/orders/meta/gtin
```

**描述**: 为 `confirmed` 状态的订单设置 GTIN（白俄罗斯商品唯一标识符）。

**认证**: `HeaderApiKey`

**速率限制**: 1 min / 500 请求

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `orders` | Array of objects (GTIN) ≤ 1000 | 每个对象含 `orderId` 和 `gtin` |

**请求示例**:

```json
{"orders": [{"gtin": "1234567890123", "orderId": 123456}]}
```

**响应码**: `200` | `400` | `401` | `402` | `403` | `409` | `429`

---

### 21. POST Add Customs Declaration

```
POST /api/marketplace/v3/dbs/orders/meta/customs-declaration
```

**描述**: 为 `deliver` 状态的订单设置海关报关单号。

**认证**: `HeaderApiKey`

**速率限制**: 1 min / 500 请求

**请求体** (`application/json`):

| 字段 | 类型 | 说明 |
|------|------|------|
| `orders` | Array of objects ≤ 1000 | 每个对象含 `orderId` 和 `customsDeclaration` |

**请求示例**:

```json
{"orders": [{"customsDeclaration": "10704010/010624/0000302", "orderId": 0}]}
```

**响应码**: `204` Updated | `400` | `401` | `402` | `403` | `404` | `409` | `429`
