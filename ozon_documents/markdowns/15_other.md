# 其他 API（数字商品、通知推送、Beta）

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

<br>
<aside class="warning">
Follow documentation updates in our <a href="https://t.me/OzonEnSellerAPI">Telegram channel</a>.
</aside>

## March 31, 2026

| Method                                                                                                                                                                                                                                             

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/posting/digital/codes/upload` | Upload digital product codes for shipping |
| POST | `/v1/posting/digital/list` | Get shipments list |
| POST | `/v1/product/digital/stocks/import` | Update quantity of digital products |
| POST | `/v1/analytics/manage/stocks` | Stock management |
| POST | `/v1/removal/from-supply/list` | Report on removal and disposal from FBO supply |
| POST | `/v1/removal/from-stock/list` | Report on removal and disposal from FBO stock |
| POST | `/v1/product/stairway-discount/by-quantity/set` | Manage quantity discounts |
| POST | `/v1/product/stairway-discount/by-quantity/get` | Get quantity discount information |
| POST | `/v1/finance/balance` | Get balance report |
| POST | `/v2/actions/discounts-task/list` | Get list of discount requests |
| POST | `/v2/cluster/list` | Get information about macrolocal clusters |
| POST | `/v1/description-category/tips` | Get tips to identify product category |
| POST | `/v1/product/quant/list` | Economy products list |
| POST | `/v1/product/quant/info` | Economy product information |

---

## 接口详情


### POST `/v1/posting/digital/codes/upload`
**Upload digital product codes for shipping**  
operationId: `UploadPostingCodes`  

Method is available only to sellers working with digital products. You can upload digital product codes within 24 hours of order confirmation.

Pass all digital product codes for each product in the order in a single request. If you don't pass all codes, the request returns an error.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `exemplars_by_sku` | array[UploadPostingCodesRequestPostingLineExemplarInfo] |  | Data on digital product codes by SKU. |
| `posting_number` | string |  | Shipment number. |

**响应 200**: Digital product codes uploaded
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `exemplars_by_sku` | array[UploadPostingCodesResponsePostingExemplarInfo] |  | Data on digital product codes by SKU. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/posting/digital/list`
**Get shipments list**  
operationId: `ListPostingCodes`  

Returns a list of shipments for which digital product codes need to be uploaded. Method is available only to sellers working with digital products.

To get a list of shipments in any status, use the [/v2/posting/fbo/list](#operation/PostingAPI_GetFboPostingList) method.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `dir` | `DirEnum` |  |  |
| `filter` | `ListPostingCodesRequestFilter` |  |  |
| `limit` | integer |  | Number of values in the response. Maximum is 1000, minimum is 1. |
| `offset` | integer |  | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |
| `with` | `ListPostingCodesRequestWithParams` |  |  |

**响应 200**: Shipments list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[ListPostingCodesResponsePosting] |  | Shipment list. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/digital/stocks/import`
**Update quantity of digital products**  
operationId: `DigitalProductAPI_StocksImport`  

Method is available only to sellers working with digital products. 

Allows you to change the product stock quantity.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `stocks` | array[StocksImportRequestItemStock] |  | Information about products in stock. |

**响应 200**: Product quantity updated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `status` | array[StocksImportResponseItemStatus] |  | Product details. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/analytics/manage/stocks`
**Stock management**  
operationId: `AnalyticsAPI_ManageStocks`  

<aside class="warning">
On January 22, 2026, the method will be disabled. Switch to the <a href="#operation/AnalyticsAPI_AnalyticsStocks">/v1/analytics/stocks</a> method.
</aside>

Use the method to find out how many product items are left in FBO stock.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1106-Razdel-upravleniia-ostatkami-analytics-manage-stocks) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `v1AnalyticsManageStocksRequestFilter` |  |  |
| `limit` | integer |  | Number of values in the response.  |
| `offset` | integer |  | Number of elements to skip in the response.  For example, if `offset = 10`, the response starts with |

**响应 200**: Stocks information
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | array[v1AnalyticsManageStocksResponseItem] |  | Products. |
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

### POST `/v1/removal/from-supply/list`
**Report on removal and disposal from FBO supply**  
operationId: `GetSupplyReturnsSummaryReport`  

Matches the [**FBO → Removal and disposal**](https://seller.ozon.ru/app/fbo-operations/returns) section in your personal account.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1608-Novye-metody-po-vyvozu-i-utilizatsii) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string | ✓ | Period start date in the `YYYY-MM-DD` format. |
| `date_to` | string | ✓ | Period end date in the `YYYY-MM-DD` format. |
| `last_id` | string |  | Identifier of the last value on the page. To get the next values, specify `last_id` from the respons |
| `limit` | integer | ✓ | Number of items in a response. |

**响应 200**: Report on removal and disposal from FBO stock
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `last_id` | string |  | Identifier of the last value on the page.. |
| `returns_summary_report_rows` | array[v1GetSupplyReturnsSummaryReportResponseRow] |  | Product details. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/removal/from-stock/list`
**Report on removal and disposal from FBO stock**  
operationId: `GetSupplierReturnsSummaryReport`  

Matches the [**FBO → Removal and disposal**](https://seller.ozon.ru/app/fbo-operations/returns) section in your personal account.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1608-Novye-metody-po-vyvozu-i-utilizatsii) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string | ✓ | Period start date in the `YYYY-MM-DD` format. |
| `date_to` | string | ✓ | Period end date in the `YYYY-MM-DD` format. |
| `last_id` | string |  | Identifier of the last value on the page. To get the next values, specify `last_id` from the respons |
| `limit` | integer | ✓ | Number of items in a response. |

**响应 200**: Report on removal and disposal from FBO stock
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `last_id` | string |  | Identifier of the last value on the page. |
| `returns_summary_report_rows` | array[v1GetSupplierReturnsSummaryReportResponseRow] |  | Product details. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/stairway-discount/by-quantity/set`
**Manage quantity discounts**  
operationId: `ProductAPI_SetProductStairwayDiscountByQuantity`  

Sets or removes a product discount based on its quantity in an order.
  
You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1719-Novye-metody-dlia-raboty-so-skidkoi-ot-kolichestva/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `stairways` | array[v1SetProductStairwayDiscountByQuantityRequestStairways] | ✓ | Information about the quantity discount for products. |
| `suppress_warnings` | boolean |  | Pass `true` to ignore warnings and set the discount.  |

**响应 200**: Discount settings updated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `accepted` | boolean |  | `true` if the request is accepted. Use the [/v1/product/stairway-discount/by-quantity/get](#operatio |
| `errors` | array[v1SetProductStairwayDiscountByQuantityResponseError] |  | Error description. |
| `warnings` | array[v1SetProductStairwayDiscountByQuantityResponseError] |  | Warning description. |
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

### POST `/v1/product/stairway-discount/by-quantity/get`
**Get quantity discount information**  
operationId: `ProductAPI_GetProductStairwayDiscountByQuantity`  

Returns information about a product discount based on its quantity in an order.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1719-Novye-metody-dlia-raboty-so-skidkoi-ot-kolichestva/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `skus` | array[string] | ✓ | Product identifiers in the Ozon system, SKU. |

**响应 200**: Information received
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `stairways` | array[v1GetProductStairwayDiscountByQuantityResponseStairways] |  | Information about the quantity discount for a specific product. |
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

### POST `/v1/finance/balance`
**Get balance report**  
operationId: `GetFinanceBalanceV1`  

Matches the **Finance → Balance** section in your seller account.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1732-Novyi-metod-polucheniia-dannykh-po-balansu/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string | ✓ | Start date of the reporting period in the `YYYY-MM-DD` format. |
| `date_to` | string | ✓ | End date of the reporting period in the `YYYY-MM-DD` format. The maximum period between `date_from`  |

**响应 200**: Balance report
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cashflows` | `GetFinanceBalanceV1ResponseCashflows` |  |  |
| `total` | `GetFinanceBalanceV1ResponseTotal` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/actions/discounts-task/list`
**Get list of discount requests**  
operationId: `GetDiscountTaskListV2`  

Method for getting a list of products that customers want to buy with a discount.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1856-Novye-metody-dlia-raboty-s-polucheniem-Spiska-zaiavok-na-skidku/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `last_id` | integer |  | Identifier of the last value on the page. Leave this field blank in the first request. |
| `limit` | integer |  | The maximum number of requests on a page. |
| `status` | `v2GetDiscountTaskListV2RequestDiscountTaskStatusEnum` |  |  |

**响应 200**: List of discount requests
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `tasks` | array[GetDiscountTaskListV2ResponseTask] |  | List of requests. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/cluster/list`
**Get information about macrolocal clusters**  
operationId: `DraftClusterList`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1873-Novyi-metod-polucheniia-makrolokalnykh-klasterov/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Macrolocal clusters
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v2DraftClusterListResponseResult] |  | Cluster list. |
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

### POST `/v1/description-category/tips`
**Get tips to identify product category**  
operationId: `DescriptionCategoryTips`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1963-Novyi-metod-dlia-raboty-s-polucheniem-podskazok-v-Dereve-kategorii-i-tipov-tovarov/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type_id` | array[string] |  | Product type identifier. You can get it using the [/v1/description-category/tree](#operation/Descrip |

**响应 200**: Tips
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[DescriptionCategoryTipsResponseResult] |  | List of tips. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/quant/list`
**Economy products list**  
operationId: `QuantProductList`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1084-Metody-po-tarifu-Ekonom) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `limit` | integer | ✓ | Maximum number of values in the response. |
| `visibility` | string |  | Filter by product visibility: - `ALL`: all products except archived ones; - `VISIBLE`: products visi |

**响应 200**: Economy products
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `products` | any |  | Economy products. |
| `total_items` | integer |  | Leftover stock in all warehouses. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/quant/info`
**Economy product information**  
operationId: `QuantGetInfo`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1084-Metody-po-tarifu-Ekonom) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `quant_code` | any | ✓ | List of MOQs with products.  |

**响应 200**: Economy product information
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | array[ProductV1QuantInfoResponseResultItems] |  | Economy products. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---