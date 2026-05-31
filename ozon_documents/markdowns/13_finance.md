# 财务 API

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

More methods in the [**Premium Methods**](#tag/Premium) section.

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v2/finance/realization` | Sales report (version 2) |
| POST | `/v1/finance/realization/posting` | Sales report by order |
| POST | `/v3/finance/transaction/list` | Transactions list |
| POST | `/v3/finance/transaction/totals` | Total transactions sum |
| POST | `/v1/finance/document-b2b-sales` | Legal entities sales register |
| POST | `/v1/finance/document-b2b-sales/json` | Legal entities sales register in JSON format |
| POST | `/v1/finance/mutual-settlement` | Mutual settlements report |
| POST | `/v1/finance/products/buyout` | Purchased product report |
| POST | `/v1/finance/compensation` | Compensation report |
| POST | `/v1/finance/decompensation` | Decompensation report |
| POST | `/v1/receipts/get` | Get receipt in PDF format |
| POST | `/v1/receipts/seller/list` | Get list of seller receipts |
| POST | `/v1/receipts/upload` | Upload receipt |

---

## 接口详情


### POST `/v2/finance/realization`
**Sales report (version 2)**  
operationId: `FinanceAPI_GetRealizationReportV2`  

Returns information on products sold and returned within a month. Canceled or non-purchased products are not included.
Matches the **Finance → Documents → Sales reports → Product sales report** section in your personal account.

Report is returned no later than the 5th day of the next month.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `month` | integer | ✓ | Month. |
| `year` | integer | ✓ | Year. |

**响应 200**: Report
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `GetRealizationReportResponseV2Result` |  |  |
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

### POST `/v1/finance/realization/posting`
**Sales report by order**  
operationId: `FinanceAPI_GetRealizationReportV1`  

Returns a report on delivered and returned products with details by order. Canceled or non-purchased products aren't included. Report is available from the current date until August, 2023 inclusive.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `month` | integer | ✓ | Month. |
| `year` | integer | ✓ | Year. |

**响应 200**: Sales report by order
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `header` | `GetRealizationReportResponseV2Header` |  |  |
| `rows` | array[v1GetRealizationReportPostingResponseRow] |  | Report table. |
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

### POST `/v3/finance/transaction/list`
**Transactions list**  
operationId: `FinanceAPI_FinanceTransactionListV3`  

<aside class="warning">
Use the method with sequential sending of requests.<br>
The data may not match the information in your personal account.
</aside>

Returns detailed information on all accruals. The maximum period for which you can get information in one request is 1 month.

If you don't specify the `posting_number` in request, the response contains all shipments for the specified period or shipments of a certain type.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `FinanceTransactionListV3RequestFilter` |  |  |
| `page` | integer | ✓ | Number of the page returned in the request. |
| `page_size` | integer | ✓ | Number of items on the page. |

**响应 200**: Transactions list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `financev3FinanceTransactionListV3ResponseResult` |  |  |
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

### POST `/v3/finance/transaction/totals`
**Total transactions sum**  
operationId: `FinanceAPI_FinanceTransactionTotalV3`  

<aside class="warning">
The data may not match the information in your personal account.
</aside>

Returns the transaction totals for the specified period.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date` | `FinanceTransactionTotalsV3RequestDate` |  |  |
| `posting_number` | string |  | Shipment number. |
| `transaction_type` | string |  | Transaction type:   - `all`—all,   - `orders`—orders,   - `returns`—returns and cancellations,   - ` |

**响应 200**: Transactions sum
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `financev3FinanceTransactionTotalsV3ResponseResult` |  |  |
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

### POST `/v1/finance/document-b2b-sales`
**Legal entities sales register**  
operationId: `ReportAPI_CreateDocumentB2BSalesReport`  

Use the method to get sales to legal entities report. Matches the **Finance → Documents → Legal entities sales register** section in your personal account.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date` | string | ✓ | Time period in the `YYYY-MM` format. |
| `language` | `commonLanguage` |  |  |

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

### POST `/v1/finance/document-b2b-sales/json`
**Legal entities sales register in JSON format**  
operationId: `ReportAPI_CreateDocumentB2BSalesJSONReport`  

Use the method to get sales to legal entities register in JSON format. Matches the **Finance → Documents → Legal entities sales register section** in your personal account.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date` | string | ✓ | Reporting period in the `YYYY-MM` format. The report is available up to and including January 2019. |

**响应 200**: Register in JSON format
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string |  | Start date of the reporting period in the `YYYYYY-MM-DD` format. |
| `date_to` | string |  | End date of the reporting period in the `YYYYY-MM-DD` format. |
| `invoices` | array[CreateDocumentB2BSalesJSONReportResponseLegalSaleInvoice] |  | Invoice list. |
| `seller_info` | `CreateDocumentB2BSalesJSONReportResponseSellerInfo` |  |  |
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

### POST `/v1/finance/mutual-settlement`
**Mutual settlements report**  
operationId: `ReportAPI_CreateMutualSettlementReport`  

Use the method to get mutual settlements report. Matches the **Finance → Documents → Analytical reports → Mutual settlements report** section in your personal account.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date` | string | ✓ | Time period in the `YYYY-MM` format. |
| `language` | `commonLanguage` |  |  |

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

### POST `/v1/finance/products/buyout`
**Purchased product report**  
operationId: `GetFinanceProductsBuyout`  

Returns a report on products purchased by Ozon for resale in the EAEU and other countries. The method corresponds to the **Finance → Documents → UTDs on transactions with legal entities → UTD for purchased products** section in your personal account.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string | ✓ | Date from which the data will be in the report. |
| `date_to` | string | ✓ | Date up to which the data will be in the report.  The maximum period is 31 days.  |

**响应 200**: Purchased product report
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `products` | array[GetFinanceProductsBuyoutResponseProduct] |  | Purchased product list |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/finance/compensation`
**Compensation report**  
operationId: `ReportAPI_GetCompensationReport`  

Use the method to get а compensation report. It is the same as the report from the **Finance → Documents → Compensation and other accruals** section in your personal account.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date` | string | ✓ | Reporting period in the `YYYY-MM` format. |
| `language` | `compensationReportLanguage` |  |  |

**响应 200**: Compensation report
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `CreateReportResponseCodeNoDeadline` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/finance/decompensation`
**Decompensation report**  
operationId: `ReportAPI_GetDecompensationReport`  

Use the method to get а decompensation report. It is the same as the report from the **Finance → Documents → Compensation and other accruals** section in your personal account.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date` | string | ✓ | Reporting period in the `YYYY-MM` format. |
| `language` | `compensationReportLanguage` |  |  |

**响应 200**: Decompensation report
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `CreateReportResponseCodeNoDeadline` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/receipts/get`
**Get receipt in PDF format**  
operationId: `GetReceipt`  

<aside class="warning">
 Method is available to sellers who signed a contract with "OZON Marketplace Kazakhstan" LLP.
</aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `receipt_id` | string | ✓ | Receipt identifier. Get the parameter value using the [/v1/receipts/seller/list](#operation/Receipts |

**响应 200**: Receipt
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `content` | string |  | PDF file with receipt in binary format. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/receipts/seller/list`
**Get list of seller receipts**  
operationId: `ReceiptsSellerList`  

<aside class="warning">
 Method is available to sellers who signed a contract with "OZON Marketplace Kazakhstan" LLP.
</aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | integer |  | Number of pages to skip. |
| `page_size` | integer |  | Number of elements on the page. |
| `posting_numbers` | array[string] |  | Filter by shipment numbers. |

**响应 200**: List of seller receipts
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `has_next` | boolean |  | Indication that not all entries are in the response:  - `true`: create another request with a differ |
| `receipts` | array[ReceiptsSellerListResponseReceipt] |  | Receipt details. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/receipts/upload`
**Upload receipt**  
operationId: `UploadReceipt`  

<aside class="warning">
 Method is available to sellers who signed a contract with "OZON Marketplace Kazakhstan" LLP.
</aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`multipart/form-data`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `content` | string | ✓ | File content in binary format. |
| `operation_type` | string | ✓ | Operation type. Get the parameter value using the [/v1/receipts/seller/list](#operation/ReceiptsSell |
| `parent_receipt_id` | string |  | Parent receipt identifier. Pass the parameter with the identifier of the receipt to edit. |
| `posting_numbers` | array[string] | ✓ | Shipment numbers. |
| `receipt_number` | string | ✓ | Receipt number. |
| `type` | `v1UploadReceiptRequestTypeEnum` | ✓ |  |

**响应 200**: Receipt uploaded
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `receipt_id` | string |  | Receipt identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---