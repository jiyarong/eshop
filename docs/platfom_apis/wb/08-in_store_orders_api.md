# Wildberries In-Store Pickup API 文档

> 基础URL: `https://marketplace-api.wildberries.ru`
> 认证方式: `HeaderApiKey` (Marketplace 类别 Token)
> 官方文档: https://dev.wildberries.ru/en/docs/openapi/in-store-pickup

---

## 目录

- [1. 概述](#1-概述)
- [2. 装配订单生命周期](#2-装配订单生命周期)
- [3. 装配订单 API](#3-装配订单-api)
  - [3.1 GET 获取新装配订单列表](#31-get-获取新装配订单列表)
  - [3.2 POST 转入装配](#32-post-转入装配)
  - [3.3 POST 通知装配订单可取货](#33-post-通知装配订单可取货)
  - [3.4 POST 获取买家信息](#34-post-获取买家信息)
  - [3.5 POST 核验订单是否属于买家](#35-post-核验订单是否属于买家)
  - [3.6 POST 通知买家已收货](#36-post-通知买家已收货)
  - [3.7 POST 通知买家拒收](#37-post-通知买家拒收)
  - [3.8 POST 获取装配订单状态](#38-post-获取装配订单状态)
  - [3.9 GET 获取已完成装配订单信息](#39-get-获取已完成装配订单信息)
  - [3.10 POST 取消装配订单](#310-post-取消装配订单)
- [4. 标签标识符 API](#4-标签标识符-api)
  - [4.1 POST 获取标签标识符详情](#41-post-获取标签标识符详情)
  - [4.2 POST 获取标签标识符信息 (已废弃)](#42-post-获取标签标识符信息-已废弃)
  - [4.3 POST 删除标签标识符](#43-post-删除标签标识符)
  - [4.4 POST 添加 Chestny ZNAK 标识码](#44-post-添加-chestny-znak-标识码)
  - [4.5 POST 添加 UIN](#45-post-添加-uin)
  - [4.6 POST 添加 IMEI](#46-post-添加-imei)
  - [4.7 POST 添加 GTIN](#47-post-添加-gtin)
- [5. 限流规则汇总](#5-限流规则汇总)
- [6. 响应码汇总](#6-响应码汇总)

---

## 1. 概述

In-Store Pickup（店内自提）API 用于管理装配订单（Assembly Orders）和订单标签标识符（Label Identifiers）。

### 业务流程

```
获取新订单 → 转入装配 → 获取买家信息 → 通知可取货 → 核验收货人身份 → 通知买家已收货/拒收
```

---

## 2. 装配订单生命周期

| 状态 (supplierStatus) | 含义 | 触发方式 |
|------------------------|------|-----------|
| `new` | 新装配订单 | 系统自动 |
| `confirm` | 装配中 | [POST 转入装配](#32-post-转入装配) |
| `prepare` | 可取货 | [POST 通知可取货](#33-post-通知装配订单可取货) |
| `receive` | 买家已收货 | [POST 通知买家已收货](#36-post-通知买家已收货) |
| `reject` | 买家拒收 | [POST 通知买家拒收](#37-post-通知买家拒收) |
| `cancel` | 卖家取消 | [POST 取消订单](#310-post-取消装配订单) |
| `cancel_shelf_life` | 过期自动取消 | 系统自动 |

### WB 系统状态 (wbStatus)

| 值 | 含义 |
|----|------|
| `waiting` | 装配进行中 |
| `sorted` | 已分拣 |
| `sold` | 买家已取货 |
| `canceled` | 已取消 |
| `canceled_by_client` | 买家取货时取消 |
| `declined_by_client` | 买家1小时内取消 |
| `defect` | 因缺陷取消 |
| `ready_for_pickup` | 准备取货 |

---

## 3. 装配订单 API

> 以下 API 限流：1分钟 300 请求，间隔 200ms，突发 20 请求。4XX 响应计为 10 次请求。

---

### 3.1 GET 获取新装配订单列表

```
GET /api/v3/click-collect/orders/new
```

**描述**：获取卖家当前所有新装配订单列表。

**认证**：`HeaderApiKey`

**请求参数**：无

**响应码**：`200` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "orders": [
    {
      "ddate": "29.10.2024",
      "salePrice": 14000,
      "requiredMeta": ["sgtin"],
      "article": "wb1702fyjh",
      "rid": "1234567673554519872.0.0",
      "createdAt": "2024-10-29T10:19:30Z",
      "warehouseAddress": "Москва, район Якиманка, Софийская набережная, 4 с1",
      "orderCode": "23457822-6667",
      "payMode": "prepaid",
      "skus": ["2041546265353"],
      "id": 1234567890,
      "warehouseId": 1234567,
      "nmId": 123456789,
      "chrtId": 987654321,
      "price": 14000,
      "finalPrice": 14000,
      "convertedPrice": 14000,
      "convertedFinalPrice": 14000,
      "currencyCode": 643,
      "convertedCurrencyCode": 643,
      "cargoType": 1,
      "isZeroOrder": false
    }
  ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | integer | 装配订单 ID |
| `orderCode` | string | 订单编码 |
| `article` | string | 货号 |
| `nmId` | integer | 商品 ID |
| `chrtId` | integer | 变体 ID |
| `rid` | string | 商品唯一标识 |
| `skus` | array | SKU 列表 |
| `price` / `finalPrice` | integer | 价格 / 最终价格 |
| `convertedPrice` / `convertedFinalPrice` | integer | 转换后价格 |
| `currencyCode` / `convertedCurrencyCode` | integer | 货币代码 |
| `salePrice` | integer | 销售价格 |
| `payMode` | string | 支付方式 (`prepaid`) |
| `requiredMeta` | array | 需要的标签标识类型 |
| `warehouseId` | integer | 仓库 ID |
| `warehouseAddress` | string | 仓库地址 |
| `cargoType` | integer | 货物类型 |
| `isZeroOrder` | boolean | 是否零元订单 |
| `ddate` | string | 日期 |
| `createdAt` | string | 创建时间 (ISO 8601) |

---

### 3.2 POST 转入装配

```
POST /api/marketplace/v3/click-collect/orders/status/confirm
```

**描述**：将装配订单从 `new` 状态转为 `confirm`（装配中）状态。

**认证**：`HeaderApiKey`

**请求体** (application/json)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `ordersIds` | Array\<integer\> | 是 | 装配订单 ID 列表，最多 1000 条 |

**请求示例**：

```json
{
  "ordersIds": [123456, 234567, 345678]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "requestId": "03615778-eb9e-4f55-b4O4-fd3ac0fad2cc",
  "results": [
    { "orderId": 123456, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}] },
    { "orderId": 234567, "isError": false }
  ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `requestId` | string | 请求 UUID |
| `results[].orderId` | integer | 订单 ID |
| `results[].isError` | boolean | 是否出错 |
| `results[].errors[].code` | integer | 错误码 |
| `results[].errors[].detail` | string | 错误详情 |

---

### 3.3 POST 通知装配订单可取货

```
POST /api/marketplace/v3/click-collect/orders/status/prepare
```

**描述**：将装配订单从 `confirm` 转为 `prepare`（可取货）状态。

**认证**：`HeaderApiKey`

**请求体** (application/json)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `ordersIds` | Array\<integer\> | 是 | 装配订单 ID 列表，最多 1000 条 |

**请求示例**：

```json
{
  "ordersIds": [123456, 234567, 345678]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "requestId": "03615778-eb9e-4f55-b4O4-fd3ac0fad2cc",
  "results": [
    { "orderId": 234567, "isError": false },
    { "orderId": 123456, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}] },
    {
      "orderId": 345678,
      "isError": true,
      "errors": [{
        "code": 409,
        "detail": "MetaValidationFail",
        "metaDetails": [{"key": "imei", "value": "359876543210925", "decision": "imeiAlreadySold"}]
      }]
    }
  ]
}
```

---

### 3.4 POST 获取买家信息

```
POST /api/v3/click-collect/orders/client
```

**描述**：根据装配订单 ID 获取买家信息（姓名、电话）。仅对 `confirm` 和 `prepare` 状态订单可用。

**认证**：`HeaderApiKey`

**限流**：1分钟 300 请求，间隔 200ms，突发 20 请求。

**请求体** (application/json, 必填)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `orders` | Array\<integer\> | 是 | 装配订单 ID 列表 |

**请求示例**：

```json
{
  "orders": [1234567]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "orders": [
    {
      "phone": "+7111111111",
      "firstName": "Ольга",
      "orderID": 4564152,
      "phoneCode": 3535
    }
  ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `orderID` | integer | 订单 ID |
| `firstName` | string | 买家姓名 |
| `phone` | string | 买家电话 |
| `phoneCode` | integer | 电话区号 |

---

### 3.5 POST 核验订单是否属于买家

```
POST /api/v3/click-collect/orders/client/identity
```

**描述**：通过验证码核验订单是否属于买家。仅在至少一个装配订单处于 `prepare` 状态时可用。

**认证**：`HeaderApiKey`

**限流**：1分钟 30 请求，间隔 2s，突发 20 请求。

**请求体** (application/json, 必填)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `orderCode` | string | 是 | 买家订单编码 |
| `passcode` | string | 是 | 验证码 |

**请求示例**：

```json
{
  "orderCode": "170046918-0011",
  "passcode": "4567"
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `404` / `409` / `429`

- `409`：验证码错误

**响应示例** (200)：

```json
{
  "ok": true
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `ok` | boolean | 核验是否通过 |

---

### 3.6 POST 通知买家已收货

```
POST /api/marketplace/v3/click-collect/orders/status/receive
```

**描述**：将装配订单从 `prepare` 转为 `receive`（买家已收货）状态。

**认证**：`HeaderApiKey`

**请求体** (application/json)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `ordersIds` | Array\<integer\> | 是 | 装配订单 ID 列表，最多 1000 条 |

**请求示例**：

```json
{
  "ordersIds": [123456, 234567, 345678]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "requestId": "03615778-eb9e-4f55-b4O4-fd3ac0fad2cc",
  "results": [
    { "orderId": 123456, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}] },
    { "orderId": 234567, "isError": false }
  ]
}
```

---

### 3.7 POST 通知买家拒收

```
POST /api/marketplace/v3/click-collect/orders/status/reject
```

**描述**：将装配订单从 `prepare` 转为 `reject`（买家拒收）状态。

**认证**：`HeaderApiKey`

**请求体** (application/json)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `ordersIds` | Array\<integer\> | 是 | 装配订单 ID 列表，最多 1000 条 |

**请求示例**：

```json
{
  "ordersIds": [123456, 234567, 345678]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "requestId": "03615778-eb9e-4f55-b4O4-fd3ac0fad2cc",
  "results": [
    { "orderId": 123456, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}] },
    { "orderId": 234567, "isError": false }
  ]
}
```

---

### 3.8 POST 获取装配订单状态

```
POST /api/marketplace/v3/click-collect/orders/status/info
```

**描述**：根据 ID 获取装配订单的状态。

**认证**：`HeaderApiKey`

**请求体** (application/json, 必填)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `ordersIds` | Array\<integer\> | 是 | 装配订单 ID 列表，最多 1000 条 |

**请求示例**：

```json
{
  "ordersIds": [123456, 234567, 345678]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "orders": [
    {
      "supplierStatus": "confirm",
      "wbStatus": "waiting",
      "errors": [],
      "orderId": 123456
    },
    {
      "supplierStatus": "",
      "wbStatus": "",
      "errors": [{"code": 404, "detail": "NotFound"}],
      "orderId": 789012
    }
  ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `orderId` | integer | 订单 ID |
| `supplierStatus` | string | 卖家侧状态 |
| `wbStatus` | string | WB 系统状态 |
| `errors` | array | 错误列表 |

---

### 3.9 GET 获取已完成装配订单信息

```
GET /api/v3/click-collect/orders
```

**描述**：获取销售完成或取消后的装配订单信息。每次请求最大时间跨度为 30 天。

**认证**：`HeaderApiKey`

**限流**：1分钟 300 请求，间隔 200ms，突发 20 请求。

**查询参数** (必填)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | integer [1..1000] | 是 | 每页最大返回数量 |
| `next` | integer | 是 | 分页偏移量，首次传 0，后续取响应中同名字段值 |
| `dateFrom` | integer (Unix timestamp) | 是 | 起始日期 |
| `dateTo` | integer (Unix timestamp) | 是 | 结束日期 |

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "next": 12345566,
  "orders": [
    {
      "article": "wb6scpbwvp",
      "cargoType": 1,
      "chrtId": 12345676,
      "createdAt": "2025-03-21T09:53:31Z",
      "price": 5000,
      "finalPrice": 5000,
      "convertedPrice": 5000,
      "convertedFinalPrice": 5000,
      "currencyCode": 643,
      "convertedCurrencyCode": 643,
      "id": 123456789,
      "isZeroOrder": false,
      "nmId": 1234567898765,
      "orderCode": "21117866-0006",
      "payMode": "prepaid",
      "rid": "5044304527347733263.0.0",
      "skus": ["2043227963145"],
      "warehouseAddress": "Москва, район Якиманка, Софийская набережная, 4 с1",
      "warehouseId": 1162157
    }
  ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `next` | integer | 下一页偏移量 |
| `orders` | array | 订单列表（字段同 [3.1](#31-get-获取新装配订单列表)） |

---

### 3.10 POST 取消装配订单

```
POST /api/marketplace/v3/click-collect/orders/status/cancel
```

**描述**：将装配订单从 `new`、`confirm`、`prepare` 状态转为 `cancel`（卖家取消）状态。

**认证**：`HeaderApiKey`

**请求体** (application/json)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `ordersIds` | Array\<integer\> | 是 | 装配订单 ID 列表，最多 1000 条 |

**请求示例**：

```json
{
  "ordersIds": [123456, 234567, 345678]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "requestId": "03615778-eb9e-4f55-b4O4-fd3ac0fad2cc",
  "results": [
    { "orderId": 123456, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}] },
    { "orderId": 234567, "isError": false }
  ]
}
```

---

## 4. 标签标识符 API

> Token 类别：**Marketplace**
> 支持标识符类型：`sgtin` (Chestny ZNAK)、`uin`、`imei`、`gtin`

---

### 4.1 POST 获取标签标识符详情

```
POST /api/marketplace/v3/click-collect/orders/meta/details
```

**描述**：返回装配订单的标签标识符及其验证状态。

**认证**：`HeaderApiKey`

**限流**：1分钟 150 请求，间隔 400ms，突发 20 请求。

**请求体** (application/json)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `ordersIds` | Array\<integer\> | 是 | 装配订单 ID 列表，最多 1000 条 |

**请求示例**：

```json
{
  "ordersIds": [123456, 234567, 345678]
}
```

**响应码**：`200` / `400` / `401` / `403` / `429`

**响应示例** (200)：

```json
{
  "requestId": "f1787bd2d1fdc35d6f537316514y4a05",
  "orders": [
    {
      "orderId": 123456,
      "isError": false,
      "errors": [],
      "metaDetails": [
        { "key": "imei", "value": "359876543210025", "decision": "imeiInvalidFormat" }
      ]
    }
  ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `orderId` | integer | 订单 ID |
| `isError` | boolean | 是否出错 |
| `metaDetails[].key` | string | 标识符类型 |
| `metaDetails[].value` | string | 标识符值 |
| `metaDetails[].decision` | string | 验证结果 |

---

### 4.2 POST 获取标签标识符信息 (已废弃)

```
POST /api/marketplace/v3/click-collect/orders/meta/info
```

> ⚠️ **已废弃**，将于 7月15日 移除。请使用 [4.1 POST 获取标签标识符详情](#41-post-获取标签标识符详情)。

**认证**：`HeaderApiKey`

**限流**：1分钟 150 请求，间隔 400ms，突发 20 请求。

**请求体** (application/json)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `ordersIds` | Array\<integer\> | 是 | 装配订单 ID 列表，最多 1000 条 |

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "meta": [
    {
      "error": "",
      "gtin": "123456789012345",
      "imei": "123456789012345",
      "orderId": 654321,
      "sgtin": ["123456789012345"],
      "uin": "123456789012345"
    }
  ]
}
```

---

### 4.3 POST 删除标签标识符

```
POST /api/marketplace/v3/click-collect/orders/meta/delete
```

**描述**：删除装配订单的标签标识符值。每次请求只能删除一种类型。

**认证**：`HeaderApiKey`

**限流**：1分钟 150 请求，间隔 400ms，突发 20 请求。

**请求体** (application/json, 必填)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `key` | string | 是 | 要删除的标识符类型：`imei` / `uin` / `gtin` / `sgtin` |
| `ordersIds` | Array\<integer\> | 是 | 装配订单 ID 列表，最多 1000 条 |

**请求示例**：

```json
{
  "key": "imei",
  "ordersIds": [123456, 234567]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "requestId": "03615778-eb9e-4f55-b4O4-fd3ac0fad2cc",
  "results": [
    { "orderId": 123456, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}] },
    { "orderId": 234567, "isError": false }
  ]
}
```

---

### 4.4 POST 添加 Chestny ZNAK 标识码

```
POST /api/marketplace/v3/click-collect/orders/meta/sgtin
```

**描述**：为装配订单设置 Chestny ZNAK 标识码。仅对 `confirm` 状态且 `requiredMeta` 包含 `sgtin` 的订单可用。

**认证**：`HeaderApiKey`

**限流**：1分钟 20 请求，间隔 3s，突发 500 请求。

**请求体** (application/json, 必填)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `orders` | Array\<object\> | 是 | 最多 1000 条 |
| `orders[].orderId` | integer | 是 | 装配订单 ID |
| `orders[].sgtins` | Array\<string\> | 是 | Chestny ZNAK 码列表 |

**请求示例**：

```json
{
  "orders": [
    {
      "orderId": 123456,
      "sgtins": ["123456789012345678", "1234567890123456"]
    }
  ]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "requestId": "03615778-eb9e-4f55-b4O4-fd3ac0fad2cc",
  "results": [
    { "orderId": 123456, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}] },
    { "orderId": 234567, "isError": false }
  ]
}
```

---

### 4.5 POST 添加 UIN

```
POST /api/marketplace/v3/click-collect/orders/meta/uin
```

**描述**：为装配订单设置 UIN（唯一识别号）。每个订单只能有一个 UIN。仅对 `confirm` 状态且由 WB 配送的订单可用。

**认证**：`HeaderApiKey`

**限流**：1分钟 20 请求，间隔 3s，突发 500 请求。

**请求体** (application/json, 必填)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `orders` | Array\<object\> | 是 | 最多 1000 条 |
| `orders[].orderId` | integer | 是 | 装配订单 ID |
| `orders[].uin` | string | 是 | UIN 值 |

**请求示例**：

```json
{
  "orders": [
    { "orderId": 123456, "uin": "1234568909091232" }
  ]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "requestId": "03615778-eb9e-4f55-b4O4-fd3ac0fad2cc",
  "results": [
    { "orderId": 123456, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}] },
    { "orderId": 234567, "isError": false }
  ]
}
```

---

### 4.6 POST 添加 IMEI

```
POST /api/marketplace/v3/click-collect/orders/meta/imei
```

**描述**：为装配订单设置 IMEI。每个订单只能有一个 IMEI。仅对 `confirm` 状态且由 WB 配送的订单可用。

**认证**：`HeaderApiKey`

**限流**：1分钟 20 请求，间隔 3s，突发 500 请求。

**请求体** (application/json, 必填)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `orders` | Array\<object\> | 是 | 最多 1000 条 |
| `orders[].orderId` | integer | 是 | 装配订单 ID |
| `orders[].imei` | string | 是 | IMEI 值 |

**请求示例**：

```json
{
  "orders": [
    { "orderId": 123456, "imei": "654321741987258" }
  ]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "requestId": "03615778-eb9e-4f55-b4O4-fd3ac0fad2cc",
  "results": [
    { "orderId": 123456, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}] },
    { "orderId": 234567, "isError": false }
  ]
}
```

---

### 4.7 POST 添加 GTIN

```
POST /api/marketplace/v3/click-collect/orders/meta/gtin
```

**描述**：为装配订单设置 GTIN（白俄罗斯商品唯一标识）。每个订单只能有一个 GTIN。仅对 `confirm` 状态且由 WB 配送的订单可用。

**认证**：`HeaderApiKey`

**限流**：1分钟 20 请求，间隔 3s，突发 500 请求。

**请求体** (application/json, 必填)：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `orders` | Array\<object\> | 是 | 最多 1000 条 |
| `orders[].orderId` | integer | 是 | 装配订单 ID |
| `orders[].gtin` | string | 是 | GTIN 值 |

**请求示例**：

```json
{
  "orders": [
    { "gtin": "1234567890123", "orderId": 123456 }
  ]
}
```

**响应码**：`200` / `400` / `401` / `402` / `403` / `429`

**响应示例** (200)：

```json
{
  "requestId": "03615778-eb9e-4f55-b4O4-fd3ac0fad2cc",
  "results": [
    { "orderId": 123456, "isError": true, "errors": [{"code": 404, "detail": "NotFound"}] },
    { "orderId": 234567, "isError": false }
  ]
}
```

---

## 5. 限流规则汇总

| API 组 | 周期 | 限制 | 间隔 | 突发 |
|--------|------|------|------|------|
| 装配订单 (orders/new, client, orders, 等) | 1 min | 300 | 200ms | 20 |
| 核验买家身份 (client/identity) | 1 min | 30 | 2s | 20 |
| 获取/删除标签标识符 | 1 min | 150 | 400ms | 20 |
| 添加标签标识符 (sgtin/uin/imei/gtin) | 1 min | 20 | 3s | 500 |
| 状态变更 (confirm/prepare/receive/reject/cancel/info) | — | 未指定 | — | — |

> 注意：4XX 响应码计为 **10 次**请求。

---

## 6. 响应码汇总

| 状态码 | 含义 |
|--------|------|
| `200` | 成功 |
| `400` | 请求参数错误 |
| `401` | 未认证 |
| `402` | 需要付款 |
| `403` | 访问被拒 |
| `404` | 未找到 |
| `409` | 冲突 (如验证码错误) |
| `429` | 请求过于频繁 |

---

## 通用响应结构

**批量操作响应** (confirm / prepare / receive / reject / cancel / sgtin / uin / imei / gtin / delete)：

```json
{
  "requestId": "UUID",
  "results": [
    {
      "orderId": 123456,
      "isError": true,
      "errors": [
        { "code": 404, "detail": "NotFound" }
      ]
    }
  ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `requestId` | string (UUID) | 请求唯一标识 |
| `results[].orderId` | integer | 订单 ID |
| `results[].isError` | boolean | 是否处理出错 |
| `results[].errors[].code` | integer | 错误码 |
| `results[].errors[].detail` | string | 错误详情 |
| `results[].errors[].metaDetails` | array | 元数据验证详情 (仅某些接口) |
