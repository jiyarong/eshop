# 退货与取消 API

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/returns/list` | Information about FBO and FBS returns |
| POST | `/v1/returns/company/fbs/info` | FBS returns quantity |
| POST | `/v1/return/giveout/is-enabled` | Check the ability to receive return shipments by barcode |
| POST | `/v1/return/giveout/list` | Return shipments list |
| POST | `/v1/return/giveout/info` | Information on return shipment |
| POST | `/v1/return/giveout/barcode` | Value of barcode for return shipments |
| POST | `/v1/return/giveout/get-pdf` | Barcode for return shipment in PDF format |
| POST | `/v1/return/giveout/get-png` | Barcode for return shipment in PNG format |
| POST | `/v1/return/giveout/barcode-reset` | Generate new barcode |
| POST | `/v2/returns/rfbs/list` | Get a list of return requests |
| POST | `/v2/returns/rfbs/get` | Get information about a return request |
| POST | `/v2/returns/rfbs/reject` | Reject a return request |
| POST | `/v2/returns/rfbs/compensate` | Compensate partial cost |
| POST | `/v2/returns/rfbs/verify` | Approve a return request |
| POST | `/v2/returns/rfbs/receive-return` | Confirm receipt of a product for check |
| POST | `/v2/returns/rfbs/return-money` | Refund the customer |
| POST | `/v1/returns/rfbs/action/set` | Pass available actions for rFBS returns |
| POST | `/v2/conditional-cancellation/list` | Get a list of rFBS cancellation requests |
| POST | `/v2/conditional-cancellation/approve` | Approve rFBS cancellation request |
| POST | `/v2/conditional-cancellation/reject` | Reject rFBS cancellation request |

---

## 接口详情


### POST `/v1/returns/list`
**Information about FBO and FBS returns**  
operationId: `returnsList`  

A method to retrieve information about FBO and FBS returns.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `GetReturnsListRequestFilter` |  |  |
| `limit` | integer | ✓ | Number of loaded returns. The maximum value is 500. |
| `last_id` | integer |  | Identifier of the last loaded return. |

**响应 200**: Returns details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `returns` | array[GetReturnsListResponseReturnsItem] |  | Returns details. |
| `has_next` | boolean |  | `true`, if the seller has other returns.  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/returns/company/fbs/info`
**FBS returns quantity**  
operationId: `returnsCompanyFBSInfo`  

The method to get information about FBS returns and their quantity.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `v1ReturnsCompanyFbsInfoRequestFilter` |  |  |
| `pagination` | `ReturnsCompanyFbsInfoRequestPagination` | ✓ |  |

**响应 200**: FBS returns quantity
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `drop_off_points` | array[ReturnsCompanyFbsInfoResponseDropOffPoints] |  | Information about drop-off points. |
| `has_next` | boolean |  | `true` if there are any other points where sellers have orders waiting.  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/return/giveout/is-enabled`
**Check the ability to receive return shipments by barcode**  
operationId: `ReturnAPI_GiveoutIsEnabled`  

The `enabled` parameter is `true` if you can pick up return shipments by barcode.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: Check result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `enabled` | boolean |  | `true` if you can pick up a return shipment by barcode.  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/return/giveout/list`
**Return shipments list**  
operationId: `ReturnAPI_GiveoutList`  

Method for getting a list of active returns.
A return shipment becomes active after scan a barcode. 
After the barcode is scanned for a second time, the status of an active return shipment switches to inactive.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `last_id` | integer |  | Identifier of the last value on the page. |
| `limit` | integer | ✓ | Number of values in the response. |

**响应 200**: Return shipments list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `giveouts` | array[GiveoutListResponseGiveoutDetails] |  | Shipment identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/return/giveout/info`
**Information on return shipment**  
operationId: `ReturnAPI_GiveoutInfo`  

Method for getting information about return shipment. 
The value received in the [/v1/return/giveout/list](#operation/ReturnAPI_GiveoutList) method is passed to the `giveout_id` parameter.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `giveout_id` | integer | ✓ | Shipment identifier. |

**响应 200**: Information on return shipment
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `articles` | array[GiveoutInfoResponseArticleDetails] |  | Product IDs. |
| `giveout_id` | integer |  | Shipment identifier. |
| `giveout_status` | `v1GiveoutStatus` |  |  |
| `warehouse_address` | string |  | Warehouse address. |
| `warehouse_name` | string |  | Warehouse name. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/return/giveout/barcode`
**Value of barcode for return shipments**  
operationId: `ReturnAPI_GiveoutGetBarcode`  

Use this method to get the barcode from the response of the [/v1/return/giveout/get-png](#operation/ReturnAPI_GiveoutGetPNG) and [/v1/return/giveout/get-pdf](#operation/ReturnAPI_GiveoutGetPDF) methods in text format.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: Barcode value
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `barcode` | string |  | Barcode value in text format. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/return/giveout/get-pdf`
**Barcode for return shipment in PDF format**  
operationId: `ReturnAPI_GiveoutGetPDF`  

Returns a PDF file with a barcode. The method works only for the FBS scheme.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: Barcode for return shipment
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file_content` | string |  | PDF file with barcode in binary format. |
| `file_name` | string |  | File name. |
| `content_type` | string |  | File type. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/return/giveout/get-png`
**Barcode for return shipment in PNG format**  
operationId: `ReturnAPI_GiveoutGetPNG`  

Returns a PNG file with a barcode.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: Barcode for return shipment
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file_content` | string |  | PNG file with barcode in binary format. |
| `file_name` | string |  | File name. |
| `content_type` | string |  | File type. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/return/giveout/barcode-reset`
**Generate new barcode**  
operationId: `ReturnAPI_GiveoutBarcodeReset`  

Use this method if an unauthorized person has gained access to your barcode.

The method returns a PNG file with the new barcode. Once the method is used, you won't be able to get a return shipment using the old barcodes.
To get a new barcode in PDF format, use the [/v1/return/giveout/get-pdf](#operation/ReturnAPI_GiveoutGetPDF) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: New barcode
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file_content` | string |  | Barcode image in binary format. |
| `file_name` | string |  | File name. |
| `content_type` | string |  | File type. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/returns/rfbs/list`
**Get a list of return requests**  
operationId: `RFBSReturnsAPI_ReturnsRfbsListV2`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `v2ReturnsRfbsFilter` |  |  |
| `last_id` | integer |  | Identifier of the last value on the page: `return_id`. Leave this field blank in the first request.  |
| `limit` | integer | ✓ | Number of values per page. |

**响应 200**: List of return requests
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `returns` | `ReturnsRfbsListResponseReturns` |  |  |
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

### POST `/v2/returns/rfbs/get`
**Get information about a return request**  
operationId: `RFBSReturnsAPI_ReturnsRfbsGetV2`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `return_id` | integer | ✓ | Return request identifier. You can get it using the [/v2/returns/rfbs/list](#operation/RFBSReturnsAP |

**响应 200**: Information about the request
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `returns` | `ReturnsRfbsGetResponseReturns` |  |  |
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

### POST `/v2/returns/rfbs/reject`
**Reject a return request**  
operationId: `RFBSReturnsAPI_ReturnsRfbsRejectV2`  

<aside class="warning">
This method will be disabled. Switch to the <a href="#operation/ReturnsAPI_ReturnsRfbsActionSet">/v1/returns/rfbs/action/set</a> method.
</aside>

The method rejects an rFBS return request. Explain your decision in the `comment` parameter.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `return_id` | integer | ✓ | Return request identifier. |
| `comment` | string |  | Comment.  The comment is required if the `rejection_reason.is_comment_required` parameter is `true`  |
| `rejection_reason_id` | integer | ✓ | Rejection reason identifier.  Pass the value from the list of reasons received in the response of th |

**响应 200**: Request rejected
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

### POST `/v2/returns/rfbs/compensate`
**Compensate partial cost**  
operationId: `RFBSReturnsAPI_ReturnsRfbsCompensateV2`  

<aside class="warning">
This method will be disabled. Switch to the <a href="#operation/ReturnsAPI_ReturnsRfbsActionSet">/v1/returns/rfbs/action/set</a> method.
</aside>

Using this method you can confirm the partial compensation and agree to keep the product with the customer.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `compensation_amount` | string |  | Compensation amount. |
| `return_id` | integer | ✓ | Return request identifier. |

**响应 200**: Compensation confirmed
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

### POST `/v2/returns/rfbs/verify`
**Approve a return request**  
operationId: `RFBSReturnsAPI_ReturnsRfbsVerifyV2`  

<aside class="warning">
This method will be disabled. Switch to the <a href="#operation/ReturnsAPI_ReturnsRfbsActionSet">/v1/returns/rfbs/action/set</a> method.
</aside>

The method allows to approve an rFBS return request and agree to receive products for verification.

Confirm that you've received the product using the [/v2/returns/rfbs/receive-return](#operation/RFBSReturnsAPI_ReturnsRfbsReceiveReturnV2) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `return_id` | integer | ✓ | Return request identifier. |
| `return_method_description` | string |  | Method of product return. |

**响应 200**: Request approved
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

### POST `/v2/returns/rfbs/receive-return`
**Confirm receipt of a product for check**  
operationId: `RFBSReturnsAPI_ReturnsRfbsReceiveReturnV2`  

<aside class="warning">
  This method will be disabled. Switch to the <a href="#operation/ReturnsAPI_ReturnsRfbsActionSet">/v1/returns/rfbs/action/set</a> method.
</aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `return_id` | integer | ✓ | Return request identifier. |

**响应 200**: Receipt confirmed
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

### POST `/v2/returns/rfbs/return-money`
**Refund the customer**  
operationId: `RFBSReturnsAPI_ReturnsRfbsReturnMoneyV2`  

<aside class="warning">
This method will be disabled. Switch to the <a href="#operation/ReturnsAPI_ReturnsRfbsActionSet">/v1/returns/rfbs/action/set</a> method.
</aside>

The method confirms the refund of the full product cost.
Use the method if you agree to refund the customer:
  - Immediately without receiving the product.
  - After you received and checked the product. If the product is defective or damaged, you also refund its return shipment cost.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `return_id` | integer | ✓ | Return request identifier. |
| `return_for_back_way` | integer |  | Refund amount for shipping the product. |

**响应 200**: Refund confirmed
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

### POST `/v1/returns/rfbs/action/set`
**Pass available actions for rFBS returns**  
operationId: `ReturnsAPI_ReturnsRfbsActionSet`  

Method for passing actions for rFBS return.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `comment` | string |  | Seller comment.  Required for `id: -1` and `id: -10`.  |
| `compensation_amount` | number |  | Compensation amount.  Required for `id: 1020`.  |
| `id` | integer |  | Action identifier.   Get available actions via the `returns.available_actions` parameter using the [ |
| `rejection_reason_id` | integer |  | Rejection reason identifier.  Required for `id: -1` and `id: -10`.  Get available rejection reasons  |
| `return_for_back_way` | number |  | Amount refunded to the customer for shipping the product.  Negative values are treated as `0`.  |
| `return_id` | integer | ✓ | Return request identifier. |

**响应 200**: Action passed
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/conditional-cancellation/list`
**Get a list of rFBS cancellation requests**  
operationId: `CancellationAPI_GetConditionalCancellationListV2`  

Method for getting a list of rFBS cancellation requests.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filters` | `GetConditionalCancellationListV2RequestFilters` |  |  |
| `last_id` | integer |  | Identifier of the last value on the page. Leave this field blank in the first request.  To get the n |
| `limit` | integer | ✓ | Number of cancellation requests in the response. |
| `with` | `GetConditionalCancellationListV2RequestWith` |  |  |

**响应 200**: List of cancellation requests
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `counter` | integer |  | Counter of requests in the `ON_APPROVAL` status. |
| `last_id` | integer |  | Identifier of the last value on the page.  To get the next values, specify `last_id` from the respon |
| `result` | array[GetConditionalCancellationListV2ResponseResult] |  | Information of cancellation requests. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/conditional-cancellation/approve`
**Approve rFBS cancellation request**  
operationId: `CancellationAPI_ConditionalCancellationApproveV2`  

Use the method to approve rFBS cancellation requests in the `ON_APPROVAL` status. The order will be canceled and the money will be returned to the customer.

**响应 200**: Request approved
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/conditional-cancellation/reject`
**Reject rFBS cancellation request**  
operationId: `CancellationAPI_ConditionalCancellationRejectV2`  

Use the method to reject rFBS cancellation requests in the `ON_APPROVAL` status. Provide a reason in the `comment` parameter. The order will remain in the same status and should be delivered to the customer.

**响应 200**: Request rejected
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---