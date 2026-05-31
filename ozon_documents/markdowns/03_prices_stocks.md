# 价格、折扣与库存 API

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v2/products/stocks` | Update the quantity of products in stock |
| POST | `/v4/product/info/stocks` | Information about product quantity |
| POST | `/v1/product/info/warehouse/stocks` | Get information on stock in FBS and rFBS warehouse |
| POST | `/v1/product/info/stocks-by-warehouse/fbs` | Stocks in seller's warehouses (FBS и rFBS) |
| POST | `/v1/product/import/prices` | Update prices |
| POST | `/v1/product/action/timer/update` | Update the minimum price relevance timer |
| POST | `/v1/product/action/timer/status` | Get status of timer you've set |
| POST | `/v5/product/info/prices` | Get product price information |
| POST | `/v1/product/info/discounted` | Get information about the markdown and the main product by the markdown product SKU |
| POST | `/v1/product/update/discount` | Set a discount on a markdown product |
| POST | `/v1/pricing-strategy/competitors/list` | List of competitors |
| POST | `/v1/pricing-strategy/list` | List of strategies |
| POST | `/v1/pricing-strategy/create` | Create a pricing strategy |
| POST | `/v1/pricing-strategy/info` | Strategy info |
| POST | `/v1/pricing-strategy/update` | Update strategy |
| POST | `/v1/pricing-strategy/products/add` | Bind products to a strategy |
| POST | `/v1/pricing-strategy/strategy-ids-by-product-ids` | List of strategy identifiers |
| POST | `/v1/pricing-strategy/products/list` | List of products in a strategy |
| POST | `/v1/pricing-strategy/product/info` | Competitor's product price |
| POST | `/v1/pricing-strategy/products/delete` | Remove products from a strategy |
| POST | `/v1/pricing-strategy/status` | Change strategy status |
| POST | `/v1/pricing-strategy/delete` | Delete a pricing strategy |

---

## 接口详情


### POST `/v2/products/stocks`
**Update the quantity of products in stock**  
operationId: `ProductAPI_ProductsStocksV2`  

Allows you to change the products in stock quantity.

<aside class="warning">
 Passed stock is the number of products available for sale without taking reserved products into account. Before updating the stock, check the number of reserved products using the <a href=“#operation/ProductAPI_ProductStocksByWarehouseFbs”>/v1/product/info/stocks-by-warehouse/fbs</a> method.  
</aside>

With one request you can change the availability for 100 product-warehouse pairs. You can send up to 80 requests per minute in one account.

<aside class="warning">You can update the stock of one product-warehouse pa

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `stocks` | array[productv2ProductsStocksRequestStock] | ✓ | Information about the products at the warehouses. |

**响应 200**: Quantity of products updated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[productv2ProductsStocksResponseResult] |  |  |
**响应 400**: Invalid parameter
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |
**响应 403**: Access denied
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v4/product/info/stocks`
**Information about product quantity**  
operationId: `ProductAPI_GetProductInfoStocks`  

Returns information about the quantity of products under the FBS, rFBS, and FBP schemes:
  - how many items are available,
  - how many are reserved by customers.

To get stock information under the FBO scheme, use the [/v1/analytics/stocks](#operation/AnalyticsAPI_AnalyticsStocks) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `filter` | `v4GetProductInfoStocksRequestFilter` | ✓ |  |
| `limit` | integer | ✓ | Limit on number of entries in a reply. Default value is 1000. Maximum value is 1000. |

**响应 200**: Products quantity
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `items` | array[v4GetProductInfoStocksResponseItem] |  | Product details. |
| `total` | integer |  | The number of unique products for which information about stocks is displayed. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/info/warehouse/stocks`
**Get information on stock in FBS and rFBS warehouse**  
operationId: `ProductInfoWarehouseStocks`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `limit` | integer | ✓ | Number of values per page. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Product quantity in FBS and rFBS warehouse
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. If the parameter is empty, there is no more data. |
| `has_next` | boolean |  | Indicates that the response returned not all products: - `true` — make a new request with a differen |
| `stocks` | array[ProductInfoWarehouseStocksResponseStocks] |  | Product stock information. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/info/stocks-by-warehouse/fbs`
**Stocks in seller's warehouses (FBS и rFBS)**  
operationId: `ProductAPI_ProductStocksByWarehouseFbs`  

Pass `offer_id` or `sku` in the request. If you specify both parameters, only `sku` is used.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sku` | any |  | Product identifier in the Ozon system, SKU. |
| `offer_id` | any |  | Product identifier in the seller's system. |

**响应 200**: Number of products in FBS and rFBS warehouses
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | any |  | Method result. |
**响应 400**: Invalid parameter
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |
**响应 403**: Access denied
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/import/prices`
**Update prices**  
operationId: `ProductAPI_ImportProductsPrices`  

Allows you to change a price of one or more products.
The price of each product can be updated no more than 10 times per hour.
To reset `old_price`, set `0` for this parameter.

If the request contains both the `offer_id` and `product_id` parameters, the changes will be applied to the product with the `offer_id`. To avoid ambiguity, use only one of the parameters.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `prices` | array[productImportProductsPricesRequestPrice] |  | Product prices details. |

**响应 200**: Price updated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[productImportProductsPricesResponseProcessResult] |  |  |
**响应 400**: Invalid parameter
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |
**响应 403**: Access denied
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/action/timer/update`
**Update the minimum price relevance timer**  
operationId: `ProductAPI_ActionTimerUpdate`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `product_ids` | array[string] |  | List of product identifiers. |

**响应 200**: Updated
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/action/timer/status`
**Get status of timer you've set**  
operationId: `ProductAPI_ActionTimerStatus`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `product_ids` | any |  | List of product identifiers. |

**响应 200**: Statuses
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `statuses` | any |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v5/product/info/prices`
**Get product price information**  
operationId: `ProductAPI_GetProductInfoPrices`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `filter` | `productv5Filter` | ✓ |  |
| `limit` | integer | ✓ | Number of values per page. |

**响应 200**: Product price information
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `items` | any |  | Product list. |
| `total` | integer |  | Products number in the list. |
**响应 400**: Invalid parameter
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |
**响应 403**: Access denied
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/info/discounted`
**Get information about the markdown and the main product by the markdown product SKU**  
operationId: `ProductAPI_GetProductInfoDiscounted`  

A method for getting information about the condition and defects of a markdown product by its SKU. Works only with discounted products under the FBO scheme. The method also returns the SKU of the main product.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `discounted_skus` | any | ✓ | Markdown products SKUs list. |

**响应 200**: Information about the markdown and the main product
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | any |  | Information about the markdown and the main product. |
**响应 400**: Invalid parameter
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |
**响应 403**: Access denied
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/update/discount`
**Set a discount on a markdown product**  
operationId: `ProductAPI_ProductUpdateDiscount`  

A method for setting the discount percentage on markdown products sold under the FBS scheme.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `discount` | integer | ✓ | Discount amount: from 3 to 99 percents.  |
| `product_id` | integer | ✓ | Product identifier in the Ozon system, `product_id`. |

**响应 200**: Success
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | boolean |  | Method result. `true` if the query was executed without errors. |
**响应 400**: Invalid parameter
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |
**响应 403**: Access denied
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/competitors/list`
**List of competitors**  
operationId: `pricing_competitors`  

Method for getting a list of competitors—sellers with similar products in other online stores and marketplaces.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | integer | ✓ | Page number from which you want to download the list of competitors. The minimum value is `1`. |
| `limit` | integer | ✓ | Maximum number of competitors on the page. Allowed values: 1–50.  |

**响应 200**: List of competitors
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `competitor` | array[GetCompetitorsResponseCompetitorInfo] |  | List of competitors. |
| `total` | integer |  | Total number of competitors. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/list`
**List of strategies**  
operationId: `pricing_list`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | integer | ✓ | Page number from which you want to download the list of competitors. The minimum value is `1`. |
| `limit` | integer | ✓ | Maximum number of competitors on the page. Allowed values: 1–50.  |

**响应 200**: List of strategies
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `strategies` | array[GetStrategyListResponseStrategy] |  | List of strategies. |
| `total` | integer |  | Total number of strategies. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/create`
**Create a pricing strategy**  
operationId: `pricing_create`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `competitors` | array[v1Competitor] | ✓ | List of competitors. |
| `strategy_name` | string | ✓ | Strategy name. |

**响应 200**: Pricing strategy created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1CreatePricingStrategyResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/info`
**Strategy info**  
operationId: `pricing_info`  

**响应 200**: Strategy info
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1GetStrategyResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/update`
**Update strategy**  
operationId: `pricing_update`  

You can update all strategies except the system one.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `competitors` | array[v1Competitor] | ✓ | List of competitors. |
| `strategy_id` | string | ✓ | Product identifier. |
| `strategy_name` | string | ✓ | Strategy name. |

**响应 200**: Strategy updated
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/products/add`
**Bind products to a strategy**  
operationId: `pricing_items-add`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `product_id` | array[string] | ✓ | List of product identifiers. The maximum number is 50. |
| `strategy_id` | string | ✓ | Product identifier. |

**响应 200**: Errors when binding products
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1AddStrategyItemsResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/strategy-ids-by-product-ids`
**List of strategy identifiers**  
operationId: `pricing_ids`  

**响应 200**: List of identifiers
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1GetStrategyIDsByItemIDsResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/products/list`
**List of products in a strategy**  
operationId: `pricing_items-list`  

**响应 200**: List of products
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1GetStrategyItemsResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/product/info`
**Competitor's product price**  
operationId: `pricing_items-info`  

If you add a product to your pricing strategy, the method returns you the price and a link to the competitor's product.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `product_id` | integer | ✓ | Product identifier in the Ozon system, `product_id`. |

**响应 200**: Competitor's product price
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1GetStrategyItemInfoResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/products/delete`
**Remove products from a strategy**  
operationId: `pricing_items-delete`  

**响应 200**: Errors when removing products
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1DeleteStrategyItemsResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/status`
**Change strategy status**  
operationId: `pricing_status`  

You can change the status of any strategy except the system one.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `enabled` | boolean |  | Strategy status: - `true`—enabled, - `false`—disabled.  |
| `strategy_id` | string | ✓ | Product identifier. |

**响应 200**: Strategy status changed
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/pricing-strategy/delete`
**Delete a pricing strategy**  
operationId: `pricing_delete`  

You can delete any strategy except the system one.

**响应 200**: Strategy deleted
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---