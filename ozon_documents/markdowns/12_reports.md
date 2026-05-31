# 报表 API

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/report/info` | Report details |
| POST | `/v1/report/list` | Reports list |
| POST | `/v1/report/products/create` | Products report |
| POST | `/v2/report/returns/create` | Report on returns |
| POST | `/v1/report/postings/create` | Shipment report |
| POST | `/v1/finance/cash-flow-statement/list` | Financial report |
| POST | `/v1/report/discounted/create` | Report on markdown products |
| POST | `/v1/report/warehouse/stock` | Report on FBS warehouse stocks |
| POST | `/v1/report/placement/by-products/create` | Get report on storage cost by products |
| POST | `/v1/report/placement/by-supplies/create` | Get report on storage cost by supplies |
| POST | `/v1/report/marked-products-sales/create` | Generate sales report of labeled products |
| POST | `/v2/invoice/create-or-update` | Create or edit an invoice |
| POST | `/v1/invoice/file/upload` | Invoice upload |
| POST | `/v2/invoice/get` | Get invoice information |
| POST | `/v1/invoice/delete` | Delete invoice link |

---

## 接口详情


### POST `/v1/report/info`
**Report details**  
operationId: `ReportAPI_ReportInfo`  

Returns information about a created report by its identifier.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string | ✓ | Unique report identifier. |

**响应 200**: Report details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `reportReportinfo` |  |  |
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

### POST `/v1/report/list`
**Reports list**  
operationId: `ReportAPI_ReportList`  

Returns the list of reports that have been generated before.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | integer | ✓ | Page number. |
| `page_size` | integer | ✓ | The number of values on the page:   - default value is 100,   - maximum value is 1000.  |
| `report_type` | `ReportListRequestReportType` |  |  |

**响应 200**: Reports list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `ReportListResponseResult` |  |  |
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

### POST `/v1/report/products/create`
**Products report**  
operationId: `ReportAPI_CreateCompanyProductsReport`  

Method for getting a report with products data. For example, Ozon ID, number of products, prices, status.
Matches the **Products and prices → Product list → Download → Products CSV** action in your personal account.

Explanation of some fields in the report:
  - __Ozon Product ID__—product identifier in the Ozon system. For example, if you sell product from the Ozon warehouse and from your own warehouse, the Ozon Product ID will be the same for them.
  - __FBO Ozon SKU ID__—identifier of the product that is sold from the Ozon warehouse.
  - __FBS Ozon SKU ID__—identifier of the product that is

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `language` | `reportLanguage` |  |  |
| `offer_id` | array[string] |  | Product identifier in the seller's system. |
| `search` | string |  | Search by record content, checks for availability. |
| `sku` | array[integer] |  | Product identifier in the Ozon system, SKU. |
| `visibility` | `reportCreateCompanyProductsReportRequestVisibility` |  |  |

**响应 200**: Products report
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `CreateReportResponseCode` |  |  |
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

### POST `/v2/report/returns/create`
**Report on returns**  
operationId: `ReportAPI_ReportReturnsCreate`  

Method for getting a report on FBO and FBS returns.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `v2ReportReturnsCreateRequestFilter` | ✓ | Filter. |
| `language` | `reportLanguage` |  |  |

**响应 200**: Report on FBO and FBS returns
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `CreateReportResponseCode` |  |  |
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

### POST `/v1/report/postings/create`
**Shipment report**  
operationId: `ReportAPI_CreateCompanyPostingsReport`  

Shipment report with orders details:
  - order statuses,
  - processing start date,
  - order numbers,
  - shipment numbers,
  - shipment costs,
  - shipments contents.
Matches the **FBO → Orders from Ozon warehouse** and **FBS → Orders from my warehouses → CSV** sections in your personal account.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `reportCreateCompanyPostingsReportRequestFilter` | ✓ |  |
| `language` | `reportLanguage` |  |  |
| `with` | `CreateCompanyPostingsReportRequestWith` |  |  |

**响应 200**: Shipment report
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `CreateReportResponseCode` |  |  |
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

### POST `/v1/finance/cash-flow-statement/list`
**Financial report**  
operationId: `FinanceAPI_FinanceCashFlowStatementList`  

Method for getting a financial report for the 1st to 15th day and the 16th to 31st day of the month.
Requesting a report for specific days is not an option.
Matches the **Finance → Payments** section in your seller account.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date` | `financev3Period` | ✓ |  |
| `page` | integer | ✓ | Number of the page returned in the request. |
| `with_details` | boolean |  | `true`, if you need to add additional parameters to the response. |
| `page_size` | integer | ✓ | Number of items on the page. |

**响应 200**: Financial report
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v3FinanceCashFlowStatementListResponseResult` |  |  |
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

### POST `/v1/report/discounted/create`
**Report on markdown products**  
operationId: `ReportAPI_CreateDiscountedReport`  

Generates a report on markdown products at Ozon warehouses.
For example, Ozon can markdown a product due to damage when delivering.

The method returns a report identifier.
To get the report, send the identifier in the request of the [/v1/report/info](#operation/ReportAPI_ReportInfo) method.

You can send 1 request per minute in one account.
Matches the **Analytics → Reports → Sales from Ozon warehouse → Marked down by Ozon** section in your personal account.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: Request result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string |  | Unique report identifier. To get a report, pass the value to the [/v1/report/info](#operation/Report |
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

### POST `/v1/report/warehouse/stock`
**Report on FBS warehouse stocks**  
operationId: `ReportAPI_CreateStockByWarehouseReport`  

Report with information about the number of available and reserved products in stock.
Matches the **FBS → Logistics management → Stock management → Download in XLS** action in your personal account. 

The method returns a report identifier.
To get the report, send the identifier in the request of the [/v1/report/info](#operation/ReportAPI_ReportInfo) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `language` | `reportLanguage` |  |  |
| `warehouseId` | string | ✓ | Warehouses identifiers. Limit of values in the request. Maximum is 50.  |

**响应 200**: Method result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `CreateReportResponseCode` |  |  |
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

### POST `/v1/report/placement/by-products/create`
**Get report on storage cost by products**  
operationId: `CreatePlacementByProductsReport`  

Corresponds to the **FBO → Storage cost** section in the personal account.

You can get the report no more than 5 times per day.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string | ✓ | Start date of the reporting period in the `YYYY-MM-DD` format. |
| `date_to` | string | ✓ | End date of the reporting period in the `YYYY-MM-DD` format.  The maximum period is 31 days.  |

**响应 200**: Report on storage cost
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string |  | Unique report identifier. To get a report, pass the value to the [/v1/report/info](#operation/Report |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/report/placement/by-supplies/create`
**Get report on storage cost by supplies**  
operationId: `CreatePlacementBySuppliesReport`  

Corresponds to the **FBO → Storage cost** section in the personal account.

You can get the report no more than 5 times per day.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string | ✓ | Start date of the reporting period in the `YYYY-MM-DD` format. |
| `date_to` | string | ✓ | End date of the reporting period in the `YYYY-MM-DD` format.  The maximum period is 31 days.  |

**响应 200**: Report on storage cost
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string |  | Unique report identifier. To get a report, pass the value to the [/v1/report/info](#operation/Report |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/report/marked-products-sales/create`
**Generate sales report of labeled products**  
operationId: `CreateCompanyMarkedProductsSalesReport`  

You can get no more than 50,000 labeling codes in one report. To get the remaining data, reduce the report generation period.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date` | `ReportMarkedProductsSalesCreateRequestDate` |  |  |

**响应 200**: Request result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `CreateReportResponseCode` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/invoice/create-or-update`
**Create or edit an invoice**  
operationId: `InvoiceAPI_InvoiceCreateOrUpdateV2`  

Create or edit an invoice for VAT refund to Turkey sellers.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date` | string | ✓ | Invoice date. |
| `hs_codes` | array[v2HsCode] |  | Product HS-codes. |
| `number` | string |  | Invoice number. The number can contain letters and digits, maximum length is 50 characters. |
| `posting_number` | string | ✓ | Shipment number. |
| `price` | number |  | Cost stated in the invoice. The fractional part is separated by decimal point, up to two digits afte |
| `price_currency` | string |  | Invoice currency: - `USD`—dollar,  - `EUR`—euro,  - `TRY`—Turkish lira,  - `CNY`—yuan,  - `RUB`—rubl |
| `url` | string | ✓ | Invoice link. Use the [v1/invoice/file/upload](#operation/invoice_upload) method to create a link. |

**响应 200**: Invoice has been created or changed
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | boolean |  | Method result. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/invoice/file/upload`
**Invoice upload**  
operationId: `invoice_upload`  

Available file types: JPEG and PDF. Maximum file size: 10 MB.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `base64_content` | string | ✓ | Base64 encoded invoice. |
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Link to invoice
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `url` | string |  | Link to invoice. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/invoice/get`
**Get invoice information**  
operationId: `invoice_getV2`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Invoice information
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `InvoiceGetV2ResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/invoice/delete`
**Delete invoice link**  
operationId: `invoice_delete`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |

**响应 200**: Link has been deleted
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | boolean |  | Method result. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---