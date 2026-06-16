# Wildberries Product Management API

> 商品管理 API：类目与属性、商品卡片、媒体文件、标签、价格与折扣、卖家仓库及库存
>
> 主要 Base URLs:
> - Content API: `https://content-api.wildberries.ru`
> - Marketplace API: `https://marketplace-api.wildberries.ru`
> - Discounts & Prices API: `https://discounts-prices-api.wildberries.ru`
>
> Token 类型: **Content**（商品内容相关） / **Marketplace**（仓库、库存相关） / **Prices and Discounts**（价格相关）

---

## 目录

- [Categories, Subjects, and Characteristics](#categories-subjects-and-characteristics)
- [Creating Product Cards](#creating-product-cards)
- [Product Cards](#product-cards)
- [Media Files](#media-files)
- [Tags](#tags)
- [Prices and Discounts](#prices-and-discounts)
- [Seller Warehouses](#seller-warehouses)
- [Seller Warehouses Inventory](#seller-warehouses-inventory)

---

## Categories, Subjects, and Characteristics

> Token 类型: **Content**
>
> 通用限速（除创建/编辑卡片等例外接口）：1 分钟 100 请求，间隔 600 ms，突发 5 请求。

---

### 1. GET Products Parent Categories

```
GET /content/v2/object/parent/all
```

**描述**: 返回所有商品父类目。

**Query 参数**: `locale` — `ru`/`en`/`zh`

**响应示例 (200)**:

```json
{
  "data": [{"name": "Электроника", "id": 479, "isVisible": true}],
  "error": false,
  "errorText": "",
  "additionalErrors": ""
}
```

---

### 2. GET Subjects List

```
GET /content/v2/object/all
```

**描述**: 返回所有可用主题（subject）及其父类目 ID。

**Query 参数**:

| 参数 | 说明 |
|------|------|
| `locale` | 语言 |
| `name` | 按名称子串搜索 |
| `limit` | 默认 30，最大 1000 |
| `offset` | 偏移量 |
| `parentID` | 父类目 ID |

---

### 3. GET Subject Characteristics

```
GET /content/v2/object/charcs/{subjectId}
```

**描述**: 根据主题 ID 返回其属性列表。

**Path 参数**: `subjectId`

**Query 参数**: `locale`

**响应示例 (200)**:

```json
{
  "data": [{
    "charcID": 54337,
    "subjectName": "Кроссовки",
    "subjectID": 105,
    "name": "Размер",
    "required": false,
    "unitName": "см",
    "maxCount": 0,
    "popular": false,
    "charcType": 4,
    "hasFilter": true,
    "isVariable": true,
    "existNamedField": true
  }],
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

---

### 4. GET Color

```
GET /content/v2/directory/colors
```

**描述**: 颜色属性可选值。

**Query 参数**: `locale`

---

### 5. GET Gender

```
GET /content/v2/directory/kinds
```

**描述**: 性别属性可选值。

---

### 6. GET Country of Origin

```
GET /content/v2/directory/countries
```

**描述**: 原产国属性可选值。

---

### 7. GET Season

```
GET /content/v2/directory/seasons
```

**描述**: 季节属性可选值。

---

### 8. GET VAT Rate

```
GET /content/v2/directory/vat
```

**描述**: 增值税率可选值。

**响应示例 (200)**:

```json
{"data": ["0", "10", "20", "Без НДС", "13"], "error": false, "errorText": "", "additionalErrors": null}
```

---

### 9. GET HS-codes

```
GET /content/v2/directory/tnved
```

**描述**: 根据类目名称和 HS 编码过滤返回 HS 编码列表。

**Query 参数**:

| 参数 | 必填 | 说明 |
|------|------|------|
| `subjectID` | 是 | 主题 ID |
| `search` | 否 | HS 编码搜索 |
| `locale` | 否 | 语言 |

**响应示例 (200)**:

```json
{"data": [{"tnved": "6106903000", "isKiz": true}], "error": false, "errorText": "", "additionalErrors": null}
```

---

### 10. GET Brands

```
GET /api/content/v1/brands
```

**描述**: 根据主题 ID 返回品牌列表。

**Query 参数**: `subjectId`（必填）, `next`（分页）

**限速**: Personal/Service/Base with secret：1 秒 1 请求；Base：1 小时 1 请求

**响应示例 (200)**:

```json
{"brands": [{"id": 9007199254, "logoUrl": "string", "name": "Brand"}], "next": 1212, "total": 344534}
```

---

## Creating Product Cards

> Token 类型: **Content**

---

### 1. GET Limits for the Product Cards

```
GET /content/v2/cards/limits
```

**描述**: 获取创建商品卡片的免费/付费额度。

**响应示例 (200)**:

```json
{"data": {"freeLimits": 1500, "paidLimits": 10}, "error": false, "errorText": "", "additionalErrors": null}
```

---

### 2. POST Generation of SKUs

```
POST /content/v2/barcodes
```

**描述**: 生成唯一 SKU（条码），用于创建商品尺寸。

**请求体**: `{"count": 100}` — 最多 5,000

**响应示例 (200)**:

```json
{"data": ["5032781145187"], "error": false, "errorText": "", "additionalErrors": ""}
```

---

### 3. POST Create Product Cards

```
POST /content/v2/cards/upload
```

**描述**: 创建商品卡片。

**创建流程**:

1. 获取父类目 → 主题 → 主题属性
2. 颜色/性别/原产国/季节/增值税率/HS 编码使用目录接口值
3. 发送请求。若返回成功但卡片未创建，查询失败列表

**限制**:

- 尺寸和重量单位分别为 `cm` 和 `kg`
- 单次最多 100 个独立卡片或 100 组合并卡片，每组最多 30 个 `nmID`
- 最大请求体 10 MB
- 异步创建，同步服务最长 30 分钟

**限速**: 1 分钟 10 请求，间隔 6 秒，突发 5 请求

**请求体**（数组）:

```json
[{
  "subjectID": 105,
  "variants": [{
    "barcode": "5032781145187",
    "vendorCode": "SHOE-001",
    "title": "Sneakers",
    "description": "...",
    "brand": "Brand",
    "dimensions": { "length": 30, "width": 20, "height": 10, "weight": 0.5 },
    "characteristics": [{ "id": 54337, "value": ["42"] }],
    "sizes": [{ "price": 1999, "skus": ["5032781145187"] }]
  }]
}]
```

**响应码**: `200` | `400` | `401` | `402` | `413` | `429`

---

### 4. POST Create Product Cards with Merge

```
POST /content/v2/cards/upload/add
```

**描述**: 创建商品卡片并合并到现有卡片。

---

## Product Cards

> Token 类型: **Content**

---

### 1. POST Product Cards List

```
POST /content/v2/get/cards/list
```

**描述**: 返回商品卡片列表。

---

### 2. POST List of Failed Product Cards with Errors

```
POST /content/v2/cards/error/list
```

**描述**: 返回创建失败的商品卡片及错误。

---

### 3. POST Update Product Cards

```
POST /content/v2/cards/update
```

**描述**: 更新商品卡片。

---

### 4. POST Merging or Separating of Product Cards

```
POST /content/v2/cards/moveNm
```

**描述**: 合并或拆分商品卡片。

---

### 5. POST Transfer Product Card to Trash

```
POST /content/v2/cards/delete/trash
```

**描述**: 将商品卡片移至回收站。

---

### 6. POST Recover Product Card from Trash

```
POST /content/v2/cards/recover
```

**描述**: 从回收站恢复商品卡片。

---

### 7. POST Product Cards in Trash List

```
POST /content/v2/get/cards/trash
```

**描述**: 返回回收站中的商品卡片列表。

---

## Media Files

> Token 类型: **Content**

---

### 1. POST Upload Media File

```
POST /content/v3/media/file
```

**描述**: 上传媒体文件（图片/视频）。

---

### 2. POST Upload Media Files via Links

```
POST /content/v3/media/save
```

**描述**: 通过链接上传媒体文件。

---

## Tags

> Token 类型: **Content**

---

### 1. GET Tags List

```
GET /content/v2/tags
```

**描述**: 返回标签列表。

---

### 2. POST Create a Tag

```
POST /content/v2/tag
```

**描述**: 创建标签。

---

### 3. PATCH Update the Tag

```
PATCH /content/v2/tag/{id}
```

**描述**: 更新标签。

**Path 参数**: `id`

---

### 4. DELETE Delete the Tag

```
DELETE /content/v2/tag/{id}
```

**描述**: 删除标签。

---

### 5. POST Tag Management in the Product Card

```
POST /content/v2/tag/nomenclature/link
```

**描述**: 管理商品卡片中的标签关联。

---

## Prices and Discounts

> Base URL: `https://discounts-prices-api.wildberries.ru`
>
> Token 类型: **Prices and Discounts**
>
> 限速（Personal/Service/Base with secret）：6 秒 10 请求，间隔 600 ms，突发 5 请求；Base：1 小时 4 请求。

---

### 1. POST Set Prices and Discounts

```
POST /api/v2/upload/task
```

**描述**: 设置商品价格与折扣。

**请求体**:

```json
{"data": [{"nmID": 123, "price": 999, "discount": 30}]}
```

**响应示例 (200)**:

```json
{"data": {"id": 0, "alreadyExists": false}, "error": false, "errorText": ""}
```

---

### 2. POST Set Size Prices

```
POST /api/v2/upload/task/size
```

**描述**: 设置按尺寸定价。

**请求体**:

```json
{"data": [{"nmID": 123, "sizeID": 98989887, "price": 999}]}
```

---

### 3. POST Set WB Club Discounts

```
POST /api/v2/upload/task/club-discount
```

**描述**: 设置 WB Club 订阅折扣。

**请求体**: `{"data": [{"nmID": 123, "clubDiscount": 5}]}`

---

### 4. POST Set Wholesale Discounts for B2B

```
POST /api/discounts-prices/v1/upload/task/b2b/wholesale
```

**描述**: 设置 B2B 批发折扣。

**请求体**:

```json
{
  "data": [{
    "nmId": 694707813,
    "wholesaleDiscountThreshold": [
      {"minQuantity": 11, "wholesaleDiscount": 14, "level": 1},
      {"minQuantity": 18, "wholesaleDiscount": 19, "level": 3}
    ]
  }]
}
```

**响应示例 (200)**:

```json
{
  "id": 128460434,
  "alreadyExists": false,
  "results": [
    {"nmId": 1, "success": false, "error": {"status": 400, "title": "Bad Request", "detail": "Invalid item No."}},
    {"nmId": 694707813, "success": true}
  ]
}
```

---

### 5. GET Processed Upload State

```
GET /api/v2/history/tasks
```

**描述**: 返回已处理上传任务状态。

**Query 参数**: `uploadID`（必填）

**响应示例 (200)**:

```json
{
  "data": {
    "uploadID": 395643565,
    "status": 3,
    "uploadDate": "2022-08-21T22:00:13+02:00",
    "activationDate": "2022-08-21T22:00:13+02:00",
    "overAllGoodsNumber": 0,
    "successGoodsNumber": 0
  },
  "error": false,
  "errorText": ""
}
```

---

### 6. GET Processed Upload Details

```
GET /api/v2/history/goods/task
```

**描述**: 返回已处理上传任务中的商品详情及错误。

**Query 参数**: `limit`（必填）, `offset`, `uploadID`（必填）

---

### 7. GET Unprocessed Upload State

```
GET /api/v2/buffer/tasks
```

**描述**: 返回处理中上传任务状态。

**Query 参数**: `uploadID`

---

### 8. GET Unprocessed Upload Details

```
GET /api/v2/buffer/goods/task
```

**描述**: 返回处理中上传任务商品详情。

---

### 9. GET Get Products with Prices

```
GET /api/v2/list/goods/filter
```

**描述**: 返回商品数据。单次请求只能指定一个 article。获取全部商品时不设 article，limit=1000，用 offset 翻页。

**Query 参数**: `limit`（必填）, `offset`, `filterNmID`

**响应示例 (200)**:

```json
{
  "data": {
    "listGoods": [{
      "nmID": 98486,
      "vendorCode": "07326060",
      "sizes": [{"sizeID": 3123515574, "price": 500, "discountedPrice": 350, "clubDiscountedPrice": 332.5, "techSizeName": "42"}],
      "currencyIsoCode4217": "RUB",
      "discount": 30,
      "clubDiscount": 5,
      "editableSizePrice": true,
      "wholesaleDiscountThreshold": [{"minQuantity": 10, "wholesaleDiscount": 10, "level": 1}],
      "isBadTurnover": true
    }]
  },
  "error": false,
  "errorText": ""
}
```

---

### 10. POST Get Products with Prices by Articles

```
POST /api/v2/list/goods/filter
```

**描述**: 根据多个 article 返回商品数据。

**请求体**: `{"nmList": [26613989,1348041]}`

---

### 11. GET Get Product Sizes with Prices

```
GET /api/v2/list/goods/size/nm
```

**描述**: 返回商品的尺寸价格数据。仅对 `editableSizePrice:true` 的商品有效。

**Query 参数**: `limit`（必填）, `offset`, `nmID`（必填）

---

### 12. GET Get Products in Quarantine

```
GET /api/v2/quarantine/goods
```

**描述**: 返回处于价格隔离区的商品信息。新价折后低于旧价 3 倍时进入隔离。

**Query 参数**: `limit`（必填）, `offset`

**响应示例 (200)**:

```json
{
  "data": {
    "quarantineGoods": [{
      "nmID": 206025152,
      "sizeID": null,
      "techSizeName": "",
      "currencyIsoCode4217": "RUB",
      "newPrice": 134,
      "oldPrice": 4000,
      "newDiscount": 25,
      "oldDiscount": 25,
      "priceDiff": -2899.5
    }]
  },
  "error": false,
  "errorText": ""
}
```

---

## Seller Warehouses

> Base URL: `https://marketplace-api.wildberries.ru`
>
> Token 类型: **Marketplace**
>
> 所有卖家仓库接口统一限速：1 分钟 300 请求，间隔 200 ms，突发 20 请求。4XX 计为 10 次。

---

### 1. GET Get Offices

```
GET /api/v3/offices
```

**描述**: 返回可绑定到卖家仓库的所有办公点/仓库列表。

**响应示例 (200)**:

```json
[{
  "address": "ул. Троицкая, Подольск, Московская обл.",
  "name": "Коледино",
  "city": "Москва",
  "id": 15,
  "longitude": 55.386871,
  "latitude": 37.588898,
  "cargoType": 1,
  "deliveryType": 1,
  "federalDistrict": "Центральный",
  "selected": true
}]
```

---

### 2. GET Get Warehouses

```
GET /api/v3/warehouses
```

**描述**: 返回卖家所有仓库。

**响应示例 (200)**:

```json
[{
  "name": "Kosmonavtov 14",
  "officeId": 15,
  "id": 1,
  "cargoType": 1,
  "deliveryType": 1,
  "isDeleting": false,
  "isProcessing": true
}]
```

---

### 3. POST Create Warehouse

```
POST /api/v3/warehouses
```

**描述**: 创建卖家仓库。已使用的 office 不能重复绑定。

**请求体**:

```json
{"name": "Koledino 2", "officeId": 15}
```

**响应码**: `201` Created

**响应示例 (201)**:

```json
{"id": 2}
```

---

### 4. PUT Update Warehouse

```
PUT /api/v3/warehouses/{warehouseId}
```

**描述**: 更新卖家仓库。每天只能修改一次绑定的 office。

**Path 参数**: `warehouseId`

**请求体**: `{"name": "Koledino", "officeId": 15}`

---

### 5. DELETE Delete Warehouse

```
DELETE /api/v3/warehouses/{warehouseId}
```

**描述**: 删除卖家仓库。

---

### 6. GET Contacts List

```
GET /api/v3/dbw/warehouses/{warehouseId}/contacts
```

**描述**: 返回绑定到 DBW 仓库（deliveryType=3）的联系人列表。

**Path 参数**: `warehouseId`

**响应示例 (200)**:

```json
{"contacts": [{"comment": "Иванов Иван Иванович. Звонить с 10 до 21 часа.", "phone": "+79998887766"}]}
```

---

### 7. PUT Update Contacts List

```
PUT /api/v3/dbw/warehouses/{warehouseId}/contacts
```

**描述**: 更新仓库联系人列表。更新为覆盖式，需包含所有联系人。最多 5 个联系人，传空数组删除全部。

**Path 参数**: `warehouseId`

**请求体**:

```json
{"contacts": [{"comment": "Иванов Иван Иванович. Звонить с 10 до 21 часа.", "phone": "+79998887766"}]}
```

---

## Seller Warehouses Inventory

> Base URL: `https://marketplace-api.wildberries.ru`
>
> Token 类型: **Marketplace**

---

### 1. PUT Update Inventory

```
PUT /api/v3/stocks/{warehouseId}
```

**描述**: 更新商品库存。

> 参数名不校验，错误参数名会返回 204 但不会更新库存。

**Path 参数**: `warehouseId`

**请求体**:

```json
{"stocks": [{"chrtId": 12345678, "amount": 10}]}
```

**响应码**: `204` Updated | `400` | `401` | `402` | `403` | `404` | `406` | `409` | `429`

**限速**: 1 分钟 300 请求，间隔 200 ms，突发 20 请求

---

### 2. DELETE Delete Inventory

```
DELETE /api/v3/stocks/{warehouseId}
```

**描述**: 删除商品库存。⚠️ 不可逆，删除后需重新上传才能继续销售。

**Path 参数**: `warehouseId`

**请求体**: `{"chrtIds": [123456789]}`

**限速**: 1 分钟 10 请求，间隔 6 秒，突发 2 请求

---

### 3. POST Get Inventory

```
POST /api/v3/stocks/{warehouseId}
```

**描述**: 返回商品库存。

**Path 参数**: `warehouseId`

**请求体**: `{"chrtIds": [12345678]}`

**响应码**: `200` Success
