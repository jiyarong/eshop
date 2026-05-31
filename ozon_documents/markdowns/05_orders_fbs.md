# FBS 订单 API（卖家仓发货）

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v3/posting/fbs/unfulfilled/list` | List of unprocessed shipments |
| POST | `/v3/posting/fbs/list` | Shipments list |
| POST | `/v3/posting/fbs/get` | Get shipment details by identifier (version 3) |
| POST | `/v2/posting/fbs/get-by-barcode` | Get shipment data by barcode |
| POST | `/v3/posting/multiboxqty/set` | Specify number of boxes for multi-box shipments |
| POST | `/v2/posting/fbs/product/country/list` | List of manufacturing countries |
| POST | `/v2/posting/fbs/product/country/set` | Set the manufacturing country |
| POST | `/v1/posting/fbs/restrictions` | Get drop-off point restrictions |
| POST | `/v2/posting/fbs/package-label` | Print the labeling |
| POST | `/v1/posting/fbs/package-label/create` | Create a task to generate labeling |
| POST | `/v2/posting/fbs/package-label/create` | Create a task to generate a label |
| POST | `/v1/posting/fbs/package-label/get` | Get a labeling file |
| POST | `/v1/posting/fbs/cancel-reason` | Shipment cancellation reasons |
| POST | `/v2/posting/fbs/cancel-reason/list` | Shipments cancellation reasons |
| POST | `/v2/posting/fbs/product/cancel` | Cancel sending some products in the shipment |
| POST | `/v2/posting/fbs/cancel` | Cancel the shipment |
| POST | `/v2/posting/fbs/arbitration` | Open a dispute over a shipment |
| POST | `/v2/posting/fbs/awaiting-delivery` | Pass the shipment to shipping |
| POST | `/v1/posting/fbs/pick-up-code/verify` | Verify courier code |
| POST | `/v1/posting/global/etgb` | ETGB customs declarations |
| POST | `/v1/posting/unpaid-legal/product/list` | List of unpaid products from legal entities |
| POST | `/v4/posting/fbs/ship` | Pack the order (version 4) |
| POST | `/v4/posting/fbs/ship/package` | Shipment partial package (version 4) |
| POST | `/v6/fbs/posting/product/exemplar/set` | Check and save items data |
| POST | `/v6/fbs/posting/product/exemplar/create-or-get` | Get created items data |
| POST | `/v5/fbs/posting/product/exemplar/status` | Get statuses of product items check |
| POST | `/v5/fbs/posting/product/exemplar/validate` | Validate labeling codes |
| POST | `/v1/fbs/posting/product/exemplar/update` | Update items data |
| POST | `/v1/carriage/create` | Create shipping |
| POST | `/v1/carriage/approve` | Confirm shipping |
| POST | `/v1/carriage/set-postings` | Change shipping composition |
| POST | `/v1/carriage/cancel` | Delete shipping |
| POST | `/v1/carriage/delivery/list` | List of delivery methods and shipments |
| POST | `/v2/carriage/delivery/list` | List of delivery methods and shippings |
| POST | `/v2/posting/fbs/act/create` | Create an acceptance and transfer certificate and a waybill |
| POST | `/v1/posting/carriage-available/list` | List of available shippings |
| POST | `/v1/carriage/get` | Shipping details |
| POST | `/v1/posting/fbs/split` | Split the order into shipments without picking |
| POST | `/v2/posting/fbs/act/get-postings` | List of shipments in the certificate |
| POST | `/v2/posting/fbs/act/get-container-labels` | Package unit labels |
| POST | `/v2/posting/fbs/act/get-barcode` | Barcode for product shipping |
| POST | `/v2/posting/fbs/act/get-barcode/text` | Value of barcode for product shipping |
| POST | `/v2/posting/fbs/digital/act/check-status` | Generating status of digital acceptance and transfer certificate and waybill |
| POST | `/v2/posting/fbs/act/get-pdf` | Get acceptance and transfer certificate and waybill |
| POST | `/v2/posting/fbs/act/list` | List of shipping certificates |
| POST | `/v2/posting/fbs/digital/act/get-pdf` | Get digital shipping certificate |
| POST | `/v2/posting/fbs/act/check-status` | Status of acceptance and transfer certificate and waybill |
| POST | `/v1/posting/fbs/traceable/split` | Split shipment with traceable products |
| POST | `/v1/posting/fbs/product/traceable/attribute` | Get list of empty attributes for traceable products |
| POST | `/v1/carriage/ettn/status` | Get electronic waybill verification status for traceable FBS shipping |
| POST | `/v1/assembly/carriage/posting/list` | Get list of shipments in shipping |
| POST | `/v1/assembly/carriage/product/list` | Get list of products in shipping |
| POST | `/v1/assembly/fbs/posting/list` | Get shipment list |
| POST | `/v1/assembly/fbs/product/list` | Get list of products in shipments |
| POST | `/v2/fbs/posting/tracking-number/set` | Add tracking numbers |
| POST | `/v2/fbs/posting/delivering` | Change the status to "Delivering" |
| POST | `/v2/fbs/posting/last-mile` | Change the status to "Last Mile" |
| POST | `/v2/fbs/posting/delivered` | Change the status to "Delivered" |
| POST | `/v1/posting/fbs/timeslot/change-restrictions` | Dates available for delivery reschedule |
| POST | `/v1/posting/fbs/timeslot/set` | Reschedule shipment delivery date |
| POST | `/v1/posting/cutoff/set` | Specify shipping date |
| POST | `/v1/pass/list` | List of passes |
| POST | `/v1/carriage/pass/create` | Create a pass |
| POST | `/v1/carriage/pass/update` | Update pass |
| POST | `/v1/carriage/pass/delete` | Delete pass |
| POST | `/v1/return/pass/create` | Create a return pass |
| POST | `/v1/return/pass/update` | Update return pass |
| POST | `/v1/return/pass/delete` | Delete return pass |
| POST | `/v1/order/cancel` | Cancel order |
| POST | `/v1/order/cancel/check` | Check if order can be canceled |
| POST | `/v1/order/cancel/status` | Get order cancellation status |
| POST | `/v2/order/create` | Create order |
| POST | `/v1/cancel-reason/list` | Cancellation reasons for shipments |
| POST | `/v1/cancel-reason/list-by-order` | Order cancellation reasons |
| POST | `/v1/cancel-reason/list-by-posting` | Cancellation reasons for a shipment |

---

## 接口详情


### POST `/v3/posting/fbs/unfulfilled/list`
**List of unprocessed shipments**  
operationId: `PostingAPI_GetFbsPostingUnfulfilledList`  

Returns a list of unprocessed shipments for the specified time period: it shouldn't be longer than one year.

Possible statuses:
- `awaiting_registration`—awaiting registration,
- `acceptance_in_progress`—acceptance is in progress,
- `awaiting_approve`—awaiting approval,
- `awaiting_packaging`—awaiting packaging,
- `awaiting_deliver`—awaiting shipping,
- `arbitration`—arbitration,
- `client_arbitration`—customer delivery arbitration,
- `delivering`—delivery is in progress,
- `driver_pickup`—picked up by driver,
- `cancelled`—canceled,
- `not_accepted`—not accepted at the sorting center.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `dir` | string |  | Sorting direction:  - `asc`—ascending,  - `desc`—descending.  |
| `filter` | `postingv3GetFbsPostingUnfulfilledListRequestFilter` | ✓ |  |
| `limit` | integer | ✓ | Number of values in the response:  - maximum—1000,  - minimum—1.  |
| `offset` | integer | ✓ | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |
| `with` | `postingv3FbsPostingWithParams` |  |  |

**响应 200**: List of unprocessed shipments
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `postingv3GetFbsPostingUnfulfilledListResponseResult` |  |  |
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

### POST `/v3/posting/fbs/list`
**Shipments list**  
operationId: `PostingAPI_GetFbsPostingListV3`  

Returns a list of shipments for the specified time period: it shouldn't be longer than one year.

You can filter shipments by their status. The list of available statuses is specified in the description of the `filter.status` parameter.

The `true` value of the `has_next` parameter in the response means there is not the entire array of shipments in the response. To get information on the remaining shipments, make a new request with a different `offset` value.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `dir` | string |  | Sorting direction:  - `asc`—ascending,  - `desc`—descending.  |
| `filter` | `postingv3GetFbsPostingListRequestFilter` | ✓ |  |
| `limit` | integer | ✓ | Number of shipments in the response:   - maximum is 50,   - minimum is 1.  |
| `offset` | integer | ✓ | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |
| `with` | `postingv3FbsPostingWithParams` |  |  |

**响应 200**: Shipments list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v3GetFbsPostingListResponseV3Result` |  |  |
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

### POST `/v3/posting/fbs/get`
**Get shipment details by identifier (version 3)**  
operationId: `PostingAPI_GetFbsPostingV3`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment identifier. |
| `with` | `postingv3FbsPostingWithParamsExamplars` |  |  |

**响应 200**: Shipment details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v3FbsPostingDetail` |  |  |
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

### POST `/v2/posting/fbs/get-by-barcode`
**Get shipment data by barcode**  
operationId: `PostingAPI_GetFbsPostingByBarcode`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `barcode` | string | ✓ | Shipment barcode. You can get it in the `barcodes` array of the [/v3/posting/fbs/get](#operation/Pos |

**响应 200**: Shipment details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v2FbsPosting` |  |  |
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

### POST `/v3/posting/multiboxqty/set`
**Specify number of boxes for multi-box shipments**  
operationId: `PostingAPI_PostingMultiBoxQtySetV3`  

Method for passing the number of boxes for multi-box shipments when working under the rFBS Aggregator scheme (using the Ozon partner delivery).

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Multi-box shipment identifier. |
| `multi_box_qty` | integer | ✓ | Number of boxes in which the product is packed. |

**响应 200**: Number of boxes is specified
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `postingv3PostingMultiBoxQtySetV3ResponseResult` |  |  |
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

### POST `/v2/posting/fbs/product/country/list`
**List of manufacturing countries**  
operationId: `PostingAPI_ListCountryProductFbsPostingV2`  

Method for getting a list of available manufacturing countries and their ISO codes.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name_search` | string |  | Filtering by line. |

**响应 200**: List of manufacturing countries
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v2FbsPostingProductCountryListResponseResult] |  | List of manufacturing countries and their ISO codes. |
**响应 default**: An unexpected error response
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/posting/fbs/product/country/set`
**Set the manufacturing country**  
operationId: `PostingAPI_SetCountryProductFbsPostingV2`  

The method to set the manufacturing country to the product if it hasn't been specified.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment identifier. |
| `product_id` | integer | ✓ | Product identifier in the Ozon system, `product_id`. |
| `country_iso_code` | string | ✓ | Country ISO code from the [/v2/posting/fbs/product/country/list](#operation/PostingAPI_ListCountryPr |

**响应 200**: Manufacturing countries have been set
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `product_id` | integer |  | Product identifier in the Ozon system, `product_id`. |
| `is_gtd_needed` | boolean |  | Indication that you need to pass the сustoms cargo declaration (CCD) number for the product and ship |
**响应 default**: An unexpected error response
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/posting/fbs/restrictions`
**Get drop-off point restrictions**  
operationId: `PostingAPI_GetRestrictions`  

Method for getting dimensions, weight, and other restrictions of the drop-off point by the shipment number. The method is applicable only for the FBS scheme.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | The number of shipment for which you want to determine the restrictions. |

**响应 200**: Drop-off point restrictions
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1Restriction` |  |  |
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

### POST `/v2/posting/fbs/package-label`
**Print the labeling**  
operationId: `PostingAPI_PostingFBSPackageLabel`  

<aside class="warning">
If you work under the rFBS or rFBS Express scheme, learn more about printing labels in the <a href="https://docs.ozon.ru/global/en/fulfillment/rfbs/logistic-settings/order-packaging-requirements/">Seller knowledge base</a>.
</aside>

Generates a PDF file with a labeling for the specified shipments in the "Awaiting shipment" status: `awaiting_deliver`. You can pass a maximum of 20 identifiers in one request. If an error occurs for at least one shipment, the labeling isn't generated for all shipments in the request.

We recommend you to request labels 45–60 seconds after 

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | array[string] | ✓ | Shipment identifier. |

**响应 200**: Labeling printed
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file_content` | string |  | File content in binary format. |
| `file_name` | string |  | File name. |
| `content_type` | string |  | File type. |
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

### POST `/v1/posting/fbs/package-label/create`
**Create a task to generate labeling**  
operationId: `PostingAPI_CreateLabelBatch`  

<aside class="warning">
Method is deprecated and will be disabled. We'll give you one month's notice. Switch to the new version <a href="#operation/PostingAPI_CreateLabelBatchV2">/v2/posting/fbs/package-label/create</a>.
</aside>

Method for creating a task for asynchronous labeling generation.

To get labels created as a result of the method, 
use the [/v1/posting/fbs/package-label/get](#operation/PostingAPI_GetLabelBatch) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | any | ✓ | Numbers of shipments that need labeling. |

**响应 200**: Labeling generation task identifier
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1CreateLabelBatchResponseResult` |  |  |
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

### POST `/v2/posting/fbs/package-label/create`
**Create a task to generate a label**  
operationId: `PostingAPI_CreateLabelBatchV2`  

<aside class="warning">
If you work under the rFBS or rFBS Express scheme, learn more about printing labels in the <a href="https://docs.ozon.ru/global/en/fulfillment/rfbs/logistic-settings/order-packaging-requirements/">Seller knowledge base</a>.
</aside>

Method for creating a task for asynchronous label generation for shipments in the "Awaiting shipment" status: `awaiting_deliver`.
The method may return several tasks: to generate a small label and a regular label.

We recommend you to request labels 45–60 seconds after packing the shipments.

To get created labels, use the [/v1/posting/fbs/

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | any | ✓ | Numbers of shipments that need labeling. |

**响应 200**: Label generation tasks
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v2CreateLabelBatchResponseResult` |  |  |
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

### POST `/v1/posting/fbs/package-label/get`
**Get a labeling file**  
operationId: `PostingAPI_GetLabelBatch`  

Method for getting labeling after using the [/v1/posting/fbs/package-label/create](#operation/PostingAPI_CreateLabelBatch) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `task_id` | integer | ✓ | Task identifier for labeling generation from the [/v1/posting/fbs/package-label/create](#operation/P |

**响应 200**: Status of labeling generation or a labeling file
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1GetLabelBatchResponseResult` |  |  |
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

### POST `/v1/posting/fbs/cancel-reason`
**Shipment cancellation reasons**  
operationId: `PostingAPI_GetPostingFbsCancelReasonV1`  

Returns a list of cancellation reasons for particular shipments.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `related_posting_numbers` | array[string] | ✓ | Shipment numbers. |

**响应 200**: Shipment cancellation reasons
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[relatedPostingCancelReason] |  | Request result. |
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

### POST `/v2/posting/fbs/cancel-reason/list`
**Shipments cancellation reasons**  
operationId: `PostingAPI_GetPostingFbsCancelReasonList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Shipment cancellation reasons
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[postingCancelReason] |  | Method result. |
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

### POST `/v2/posting/fbs/product/cancel`
**Cancel sending some products in the shipment**  
operationId: `PostingAPI_CancelFbsPostingProduct`  

Use this method if you cannot send some of the products from the shipment.

To get the `cancel_reason_id` cancellation reason identifiers when working with the FBS or rFBS schemes, use the [/v2/posting/fbs/cancel-reason/list](#operation/PostingAPI_GetPostingFbsCancelReasonList) method.

You can't cancel presumably delivered orders.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cancel_reason_id` | integer | ✓ | Product shipping cancellation reason identifier. |
| `cancel_reason_message` | string | ✓ | Additional information on cancellation. Required parameter. |
| `items` | array[PostingProductCancelRequestItem] | ✓ | Products information. |
| `posting_number` | string | ✓ | Shipment identifier. |

**响应 200**: Shipping is canceled
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | string |  | Shipment number. |
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

### POST `/v2/posting/fbs/cancel`
**Cancel the shipment**  
operationId: `PostingAPI_CancelFbsPosting`  

Change shipment status to `cancelled`.

If you are using the rFBS scheme, you have the following cancellation reason identifiers (`cancel_reason_id`) available:

- `352`—product is out of stock;
- `400`—only defective products left;
- `401`—cancellation from arbitration;
- `402`—other reason;
- `665`—the customer didn't pick the order;
- `666`—delivery isn't available in the region;
- `667`—order was lost by the delivery service.

The last 4 reasons are available for shipments in the "Delivering" and "Courier on the way" statuses.

You can't cancel presumably delivered orders.

If `cancel_reas

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cancel_reason_id` | integer | ✓ | Shipment cancellation reason identifier. |
| `cancel_reason_message` | string |  | Additional information on cancellation. If `cancel_reason_id = 402`, the parameter is required. |
| `posting_number` | string | ✓ | Shipment identifier. |

**响应 200**: Shipment canceled
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | boolean |  | Request processing result. `true`, if the request was executed without errors. |
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

### POST `/v2/posting/fbs/arbitration`
**Open a dispute over a shipment**  
operationId: `PostingAPI_MoveFbsPostingToArbitration`  

If the shipment has been handed over for delivery, but has not been scanned at the sorting center, you can open a dispute. Opened dispute will put the shipment into the `arbitration` status.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | array[string] | ✓ | Shipment identifier. |

**响应 200**: A successful response
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | boolean |  | Request processing result. `true`, if the request was executed without errors. |
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

### POST `/v2/posting/fbs/awaiting-delivery`
**Pass the shipment to shipping**  
operationId: `PostingAPI_MoveFbsPostingToAwaitingDelivery`  

Transfers disputed orders to shipping. The shipment status will change to `awaiting_deliver`.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | array[string] | ✓ | Shipment identifier. The maximum number of values in one request is 100. |

**响应 200**: Shipment has been passed for shipping
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | boolean |  | Request processing result. `true`, if the request was executed without errors. |
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

### POST `/v1/posting/fbs/pick-up-code/verify`
**Verify courier code**  
operationId: `PostingAPI_PostingFBSPickupCodeVerify`  

Use this method to verify the courier code when handing over realFBS Express shipments. Learn more about handing shipments over in the [Seller Knowledge Base](https://seller-edu.ozon.ru/contract-for-sellers/regulations-fbs-realfbs/reglament-prodaji-so-svoego-sklada-fbs-express#7-порядок-передачи-отправлении-через-партнёров-ozon-при-экспресс-доставке).

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pickup_code` | string | ✓ | Courier code. |
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Verification result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `valid` | boolean |  | `true`, if the code is correct.  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/posting/global/etgb`
**ETGB customs declarations**  
operationId: `PostingAPI_GetEtgb`  

Method for getting Elektronik Ticaret Gümrük Beyannamesi (ETGB) customs declarations for sellers from Turkey.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date` | `GetEtgbRequestDate` | ✓ |  |

**响应 200**: Information about declarations
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[GetEtgbResponseResult] |  | Request result. |
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

### POST `/v1/posting/unpaid-legal/product/list`
**List of unpaid products from legal entities**  
operationId: `PostingAPI_UnpaidLegalProductList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `limit` | integer | ✓ | Number of values in the response.  |

**响应 200**: List of unpaid products
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `products` | array[v1PostingUnpaidLegalProductListResponseProducts] |  | Product list. |
| `cursor` | string |  | Cursor for the next data sample. |
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

### POST `/v4/posting/fbs/ship`
**Pack the order (version 4)**  
operationId: `PostingAPI_ShipFbsPostingV4`  

<aside class="warning">
Response with the <tt>200</tt> code doesn't guarantee that order is packaged successfully. Use the <a href="#operation/PostingAPI_GetFbsPostingV3">/v3/posting/fbs/get</a> method to check if order is packaged. If you get <tt>result.substatus = ship_failed</tt>, repeat order package.
</aside>

Divides the order into shipments and changes its status to `awaiting_deliver`.

Each element of the `packages` may contain several instances of the `products`. One instance of the `products` is one shipment.
Each element of the `products` is a product included into the shipment.

Di

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `packages` | any | ✓ | List of packages. Each package contains a list of shipments that the order was divided into. |
| `posting_number` | string | ✓ | Shipment number. |
| `with` | `FbsPostingShipV4RequestWith` |  |  |

**响应 200**: Method result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `additional_data` | any |  | Additional information about shipments. |
| `result` | any |  | Order packaging result. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v4/posting/fbs/ship/package`
**Shipment partial package (version 4)**  
operationId: `PostingAPI_ShipFbsPostingPackage`  

<aside class="warning">
Response with the <tt>200</tt> code doesn't guarantee that shipment is packaged successfully. Use the <a href="#operation/PostingAPI_GetFbsPostingV3">/v3/posting/fbs/get</a> method to check if shipment is packaged. If you get <tt>result.substatus = ship_failed</tt>, repeat shipment package.
</aside>
If you pass some of the shipped products through the request, the primary shipment will split into two parts.
The primary unassembled shipment will contain some of the products that weren't passed to the request.

Default status of created shipments is `awaiting_packaging`, 

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |
| `products` | array[v4FbsPostingShipPackageV4RequestProduct] |  | List of products in the shipment. |

**响应 200**: Method result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | string |  | Shipments numbers formed after packaging. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v6/fbs/posting/product/exemplar/set`
**Check and save items data**  
operationId: `PostingAPI_FbsPostingProductExemplarSetV6`  

Asynchronous method:

 - for checking the availability of product items in the “Chestny ZNAK” labeling system;
 - for saving product items data.

To get the checks results, use the [/v5/fbs/posting/product/exemplar/status](#operation/PostingAPI_FbsPostingProductExemplarStatusV5) method.
To get data about created items, use the [/v6/fbs/posting/product/exemplar/create-or-get](#operation/PostingAPI_FbsPostingProductExemplarCreateOrGetV6) method.

If you have multiple identical products in a shipment, specify one `product_id` and `exemplars` array for each product in the shipment.

Always pass a 

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `multi_box_qty` | integer |  | Quantity of boxes the product is packed in. |
| `posting_number` | string | ✓ | Shipment number. |
| `products` | array[FbsPostingProductExemplarSetV6RequestProducts] | ✓ | Product list. |

**响应 200**: Success
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v6/fbs/posting/product/exemplar/create-or-get`
**Get created items data**  
operationId: `PostingAPI_FbsPostingProductExemplarCreateOrGetV6`  

Method for getting data about product items from the shipment passed in the [/v6/fbs/posting/product/exemplar/set](#operation/PostingAPI_FbsPostingProductExemplarSetV6) method.

Use this method to get the `exemplar_id`.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Items data
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `multi_box_qty` | integer |  | Quantity of boxes the product is packed in. |
| `posting_number` | string |  | Shipment number. |
| `products` | array[FbsPostingProductExemplarCreateOrGetV6ResponseProduct] |  | Product list. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v5/fbs/posting/product/exemplar/status`
**Get statuses of product items check**  
operationId: `PostingAPI_FbsPostingProductExemplarStatusV5`  

Method for getting product items addition statuses that were passed in the [/v6/fbs/posting/product/exemplar/set](#operation/PostingAPI_FbsPostingProductExemplarSetV6) method. Also returns data on these product items.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Product items check statuses
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string |  | Shipment number. |
| `products` | array[v5FbsPostingProductExemplarStatusV5ResponseProduct] |  | Product list. |
| `status` | string |  | Verification status for product items and order packaging availability: - `ship_available`: order pa |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v5/fbs/posting/product/exemplar/validate`
**Validate labeling codes**  
operationId: `PostingAPI_FbsPostingProductExemplarValidateV5`  

Method for checking whether labeling codes meet the "Chestny ZNAK" system requirements on length and symbols and other labelings.

If you don't have the customs cargo declaration (CCD) number, you don't have to specify it.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |
| `products` | array[v5FbsPostingProductExemplarValidateV5RequestProduct] | ✓ | Product list. |

**响应 200**: Validation result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `products` | array[v5FbsPostingProductExemplarValidateV5ResponseProduct] |  | Product list. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbs/posting/product/exemplar/update`
**Update items data**  
operationId: `PostingAPI_FbsPostingProductExemplarUpdate`  

Use the method after passing item data using the [/v6/fbs/posting/product/exemplar/set](#operation/PostingAPI_FbsPostingProductExemplarSetV6) method to save updated item data for shipments in the “Awaiting shipment” status.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Data updated
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/carriage/create`
**Create shipping**  
operationId: `CarriageAPI_CarriageCreate`  

<aside class="warning">
If you're a seller outside Russia, please check the availability of the <a href="https://seller-edu.ozon.ru/fbs/ozon-logistika/sobrat-zakazy#шаг-2-сформируите-отгрузку">recommended shipping time</a> in your personal account.
If it's not available, create shipping using the <a href="#operation/PostingAPI_PostingFBSActCreate">/v2/posting/fbs/act/create</a> method.
You don't need to confirm shipping created using this method. Once the shipping is created, you can't edit its contents.
</aside>

Use the method to create the first FBS shipping. It includes all shipments in th

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `all_blr_traceable` | boolean |  | `true` if you have to create shipping with traceable products.  |
| `delivery_method_id` | integer |  | Delivery method identifier. |
| `departure_date` | string |  | Shipping date. The default value is current date. |

**响应 200**: Shipping details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `carriage_id` | integer |  | Shipping identifier. |
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

### POST `/v1/carriage/approve`
**Confirm shipping**  
operationId: `CarriageAPI_CarriageApprove`  

Use the method to confirm shipping after creation.
After confirmation, the shipping receives the `FORMED` status.

Once the shipping is confirmed, you can get the shipping list using the [/v2/posting/fbs/act/get-pdf](#operation/PostingAPI_PostingFBSGetAct) method and the shipping barcode using the [/v2/posting/fbs/act/get-barcode](#operation/PostingAPI_PostingFBSGetBarcode) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `carriage_id` | integer |  | Shipping identifier. |
| `containers_count` | integer |  | Number of package units.  Use this parameter if you have trusted acceptance enabled and ship orders  |

**响应 200**: Shipping confirmed
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

### POST `/v1/carriage/set-postings`
**Change shipping composition**  
operationId: `CarriageAPI_SetPostings`  

<aside class="warning">
The method isn't available for sellers from CIS.

Overwrites the list of orders in shipping. Pass only orders in the <code>awaiting_deliver</code> status and ones which are ready for shipping.       
</aside>

<br>

<aside class="notice">
To return to the list of orders, delete the shipping using <a href="#operation/CarriageAPI_CarriageCancel">/v1/carriage/cancel</a> and create a new one.
</aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `carriage_id` | integer | ✓ | Shipping identifier. |
| `posting_numbers` | array[string] | ✓ | Current list of shipments. |

**响应 200**: Shipment information
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | any |  |  |
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

### POST `/v1/carriage/cancel`
**Delete shipping**  
operationId: `CarriageAPI_CarriageCancel`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `carriage_id` | integer | ✓ | Shipping identifier. |

**响应 200**: Shipment information
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | string |  | Error message. |
| `carriage_status` | string |  | Shipping status. |
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

### POST `/v1/carriage/delivery/list`
**List of delivery methods and shipments**  
operationId: `CarriageAPI_CarriageDeliveryList`  

<aside class="warning">
  Method doesn't return information for delivery methods that don't have shipments.
</aside>

Use the method to get a list of created shipments for a delivery method and their statuses.  

<aside class="warning">
  On March 20, 2026 we disable the method. Switch to the new version <a href="#operation/CarriageDeliveryListV2">/v2/carriage/delivery/list</a>.
</aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `delivery_method_id` | integer |  | Delivery method identifier. |
| `departure_date` | string |  | Shipping date. The default value is current date. |

**响应 200**: List of methods and shipments
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v1CarriageDeliveryListResponseResult] |  |  |
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

### POST `/v2/carriage/delivery/list`
**List of delivery methods and shippings**  
operationId: `CarriageDeliveryListV2`  

<aside class="warning">
  Doesn't return information about delivery methods that don't have shipments.
</aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `filter` | `CarriageDeliveryListV2RequestFilter` |  |  |
| `limit` | integer | ✓ | Number of values per page. |

**响应 200**: List of methods and shippings
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `has_next` | boolean |  | `true` if not all delivery methods are returned in the response.  |
| `methods` | array[CarriageDeliveryListV2ResponseDeliveryMethod] |  | List of delivery methods. |
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

### POST `/v2/posting/fbs/act/create`
**Create an acceptance and transfer certificate and a waybill**  
operationId: `PostingAPI_PostingFBSActCreate`  

Launches the procedure for generating the transfer documents: acceptance and transfer certificate and the waybill.

To generate and receive transfer documents, transfer the shipment to the `awaiting_deliver` status.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `containers_count` | integer |  | Number of package units.   Use this parameter  if you have trusted acceptance enabled and ship order |
| `delivery_method_id` | integer | ✓ | Delivery method identifier. For realFBS warehouses, get it using the [/v2/delivery-method/list](#ope |
| `departure_date` | string |  | Shipping date.  To make documents printing available before the shipping day, enable **Printing the  |

**响应 200**: A successful response
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `PostingFBSActCreateResponseAct` |  |  |
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

### POST `/v1/posting/carriage-available/list`
**List of available shippings**  
operationId: `PostingAPI_GetCarriageAvailableList`  

<aside class="warning">
On March 20, 2026 we disable the method. Switch to the new version <a href="#operation/CarriageDeliveryListV2">/v2/carriage/delivery/list</a>.
</aside>

Method for getting shipments that require printing acceptance and transfer certificates and a waybill.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `delivery_method_id` | integer | ✓ | Filter by delivery method identifier. You can get it using the [/v1/delivery-method/list](#operation |
| `departure_date` | string |  | Shipping date. The default value is current date. |

**响应 200**: Shipping list
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

### POST `/v1/carriage/get`
**Shipping details**  
operationId: `CarriageGet`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `carriage_id` | integer | ✓ | Shipping identifier. |

**响应 200**: Shipping information
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `act_type` | string |  | Acceptance certificate type for FBS sellers. |
| `all_blr_traceable` | boolean |  | `true` if shipping contains traceable products.  |
| `is_waybill_enabled` | boolean |  | `true` if it's possible to print the waybill.  |
| `is_econom` | boolean |  | `true` if the shipping contains Super Economy products.  |
| `arrival_pass_ids` | array[string] |  | Pass identifiers for the shipping. |
| `available_actions` | array[string] |  | Available actions with the shipping: - `get_shipping_list`: get the shipping list; - `get_act_of_acc |
| `cancel_availability` | `carriageCarriageGetResponseCancelAvailability` |  |  |
| `carriage_id` | integer |  | Shipping identifier. |
| `company_id` | integer |  | Company identifier. |
| `containers_count` | integer |  | Number of package units. |
| `created_at` | string |  | Date and time of shipping creation. |
| `delivery_method_id` | integer |  | Delivery method identifier. |
| `departure_date` | string |  | Shipping date. |
| `first_mile_type` | string |  | First mile type. |
| `has_postings_for_next_carriage` | boolean |  | `true` if there are shipments subject to shipping that are not in the current shipping.  |
| `integration_type` | string |  | Delivery service integration type. |
| `is_container_label_printed` | boolean |  | `true` if you already printed shipping labels.  |
| `is_partial` | boolean |  | `true` if the shipping is partial.  |
| `partial_num` | integer |  | Serial number of the partial shipping. |
| `retry_count` | integer |  | The number of retries to create shipping. |
| `status` | string |  | Shipping status: - `received`: acceptance in progress; - `closed`: closed after acceptance; - `sende |
| `tpl_provider_id` | integer |  | Delivery method identifier. |
| `updated_at` | string |  | Date and time when the shipping was last updated. |
| `warehouse_id` | integer |  | Warehouse identifier. |
**响应 default**: Request error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/posting/fbs/split`
**Split the order into shipments without picking**  
operationId: `FbsSplit`  

**响应 200**: Order was split
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `parent_posting` | `v1PostingFbsSplitResponsePostingParent` |  |  |
| `postings` | array[v1PostingFbsSplitResponsePosting] |  | List of shipments the order is split into. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/posting/fbs/act/get-postings`
**List of shipments in the certificate**  
operationId: `PostingAPI_ActPostingList`  

Returns a list of shipments in the certificate by certificate identifier.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int | ✓ | Certificate identifier. You can get it using the [/v2/posting/fbs/act/list](#operation/PostingAPI_Fb |

**响应 200**: List of shipments
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v2PostingFBSActGetPostingsResult] |  | Information about shipments. |
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

### POST `/v2/posting/fbs/act/get-container-labels`
**Package unit labels**  
operationId: `PostingAPI_PostingFBSActGetContainerLabels`  

Method creates package unit labels.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | integer | ✓ | Document generation task number (shipping identifier) received from the [POST /v2/posting/fbs/act/cr |

**响应 200**: Package unit labels
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file_content` | string |  | File content in binary format. |
| `file_name` | string |  | File name. |
| `content_type` | string |  | File type. |
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

### POST `/v2/posting/fbs/act/get-barcode`
**Barcode for product shipping**  
operationId: `PostingAPI_PostingFBSGetBarcode`  

Method for getting a barcode to show at a pick-up point or sorting center during shipping.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | integer | ✓ | Shipping identifier. |

**响应 200**: Shipment barcode
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file_content` | string |  | Barcode image in binary format. |
| `file_name` | string |  | File name. |
| `content_type` | string |  | File type. |
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

### POST `/v2/posting/fbs/act/get-barcode/text`
**Value of barcode for product shipping**  
operationId: `PostingAPI_PostingFBSGetBarcodeText`  

Use this method to get the barcode
from the [/v2/posting/fbs/act/get-barcode](#operation/PostingAPI_PostingFBSGetBarcode) response in text format.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | integer | ✓ | Shipping identifier. |

**响应 200**: Barcode value
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | string |  | Barcode in text format. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/posting/fbs/digital/act/check-status`
**Generating status of digital acceptance and transfer certificate and waybill**  
operationId: `PostingAPI_PostingFBSDigitalActCheckStatus`  

<aside class="warning">
The method is deprecated and will be disabled on March 22, 2026. Switch to the <a href="#operation/PostingAPI_PostingFBSActCheckStatus">/v2/posting/fbs/act/check-status</a> method.

The method is available only for sellers who are connected to electronic document circulation.
</aside>

Get current status of generating digital acceptance and transfer certificate and waybill.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | integer | ✓ | Document generation task number (shipping identifier) received from the [POST /v2/posting/fbs/act/cr |

**响应 200**: Generating status of digital acceptance and transfer certificate and waybill
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | integer |  | Number of document generation task. |
| `status` | string |  | Documents generation status: - `FORMING`—in process, - `FORMED`—generated successfully, - `CONFIRMED |
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

### POST `/v2/posting/fbs/act/get-pdf`
**Get acceptance and transfer certificate and waybill**  
operationId: `PostingAPI_PostingFBSGetAct`  

Get the generated transfer documents in PDF format: an acceptance and transfer certificate and a waybill.

If you are not connected to electronic document circulation (EDC), the method returns an acceptance and transfer certificate and a waybill.

If you are connected to EDC, the method returns a waybill only.

Get the list of available documents for the shipping in the `available_actions` parameter of the [/v1/carriage/get](#operation/CarriageGet) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | integer | ✓ | Number of the document generation task (shipping identifier) received in the [/v2/posting/fbs/act/cr |

**响应 200**: An acceptance and transfer certificate and a waybill
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file_content` | string |  | File content in binary format. |
| `file_name` | string |  | File name. |
| `content_type` | string |  | File type. |
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

### POST `/v2/posting/fbs/act/list`
**List of shipping certificates**  
operationId: `PostingAPI_FbsActList`  

Returns a list of shipping certificates allowing to filter them by time period, status, and integration type.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `v2PostingFBSActListFilter` |  |  |
| `limit` | integer | ✓ | Maximum number of certificates in the response. |

**响应 200**: List of certificates
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v2PostingFBSActListResult] |  | Request result. |
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

### POST `/v2/posting/fbs/digital/act/get-pdf`
**Get digital shipping certificate**  
operationId: `PostingAPI_PostingFBSGetDigitalAct`  

<br>
<aside class="warning">
The method is deprecated and will be disabled on March 22, 2026. Switch to the <a href="#operation/PostingAPI_PostingFBSGetAct">/v2/posting/fbs/act/get-pdf</a> method.
The method is available only for sellers who are connected to electronic document circulation.
</aside>

You can get digital documents, if the [/v2/posting/fbs/digital/act/check-status](#operation/PostingAPI_PostingFBSDigitalActCheckStatus) method returned one of the following statuses:
- `FORMED`: generated successfully;
- `CONFIRMED`: signed by Ozon;
- `CONFIRMED_WITH_MISMATCH`: signed by Ozon with

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | integer | ✓ | Document generation task number (shipping identifier) received from the [POST /v2/posting/fbs/act/cr |
| `doc_type` | string |  | Type of shipment certificate: - `act_of_acceptance`: acceptance certificate, - `act_of_mismatch`: di |

**响应 200**: Digital shipping certificate
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file_content` | string |  | File content in binary format. |
| `file_name` | string |  | File name. |
| `content_type` | string |  | File type. |
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

### POST `/v2/posting/fbs/act/check-status`
**Status of acceptance and transfer certificate and waybill**  
operationId: `PostingAPI_PostingFBSActCheckStatus`  

If you are not connected to electronic document circulation (EDC), the method returns status of generating an acceptance and transfer certificate and a waybill.

If you are connected to EDC, the method returns status of generating a waybill only.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | integer | ✓ | Document generation task number (shipping identifier) received from the [POST /v2/posting/fbs/act/cr |

**响应 200**: Status of acceptance and transfer certificate and waybill
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `PostingFBSActCheckStatusResponseStatus` |  |  |
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

### POST `/v1/posting/fbs/traceable/split`
**Split shipment with traceable products**  
operationId: `PostingFbsTraceableSplit`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Order split
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `postings` | array[v1PostingFbsTraceableSplitResponsePosting] |  | Shipment details. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/posting/fbs/product/traceable/attribute`
**Get list of empty attributes for traceable products**  
operationId: `PostingFbsProductTraceableAttribute`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: List of empty attributes
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `products` | array[v1PostingFbsProductTraceableAttributeResponseProduct] |  | List of products in the shipment. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/carriage/ettn/status`
**Get electronic waybill verification status for traceable FBS shipping**  
operationId: `CarriageEttnStatus`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `carriage_id` | integer | ✓ | Shipping identifier. |

**响应 200**: Electronic waybill verification status
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `errors` | array[string] |  | Errors in checking the electronic waybill of traceable shipping. |
| `status` | string |  | Status of electronic waybill of traceable shipping. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/assembly/carriage/posting/list`
**Get list of shipments in shipping**  
operationId: `AssemblyCarriagePostingList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `filter` | `v1AssemblyCarriagePostingListRequestFilter` | ✓ |  |
| `limit` | integer | ✓ | Number of values per page. |

**响应 200**: Shipment list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `can_print_mass_label` | boolean |  | `true` if you can print labels in bulky.  |
| `cursor` | string |  | Cursor for the next data sample. If the parameter is empty, there is no more data. |
| `postings` | array[v1AssemblyCarriagePostingListResponsePosting] |  | Shipment list. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/assembly/carriage/product/list`
**Get list of products in shipping**  
operationId: `AssemblyCarriageProductList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `filter` | `v1AssemblyCarriageProductListRequestFilter` | ✓ |  |
| `limit` | integer | ✓ | Number of values per page. |

**响应 200**: Products list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. If the parameter is empty, there is no more data. |
| `products` | array[v1AssemblyCarriageProductListResponseProduct] |  | Product list. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/assembly/fbs/posting/list`
**Get shipment list**  
operationId: `AssemblyFbsPostingList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `filter` | `v1AssemblyFbsPostingListRequestFilter` | ✓ |  |
| `limit` | integer | ✓ | Number of values per page. |
| `sort_dir` | `v1AssemblyFbsPostingListRequestSortDirEnum` | ✓ |  |

**响应 200**: Shipments list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. If the parameter is empty, there is no more data. |
| `cutoff` | string |  | Time before an order must be packed. |
| `postings` | array[v1AssemblyFbsPostingListResponsePosting] |  | Shipment list. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/assembly/fbs/product/list`
**Get list of products in shipments**  
operationId: `AssemblyFbsProductList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `v1AssemblyFbsProductListRequestFilter` | ✓ |  |
| `limit` | integer | ✓ | Number of values per page. |
| `offset` | integer |  | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |
| `sort_dir` | `v1AssemblyFbsProductListRequestSortDirEnum` |  |  |

**响应 200**: List of products in shipments
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `has_next` | boolean |  | Indicates that the response returned not all products:  - `true`: make a new request with a differen |
| `products` | array[AssemblyFbsProductListResponseProducts] |  | Product list. |
| `products_count` | integer |  | Number of products. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/fbs/posting/tracking-number/set`
**Add tracking numbers**  
operationId: `PostingAPI_FbsPostingTrackingNumberSet`  

Add tracking numbers to shipments. You can add up to 20 tracking numbers at a time.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `tracking_numbers` | array[FbsPostingTrackingNumberSetRequestTrackingNumber] | ✓ | An array with shipment identifier—tracking number pairs. |

**响应 200**: Tracking number added
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[FbsPostingMoveStatusResponseMoveStatus] |  | Method result. |
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

### POST `/v2/fbs/posting/delivering`
**Change the status to "Delivering"**  
operationId: `PostingAPI_FbsPostingDelivering`  

<aside class="warning">Before changing the status, check the current shipment status using the <a href="#operation/PostingAPI_GetFbsPostingV3">/v3/posting/fbs/get</a> method. The status change is asynchronous.</aside>

Changes the shipment status to "Delivering" if a third-party delivery service is being used.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | array[string] | ✓ | Shipment identifier. |

**响应 200**: Status changed
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[FbsPostingMoveStatusResponseMoveStatus] |  | Method result. |
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

### POST `/v2/fbs/posting/last-mile`
**Change the status to "Last Mile"**  
operationId: `PostingAPI_FbsPostingLastMile`  

<aside class="warning">Before changing the status, check the current shipment status using the <a href="#operation/PostingAPI_GetFbsPostingV3">/v3/posting/fbs/get</a> method. The status change is asynchronous.</aside>

Changes the shipment status to "Last mile" if a third-party delivery service is being used.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | array[string] | ✓ | Shipment identifier. |

**响应 200**: Status changed
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[FbsPostingMoveStatusResponseMoveStatus] |  | Method result. |
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

### POST `/v2/fbs/posting/delivered`
**Change the status to "Delivered"**  
operationId: `PostingAPI_FbsPostingDelivered`  

<aside class="warning">Before changing the status, check the current shipment status using the <a href="#operation/PostingAPI_GetFbsPostingV3">/v3/posting/fbs/get</a> method. The status change is asynchronous.</aside>

Changes the shipment status to "Delivered" if a third-party delivery service is being used.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | array[string] | ✓ | Shipment identifier. |

**响应 200**: Status changed
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[FbsPostingMoveStatusResponseMoveStatus] |  | Method result. |
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

### POST `/v1/posting/fbs/timeslot/change-restrictions`
**Dates available for delivery reschedule**  
operationId: `PostingAPI_PostingTimeslotChangeRestrictions`  

Method for getting the dates and number of times available for delivery reschedule.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Available dates and number
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `delivery_interval` | `v1PostingFbsTimeslotChangeRestrictionsDeliveryInterval` |  |  |
| `remaining_changes_count` | integer |  | Number of delivery date reschedules left. |
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

### POST `/v1/posting/fbs/timeslot/set`
**Reschedule shipment delivery date**  
operationId: `PostingAPI_SetPostingTimeslot`  

You can change the delivery date of a shipment up to two times.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `new_timeslot` | `v1PostingFbsTimeslotSetNewTimeslot` | ✓ |  |
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Request result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | boolean |  | `true`, if the date was changed.  |
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

### POST `/v1/posting/cutoff/set`
**Specify shipping date**  
operationId: `PostingAPI_SetPostingCutoff`  

Method for shipments delivered by the seller or a non-integrated shipping provider.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `new_cutoff_date` | string | ✓ | New shipping date. |
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Date specification result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | boolean |  | `true` if the new date is set.  |
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

### POST `/v1/pass/list`
**List of passes**  
operationId: `PassList`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `filter` | `ArrivalPassListRequestFilter` |  |  |
| `limit` | integer | ✓ | Limit on number of entries in a reply. Default value is 1000. Maximum value is 1000.  |

**响应 200**: List of passes
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `arrival_passes` | array[arrivalpassArrivalPassListResponseArrivalPass] |  | List of passes. |
| `cursor` | string |  | Cursor for the next data sample. If the parameter is empty, there is no more data.  |
**响应 default**: Request error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/carriage/pass/create`
**Create a pass**  
operationId: `carriagePassCreate`  

The identifier of the created pass will be added to the shipment.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `arrival_passes` | array[sellerSellerAPIArrivalPassCreateRequestArrivalPass] | ✓ | List of passes. |
| `carriage_id` | integer | ✓ | Shipping identifier. |

**响应 200**: Pass created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `arrival_pass_ids` | array[string] |  | Pass identifiers. |
**响应 default**: Request error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/carriage/pass/update`
**Update pass**  
operationId: `carriagePassUpdate`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `arrival_passes` | array[sellerSellerAPIArrivalPassUpdateRequestArrivalPass] | ✓ | List of passes. |
| `carriage_id` | integer | ✓ | Shipping identifier. |

**响应 200**: Pass updated
**响应 default**: Request error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/carriage/pass/delete`
**Delete pass**  
operationId: `carriagePassDelete`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `arrival_pass_ids` | array[string] | ✓ | Pass identifiers. |
| `carriage_id` | integer | ✓ | Shipping identifier. |

**响应 200**: Pass deleted
**响应 default**: Request error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/return/pass/create`
**Create a return pass**  
operationId: `returnPassCreate`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `arrival_passes` | array[arrivalpassArrivalPassCreateRequestArrivalPass] | ✓ | Array of passes. |

**响应 200**: Pass created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `arrival_pass_ids` | array[string] |  | Pass identifiers. |
**响应 default**: Request error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/return/pass/update`
**Update return pass**  
operationId: `returnPassUpdate`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `arrival_passes` | array[arrivalpassArrivalPassUpdateRequestArrivalPass] | ✓ | Array of passes. |

**响应 200**: Pass updated
**响应 default**: Request error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/return/pass/delete`
**Delete return pass**  
operationId: `returnPassDelete`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `arrival_pass_ids` | array[string] | ✓ | Pass identifiers. |

**响应 200**: Pass deleted
**响应 default**: Request error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/order/cancel`
**Cancel order**  
operationId: `OrderAPI_OrderCancel`  

Cancels an order with all shipments. Use the cancellation reason identifier `reasons.id` from the [/v1/cancel-reason/list-by-order](#operation/CancelReasonListByOrder) method.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `order_number` | string | ✓ | Order number. |
| `reason_id` | integer | ✓ | Order cancellation reason identifier. |
| `reason_message` | string |  | Order cancellation reason. |

**响应 200**: Order canceled
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `message` | string |  | Cancellation processing status. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/order/cancel/check`
**Check if order can be canceled**  
operationId: `OrderAPI_OrderCancelCheck`  

Returns possibility for a customer to cancel an order.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `order_number` | string | ✓ | Order number. |

**响应 200**: Result of check
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cancellable` | boolean |  | `true` if order can be canceled.  |
| `order_number` | string |  | Order number. |
| `posting_groups` | array[OrderCancelCheckResponsePostingGroup] |  | Shipment groups. |
| `postings` | array[OrderCancelCheckResponsePosting] |  | Cancellation availability details. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/order/cancel/status`
**Get order cancellation status**  
operationId: `OrderAPI_OrderCancelStatus`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `order_number` | string | ✓ | Order number. |

**响应 200**: Order cancellation status
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `order_number` | string |  | Order number. |
| `posting_number` | array[string] |  | List of shipments in order. |
| `state` | string |  | Order cancellation status. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/order/create`
**Create order**  
operationId: `OrderAPI_OrderCreate`  

Creates an order for a customer and recipient in the Ozon system. Pass the delivery option from the [/v2/delivery/checkout](#operation/DeliveryCheckout) method response.

The response may include not all shipments. Get the list of all shipments by the `order_number` parameter using the methods:

  - [/v2/posting/fbo/list](#operation/PostingAPI_GetFboPostingList): for the FBO scheme;
  - [/v3/posting/fbs/list](#operation/PostingAPI_GetFbsPostingListV3): for the FBS scheme.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `buyer` | `OrderCreateRequestBuyer` | ✓ |  |
| `delivery` | `OrderCreateRequestDelivery` | ✓ |  |
| `delivery_schema` | `OrderCreateRequestV2DeliverySchemaEnum` | ✓ |  |
| `recipient` | `OrderCreateRequestRecipient` | ✓ |  |
| `splits` | array[OrderCreateRequestSplit] | ✓ | Details on shipments in order. |

**响应 200**: Order created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `order_number` | string |  | Order number. |
| `postings` | array[string] |  | Shipments. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/cancel-reason/list`
**Cancellation reasons for shipments**  
operationId: `CancelReasonList`  

Returns possible cancellation reasons for shipments and orders.

**响应 200**: Cancellation reasons for all shipments
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `reasons` | array[v1CancelReasonListByOrderResponseReason] |  | Information about cancellation reasons. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/cancel-reason/list-by-order`
**Order cancellation reasons**  
operationId: `CancelReasonListByOrder`  

Returns possible cancellation reasons for orders.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `order_number` | string | ✓ | Order number. |

**响应 200**: Order cancellation reasons
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `reasons` | array[v1CancelReasonListByOrderResponseReason] |  | Information about cancellation reasons. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/cancel-reason/list-by-posting`
**Cancellation reasons for a shipment**  
operationId: `CancelReasonAPI_CancelReasonListByPosting`  

Returns possible cancellation reasons for shipments.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Cancellation reasons for a shipment
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `reasons` | array[v1CancelReasonListByPostingResponseReason] |  | Information about cancellation reasons. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---