# 数据分析 API

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

More methods in the [**Premium Methods**](#tag/Premium) section.

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v2/analytics/stock_on_warehouses` | Stocks and products report |
| POST | `/v1/analytics/turnover/stocks` | Product turnover |
| POST | `/v1/analytics/average-delivery-time` | Get analytics of average delivery time |
| POST | `/v1/analytics/average-delivery-time/details` | Get detailed analytics of average delivery time |
| POST | `/v1/analytics/average-delivery-time/summary` | Get general analytics of average delivery time |
| POST | `/v1/analytics/stocks` | Get analytics on stock balances |

---

## 接口详情


### POST `/v2/analytics/stock_on_warehouses`
**Stocks and products report**  
operationId: `AnalyticsAPI_AnalyticsGetStockOnWarehousesV2`  

<aside class="warning">
This method will be disabled. Switch to the <a href="#operation/AnalyticsAPI_AnalyticsStocks">/v1/analytics/stocks</a> method.
</aside>

Method for getting a report on leftover stocks and products movement at Ozon warehouses.

<aside class="warning">
Different from the report in the <b>Analytics → Reports → Report on stocks and products on the way to Ozon warehouses</b> section in your personal account.
</aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | integer | ✓ | Number of values per page. Default is 100. |
| `offset` | integer |  | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |
| `warehouse_type` | `AnalyticsGetStockOnWarehousesRequestWarehouseType` |  |  |

**响应 200**: Stocks and products report
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `analyticsStockOnWarehouseResponseResult` |  |  |
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

### POST `/v1/analytics/turnover/stocks`
**Product turnover**  
operationId: `AnalyticsAPI_StocksTurnover`  

Use the method to get the product turnover rate and the number of days the current stock will last.

 The method corresponds to the [**FBO → Residuals management**](https://seller.ozon.ru/app/supply/stocks-management) section in the personal account.
 You can make no more than 1 request per minute per `Client-Id` account.

If you request a list of products by `sku`, the `limit` and `offset` parameters are optional.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | integer |  | Number of values in the response.  |
| `offset` | integer |  | Number of elements to skip in the response.  For example, if `offset = 10`, the response starts with |
| `sku` | array[string] |  | Product identifiers in the Ozon system, SKU. |

**响应 200**: Turnover information
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | array[v1AnalyticsTurnoverStocksResponseItem] |  | Products. |
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

### POST `/v1/analytics/average-delivery-time`
**Get analytics of average delivery time**  
operationId: `AnalyticsAPI_AverageDeliveryTime`  

Method has the same functionality as **Analytics → Sales location → Average delivery time** tab in the seller's personal account. Get detailed analytics for each cluster using the [/v1/analytics/average-delivery-time/details](#operation/AnalyticsAPI_AverageDeliveryTimeDetails) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `delivery_schema` | `v1AverageDeliveryTimeRequestDeliverySchema` | ✓ |  |
| `sku` | array[string] |  | Product identifier in the Ozon system, SKU. |
| `supply_period` | `v1AverageDeliveryTimeRequestSupplyPeriod` | ✓ |  |

**响应 200**: Analytics of average delivery time
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `data` | array[v1AverageDeliveryTimeResponseData] |  | Cluster information. |
| `total` | `AverageDeliveryTimeResponseTotal` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/analytics/average-delivery-time/details`
**Get detailed analytics of average delivery time**  
operationId: `AnalyticsAPI_AverageDeliveryTimeDetails`  

Method has the same functionality as **Analytics → Sales location → Average delivery time** tab in the seller's personal account.

Get general analytics by cluster using the <a href="#operation/AnalyticsAPI_AverageDeliveryTime">/v1/analytics/average-delivery-time</a> method.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cluster_id` | integer | ✓ | Clusters identifier. |
| `filters` | `AverageDeliveryTimeDetailsRequestFilters` |  |  |
| `limit` | integer | ✓ | Number of elements in the response.  |
| `offset` | integer | ✓ | Number of elements that are skipped in the response.  For example, if `offset=10`, the response star |

**响应 200**: Detailed analytics
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `data` | array[v1AverageDeliveryTimeDetailsResponseData] |  | Cluster data. |
| `total_rows` | integer |  | Total number of rows. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/analytics/average-delivery-time/summary`
**Get general analytics of average delivery time**  
operationId: `AverageDeliveryTimeSummary`  

Method has the same functionality as **Analytics → Sales location → Average delivery time** tab in the seller's personal account.

Get detailed analytics for each cluster using the [/v1/analytics/average-delivery-time/details](#operation/AnalyticsAPI_AverageDeliveryTimeDetails) method.
To get analytics of average delivery time use the [/v1/analytics/average-delivery-time](#operation/AnalyticsAPI_AverageDeliveryTime) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: General analytics
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `average_delivery_time` | integer |  | Average delivery time to the customer. |
| `current_tariff` | `AverageDeliveryTimeSummaryResponseTariff` |  |  |
| `lost_profit` | number |  | Overpayment for FBO logistics. |
| `perfect_delivery_time` | integer |  | Recommended average delivery time to the customer. |
| `updated_at` | string |  | Date and time of the last data update. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/analytics/stocks`
**Get analytics on stock balances**  
operationId: `AnalyticsAPI_AnalyticsStocks`  

Use the method to get analytics on product stock balances. The method corresponds to the [**FBO → Stock management**](https://seller.ozon.ru/app/fbo-stocks/stocks-management/) section in your personal account. Analytics is updated twice a day: around 07:00 and 16:00 UTC. 

In the request, use only one of the parameters: `cluster_ids` or `macrolocal_cluster_ids`, otherwise an error is returned.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cluster_ids` | array[string] |  | Filter by cluster identifiers. To get identifiers, use the [/v1/cluster/list](#operation/SupplyDraft |
| `item_tags` | array[string] |  | Filter by product tags:       - `ITEM_ATTRIBUTE_NONE`: no tag; - `ECONOM`: economy product; - `NOVEL |
| `macrolocal_cluster_ids` | array[string] |  | Filter by macrolocal cluster identifiers. You can get cluster identifiers in the `macrolocal_cluster |
| `skus` | array[string] | ✓ | Filter by product identifiers in the Ozon system, SKU. |
| `turnover_grades` | array[string] |  | Filter by product liquidity status:       - `TURNOVER_GRADE_NONE`: product has no liquidity status.  |
| `warehouse_ids` | array[string] |  | Filter by warehouse identifiers. To get identifiers, use the [/v1/warehouse/list](#operation/Warehou |

**响应 200**: Analytics on stock balances
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | array[v1AnalyticsStocksResponseItem] |  | Product details. |
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