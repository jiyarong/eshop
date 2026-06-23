# Wildberries FBS Orders API

> **FBS (Fulfillment by Seller)** — 卖家自配送模式
>
> Base URL: `https://marketplace-api.wildberries.ru`
>
> Token 类型: **Marketplace**
>
> 功能：管理 FBS 配货订单、标签标识、供货（Supply）及仓库通行证（Pass）

---

## 目录

- [FBS Assembly Orders](#fbs-assembly-orders)
- [FBS Label Identifiers](#fbs-label-identifiers)
- [FBS Supplies](#fbs-supplies)
- [FBS Passes](#fbs-passes)

---

## FBS Assembly Orders

### 工作流程

1. [获取新配货订单](#1-get-new-assembly-orders)
2. 将订单加入供货（Supply）并自动进入 `confirm` — 配货中
3. 供货交接后进入 `complete` — 配送中
4. 可通过 [取消订单](#5-cancel-the-assembly-order) 取消订单

### 状态说明

**supplierStatus**（由卖家触发）：

| 状态 | 说明 | 进入方式 |
|------|------|----------|
| `new` | 新订单 | — |
| `confirm` | 配货中（FBS） | 加入供货 |
| `complete` | 配送中（FBS/WB courier） | 供货转配送 |
| `cancel` | 卖家取消 | 调用取消接口 |
| `cancel_carrier` | 承运商取消（仅跨境） | 承运商更改 |

**wbStatus**（WB 侧状态）：`waiting`, `sorted`, `sold`, `canceled`, `canceled_by_client`, `declined_by_client`, `defect`, `ready_for_pickup`, `postponed_delivery`, `accepted_by_carrier`, `sent_to_carrier`, `canceled_by_carrier`

> 所有 FBS 配货订单、供货、通行证接口统一限速：1 分钟 300 请求，间隔 200 ms，突发 20 请求。4XX 计为 10 次。

---

### 1. GET New Assembly Orders

```
GET /api/v3/orders/new
```

**描述**: 获取当前所有新 FBS 配货订单。

**认证**: `HeaderApiKey`

**响应码**: `200` Success | `401` Unauthorized | `402` Payment required | `403` Access denied | `429` Too many requests

**响应示例 (200)**:

```json
{
  "orders": [{
    "address": { "fullAddress": "...", "longitude": 44.519068, "latitude": 40.20192 },
    "ddate": "17.05.2024",
    "sellerDate": "02.06.2025",
    "salePrice": 504600,
    "requiredMeta": ["uin"],
    "optionalMeta": ["sgtin"],
    "deliveryType": "fbs",
    "comment": "Упакуйте в плёнку, пожалуйста",
    "scanPrice": null,
    "orderUid": "165918930_629fbc924b984618a44354475ca58675",
    "article": "one-ring-7548",
    "colorCode": "RAL 3017",
    "rid": "f884001e44e511edb8780242ac120002",
    "createdAt": "2022-05-04T07:56:29Z",
    "offices": ["Калуга"],
    "skus": ["6665956397512"],
    "id": 13833711,
    "warehouseId": 658434,
    "officeId": 123,
    "nmId": 123456789,
    "chrtId": 987654321,
    "price": 1014,
    "finalPrice": 1014,
    "convertedPrice": 28322,
    "convertedFinalPrice": 1014,
    "currencyCode": 933,
    "convertedCurrencyCode": 643,
    "cargoType": 1,
    "crossBorderType": 1,
    "isZeroOrder": false,
    "options": { "isB2B": true }
  }]
}
```

---

### 2. GET Assembly Orders

```
GET /api/v3/orders
```

**描述**: 返回 3 个月内创建的配货订单（不含当前状态）。默认查询近 30 天，单次最多 30 天。超过 3 个月的订单使用 [归档列表](#10-get-the-list-of-archived-assembly-orders)。

**Query 参数**:

| 参数 | 必填 | 说明 |
|------|------|------|
| `limit` | 是 | integer [1..1000]，分页大小 |
| `next` | 是 | integer <int64>，从 0 开始，下一批使用响应中的 `next` |
| `dateFrom` | 否 | integer，Unix 时间戳，UTC |
| `dateTo` | 否 | integer，Unix 时间戳，UTC |

**响应码**: `200` | `400` | `401` | `402` | `403` | `429`

**响应示例 (200)**:

```json
{
  "next": 13833711,
  "orders": [{
    "supplyId": "WB-GI-92937123",
    "scanPrice": 1500,
    "deliveryType": "fbs",
    ...
  }]
}
```

---

### 3. POST Get Assembly Orders Statuses

```
POST /api/v3/orders/status
```

**描述**: 根据配货订单 ID 列表返回状态。

**请求体**:

```json
{
  "orders": [5632423]
}
```

**响应示例 (200)**:

```json
{
  "orders": [{
    "id": 5632423,
    "isCancellable": false,
    "supplierStatus": "new",
    "wbStatus": "waiting"
  }]
}
```

---

### 4. GET Get All Assembly Orders for Re-shipment

```
GET /api/v3/supplies/orders/reshipment
```

**描述**: 返回所有需要重新发货的配货订单。

**响应示例 (200)**:

```json
{
  "orders": [{"supplyID": "WB-GI-1234567", "orderID": 5632423}]
}
```

---

### 5. PATCH Cancel the Assembly Order

```
PATCH /api/v3/orders/{orderId}/cancel
```

**描述**: 将订单移至 `cancel`（卖家取消）。在交给 WB 前可取消，可通过 `isCancellable` 判断。

**Path 参数**:

| 参数 | 必填 | 说明 |
|------|------|------|
| `orderId` | 是 | integer <int64>，配货订单 ID |

**响应码**: `204` Canceled | `400` | `401` | `402` | `403` | `404` | `409` | `429`

**限速**: 1 分钟 100 请求，间隔 600 ms

---

### 6. POST Get Assembly Orders Stickers

```
POST /api/v3/orders/stickers
```

**描述**: 根据配货订单返回贴纸。支持 `svg`、`zplv`、`zplh`、`png`。

**限制**:

- 单次最多 100 个订单
- 仅 `confirm` 和 `complete` 状态的订单可获取
- 尺寸：580x400（width=58, height=40）或 400x300（width=40, height=30）

**Query 参数**:

| 参数 | 必填 | 说明 |
|------|------|------|
| `type` | 是 | Enum: `svg`, `zplv`, `zplh`, `png` |
| `width` | 是 | Enum: 58, 40 |
| `height` | 是 | Enum: 40, 30 |

**请求体**:

```json
{"orders": [5346346]}
```

**响应示例 (200)**:

```json
{
  "stickers": [{
    "orderId": 5346346,
    "partA": "231648",
    "partB": "9753",
    "barcode": "!uKEtQZVx",
    "file": "<base64/图片数据>"
  }]
}
```

---

### 7. POST Get Stickers for Cross-Border Assembly Orders

```
POST /api/v3/orders/stickers/cross-border
```

**描述**: 返回跨境订单的 PDF 贴纸。

**状态**:

- `awaitingTrackNumber` — 等待承运商追踪号
- `ready` — 已生成

**请求体**: `{"orders": [3869227998]}`

**响应示例 (200)**:

```json
{
  "stickers": [{
    "orderId": 123456789,
    "status": "ready",
    "parcelId": "WB0000000001",
    "file": "<PDF base64>",
    "partA": "231648",
    "partB": "9753",
    "barcode": "!uKEtQZVx"
  }]
}
```

---

### 8. POST Status History for Cross-Border Orders

```
POST /api/v3/orders/status/history
```

**描述**: 返回跨境订单状态历史。

**请求体**: `{"orders": [123456789,987654321]}`

**响应示例 (200)**:

```json
{
  "orders": [{
    "deliveryDate": "2019-08-24T14:15:22Z",
    "statuses": [{"date": null, "code": "SORTED"}],
    "orderID": 123456789
  }]
}
```

---

### 9. POST Orders with Client Information

```
POST /api/v3/orders/client
```

**描述**: 根据配货订单 ID 获取买家信息，仅适用于来自 **土耳其** 的跨境订单。

**请求体**: `{"orders": [987654321,123456789]}`

**响应示例 (200)**:

```json
{
  "orders": [{
    "firstName": "Иван",
    "fullName": "Андреев Иван Васильевич",
    "lastName": "Андреев",
    "middleName": "Васильевич",
    "orderID": 134567,
    "phone": "79871234567",
    "phoneCode": "0"
  }]
}
```

---

### 10. GET Get the List of Archived Assembly Orders

```
GET /api/marketplace/v3/fbs/orders/archive
```

**描述**: 返回创建时间超过 3 个月的归档配货订单。

**Query 参数**:

| 参数 | 必填 | 说明 |
|------|------|------|
| `year` | 是 | 订单创建年份 |
| `month` | 是 | 订单创建月份 [1..12] |
| `next` | 是 | 分页偏移，从 0 开始 |
| `limit` | 是 | [100..1000]，默认 100 |

**响应示例 (200)**:

```json
{
  "next": 0,
  "orders": [{
    "cargoType": "mgt",
    "colorCode": "RAL 3017",
    "createdAt": "2022-05-04",
    "crossBorder": {"parcel": "1Z999AA10123456784"},
    "crossBorderType": "crossBorder",
    "id": 1234567890,
    ...
  }]
}
```

---

## FBS Label Identifiers

> 用于获取、删除、编辑配货订单的标签标识。
>
> 支持的标识：`imei`、`uin`、`gtin`、`sgtin`（Честный ЗНАК）、`expiration`（有效期）、`customsDeclaration`（报关单号）

---

### 1. POST Get Assembly Orders Label Identifiers

```
POST /api/marketplace/v3/orders/meta
```

**描述**: 根据订单 ID 列表返回标签标识。

**请求体**: `{"orders": [123456,234567,345678]}`

**限速**: 获取/删除标识：1 分钟 300 请求

**响应示例 (200)**:

```json
{
  "orders": [{
    "id": 0,
    "metaDetails": [{"key": "uin", "value": null, "decision": "uinMaySell"}]
  }]
}
```

---

### 2. DELETE Delete Assembly Order Label Identifiers

```
DELETE /api/v3/orders/{orderId}/meta
```

**描述**: 删除指定订单指定 key 的所有标签标识值。

**Path 参数**: `orderId` — 配货订单 ID

**Query 参数**: `key` — 标识类型（imei/uin/gtin/sgtin/customsDeclaration）

**限速**: 获取/删除标识：1 分钟 300 请求

**响应码**: `204` | `400` | `401` | `402` | `403` | `404` | `429`

---

### 3. PUT Add Labeling Code Chestny ZNAK to the Assembly Order

```
PUT /api/v3/orders/{orderId}/meta/sgtin
```

**描述**: 为订单设置 Честный ЗНАК 数据矩阵码。

**Path 参数**: `orderId`

**请求体**:

```json
{"sgtin": ["123456789012345678"]}
```

**响应码**: `204` Sent | `400` | `401` | `402` | `403` | `404` | `409` | `429`

**限速**: 添加标识：1 分钟 1000 请求，间隔 60 ms

---

### 4. PUT Add UIN to the Assembly Order

```
PUT /api/v3/orders/{orderId}/meta/uin
```

**描述**: 设置 UIN（唯一识别码）。

**请求体**: `{"uin": "1234567890123456"}`

---

### 5. PUT Add IMEI to the Assembly Order

```
PUT /api/v3/orders/{orderId}/meta/imei
```

**描述**: 设置 IMEI。

**请求体**: `{"imei": "654321741987258"}`

---

### 6. PUT Add GTIN to the Assembly Order

```
PUT /api/v3/orders/{orderId}/meta/gtin
```

**描述**: 设置 GTIN（白俄罗斯商品唯一标识）。

**请求体**: `{"gtin": "1234567890123"}`

---

### 7. PUT Add Expiration Date to the Assembly Order

```
PUT /api/v3/orders/{orderId}/meta/expiration
```

**描述**: 设置商品有效期，格式 `dd.mm.yyyy`，距离当前日期不少于 30 天。

**请求体**: `{"expiration": "12.09.2030"}`

---

### 8. PUT Add Custom Declaration number to the Order

```
PUT /api/marketplace/v3/orders/{orderId}/meta/customs-declaration
```

**描述**: 更新报关单号。仅适用于 `confirm` 或 `complete` 状态，EAEU 外生产商品必填。

**请求体**: `{"customsDeclaration": "10704010/010624/0000302"}`

---

## FBS Supplies

### 工作流程

1. [创建新供货](#1-post-create-a-new-supply) → 返回 `WB-GI-1234567`
2. [添加配货订单到供货](#3-patch-add-assembly-orders-to-the-supply)
3. （配送自提点时）创建、查询、打印 shipping unit 贴纸
4. [供货转配送](#7-patch-move-the-supply-to-the-delivery)
5. 如有未扫描商品，重新发货

---

### 1. POST Create a New Supply

```
POST /api/v3/supplies
```

**描述**: 创建新供货。

**限制**:

- 仅适用于 FBS 配送订单
- 加入供货的订单自动从 `new` 转至 `confirm`
- 供货内订单必须具有相同 `cargoType`

**请求体**: `{"name": "Some test supply"}`

**响应码**: `201` Created

**响应示例 (201)**:

```json
{"id": "WB-GI-1234567"}
```

---

### 2. GET Get a Supplies List

```
GET /api/v3/supplies
```

**描述**: 返回供货列表。

**Query 参数**: `limit`, `next`（必填，分页）

**响应示例 (200)**:

```json
{
  "next": 13833711,
  "supplies": [{
    "id": "WB-GI-1234567",
    "isB2b": true,
    "done": true,
    "createdAt": "2022-05-04T07:56:29Z",
    "closedAt": "2022-05-04T07:56:29Z",
    "scanDt": "2022-05-04T07:56:29Z",
    "name": "My test supply",
    "cargoType": 0,
    "crossBorderType": 1,
    "destinationOfficeId": 123,
    "recommendedWhId": 123569
  }]
}
```

---

### 3. PATCH Add Assembly Orders to the Supply

```
PATCH /api/marketplace/v3/supplies/{supplyId}/orders
```

**描述**: 向供货添加最多 100 个配货订单，并移至 `confirm`。支持在活跃供货间转移，或从已关闭供货转移至活跃供货（如需重新发货）。

**Path 参数**: `supplyId`

**请求体**: `{"orders": [5632423,3453452,...]}`

**响应码**: `204` | `400` | `401` | `402` | `403` | `404` | `409` | `429`

---

### 4. GET Get Supply Details

```
GET /api/v3/supplies/{supplyId}
```

**描述**: 返回供货详情。

---

### 5. DELETE Delete the Supply

```
DELETE /api/v3/supplies/{supplyId}
```

**描述**: 删除活跃且不含任何订单的供货。

**响应码**: `204` Deleted | `409` The supply contains orders

---

### 6. GET Get Supply Assembly Order IDs

```
GET /api/marketplace/v3/supplies/{supplyId}/order-ids
```

**描述**: 返回供货中的所有配货订单 ID。

**响应示例 (200)**:

```json
{"orderIds": [132334,203984,403543,598349]}
```

---

### 7. PATCH Move the Supply to the Delivery

```
PATCH /api/v3/supplies/{supplyId}/deliver
```

**描述**: 关闭供货，所有订单移至 `complete`（配送中）。

**条件**:

- 至少有一个订单
- 所有订单已填写所需标识
- 所有标识通过验证

**响应码**: `204` | `400` | `401` | `402` | `403` | `404` | `409` | `429`

---

### 8. GET Get the Supply QR Code

```
GET /api/v3/supplies/{supplyId}/barcode
```

**描述**: 返回供货 QR 码（svg/zplv/zplh/png），仅供货转配送后可用。

**Query 参数**: `type`（必填）

**响应示例 (200)**:

```json
{"barcode": "WB-GI-12345678", "file": "<base64>"}
```

---

### 9. GET Get Supply Shipping Units List

```
GET /api/v3/supplies/{supplyId}/trbx
```

**描述**: 返回供货的 shipping unit 列表。

**响应示例 (200)**:

```json
{"trbxes": [{"id": "WB-TRBX-1234567"}]}
```

---

### 10. POST Add Shipping Units to the Supply

```
POST /api/v3/supplies/{supplyId}/trbx
```

**描述**: 向供货添加 shipping unit。仅适用于配送至自提点的供货，且只能添加到开放供货。

**请求体**: `{"amount": 4}`

**响应码**: `201` Created

**响应示例 (201)**:

```json
{"trbxIds": ["WB-TRBX-1234567"]}
```

---

### 11. DELETE Delete Shipping Units from the Supply

```
DELETE /api/v3/supplies/{supplyId}/trbx
```

**描述**: 从供货中删除 shipping unit，仅供货处于配货中时可用。

**请求体**: `{"trbxIds": ["WB-TRBX-1234567"]}`

---

### 12. POST Get the Supply Shipping Unit QR Code Stickers

```
POST /api/v3/supplies/{supplyId}/trbx/stickers
```

**描述**: 返回 shipping unit 的 QR 码贴纸（580x400）。

**Query 参数**: `type`（必填）

**请求体**: `{"trbxIds": ["WB-TRBX-1234567"]}`

**响应示例 (200)**:

```json
{"stickers": [{"barcode": "$WBMP:1:123:1234567", "file": "<base64>"}]}
```

---

## FBS Passes

> 管理进入 WB 仓库/自提点的车辆通行证。

---

### 1. GET Get Offices for Pass

```
GET /api/v3/passes/offices
```

**描述**: 返回需要通行证的仓库/办公点列表。

**响应示例 (200)**:

```json
[{"name": "Koledino", "address": "Kosmonavtov 10А", "id": 1}]
```

---

### 2. GET Get Passes

```
GET /api/v3/passes
```

**描述**: 返回卖家所有通行证列表。

**响应示例 (200)**:

```json
[{
  "firstName": "Alex",
  "dateEnd": "2022-07-31 17:53:13+00:00",
  "lastName": "Petrov",
  "carModel": "Lamborghini",
  "carNumber": "A456BC123",
  "officeName": "Koledino",
  "officeAddress": "Kosmonavtov 10А",
  "officeId": 15,
  "id": 1
}]
```

---

### 3. POST Create Pass

```
POST /api/v3/passes
```

**描述**: 创建通行证，自创建起 48 小时内有效。

**限制**: 每 10 分钟最多 1 次请求

**请求体**:

```json
{
  "firstName": "Alex",
  "lastName": "Petrov",
  "carModel": "Lamborghini",
  "carNumber": "A456BC123",
  "officeId": 15
}
```

**响应码**: `201` Created

**响应示例 (201)**:

```json
{"id": 2}
```

---

### 4. PUT Update Pass

```
PUT /api/v3/passes/{passId}
```

**描述**: 更新通行证信息。

**Path 参数**: `passId`

**请求体**: 同创建

---

### 5. DELETE Delete the Pass

```
DELETE /api/v3/passes/{passId}
```

**描述**: 删除通行证。

**Path 参数**: `passId`

**响应码**: `204` Deleted
