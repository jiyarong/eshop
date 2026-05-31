# FBP/DBS 订单 API（快递上门自提）

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/fbp/warehouse/list` | Get partner warehouses list |
| POST | `/v1/fbp/draft/get` | Get information about supply draft |
| POST | `/v1/fbp/draft/list` | Supply drafts list |
| POST | `/v1/fbp/draft/direct/seller-dlv/create` | Create draft with delivery by seller |
| POST | `/v1/fbp/draft/direct/seller-dlv/edit` | Update draft with information about delivery by seller |
| POST | `/v1/fbp/draft/direct/timeslot/edit` | Edit time slot in draft |
| POST | `/v1/fbp/draft/direct/timeslot/get` | Get list of time slots for direct supply |
| POST | `/v1/fbp/draft/direct/create` | Create supply request draft without specifying delivery method |
| POST | `/v1/fbp/draft/direct/delete` | Delete draft of supply request |
| POST | `/v1/fbp/draft/direct/product/validate` | Validate product list for partner warehouse |
| POST | `/v1/fbp/draft/direct/registrate` | Transfer draft to current supply |
| POST | `/v1/fbp/draft/direct/tpl-dlv/create` | Create supply request for delivery by a third-party transport company |
| POST | `/v1/fbp/draft/direct/tpl-dlv/edit` | Edit a draft of shipment with a third-party transport company |
| POST | `/v1/fbp/draft/drop-off/province/list` | Get province list |
| POST | `/v1/fbp/draft/drop-off/point/list` | Get list of drop-off points in province |
| POST | `/v1/fbp/draft/drop-off/point/timetable` | Get drop-off point schedule |
| POST | `/v1/fbp/draft/drop-off/product/validate` | Check product list that partner's warehouse can accept |
| POST | `/v1/fbp/draft/drop-off/create` | Create draft for delivery to drop-off point |
| POST | `/v1/fbp/draft/drop-off/delete` | Delete draft for delivery to drop-off point |
| POST | `/v1/fbp/draft/drop-off/dlv/edit` | Edit delivery details for drop-off draft |
| POST | `/v1/fbp/draft/drop-off/registrate` | Transfer draft to current supply |
| POST | `/v1/fbp/draft/pick-up/registrate` | Transfer draft to current supply |
| POST | `/v1/fbp/draft/pick-up/create` | Create request draft for pick-up supply |
| POST | `/v1/fbp/draft/pick-up/delete` | Cancel request draft for pick-up supply |
| POST | `/v1/fbp/draft/pick-up/dlv/edit` | Update request draft for pick-up supply |
| POST | `/v1/fbp/draft/pick-up/product/validate` | Validate product list for pick-up supply |
| POST | `/v1/fbp/order/direct/cancel` | Cancel supply |
| POST | `/v1/fbp/order/direct/seller-dlv/edit` | Update information about delivery by seller |
| POST | `/v1/fbp/order/direct/timeslot/edit` | Edit time slot in supply request |
| POST | `/v1/fbp/order/direct/timeslot/list` | Get list of time slots for supply |
| POST | `/v1/fbp/order/drop-off/cancel` | Cancel supply to drop-off point |
| POST | `/v1/fbp/order/drop-off/dlv/edit` | Edit information about supply to drop-off point |
| POST | `/v1/fbp/order/drop-off/timetable` | Get drop-off point working schedule |
| POST | `/v1/fbp/order/pick-up/cancel` | Cancel pick-up supply |
| POST | `/v1/fbp/order/pick-up/dlv/edit` | Edit pick-up point details |
| POST | `/v1/fbp/act-from/create` | Generate acceptance certificate |
| POST | `/v1/fbp/act-from/get` | Get status of acceptance certificate generation |
| POST | `/v1/fbp/act-to/create` | Generate waybill |
| POST | `/v1/fbp/act-to/get` | Get status of waybill generation |
| POST | `/v1/fbp/archive/get` | Get details on completed supply |
| POST | `/v1/fbp/archive/list` | Get list of completed supplies |
| POST | `/v1/fbp/label/create` | Create label generation task |
| POST | `/v1/fbp/label/get` | Get status of label generation task |
| POST | `/v1/fbp/order/get` | Get information about supply |
| POST | `/v1/fbp/order/list` | Get list of supplies |

---

## 接口详情


### POST `/v1/fbp/warehouse/list`
**Get partner warehouses list**  
operationId: `FbpWarehouseList`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Partner warehouses list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `warehouses` | array[FbpWarehouseListResponseWarehouse] |  | List of warehouses. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/get`
**Get information about supply draft**  
operationId: `FbpAPI_FbpDraftGet`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Draft details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bundle_id` | string |  | Identifier of the validated product list. |
| `cancellation_state` | `v1CancellationState` |  |  |
| `created_at` | string |  | Date and time of draft creation. |
| `decline_reason` | `FbpDraftGetResponseDeclineReason` |  |  |
| `deleted_at` | string |  | Date and time of deletion. |
| `delivery_details` | `v1fbpDeliveryDetails` |  |  |
| `editable` | boolean |  | `true`, if draft is editable.  |
| `id` | integer |  | Draft identifier. |
| `is_cancelable` | boolean |  | `true`, if draft is cancelable.  |
| `is_deletable` | boolean |  | `true`, if draft is deletable.  |
| `is_registration_available` | boolean |  | `true`, if registration is available.  |
| `locked` | boolean |  | `true`, if draft is locked.  |
| `package_units_count` | integer |  | Number of package units. |
| `row_version` | integer |  | Identifier of the current draft version. |
| `status` | `v1DraftStatusEnum` |  |  |
| `supply_id` | string |  | Supply identifier. |
| `warehouse_id` | integer |  | Warehouse identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/list`
**Supply drafts list**  
operationId: `FbpAPI_FbpDraftList`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `count` | integer | ✓ | Number of elements in the response. |
| `last_id` | integer |  | Identifier of the last value on the page.  To get the next values, specify the recieved value in the |

**响应 200**: Supply drafts list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `has_next` | boolean |  | `true`, if not all elements were returned in the response.  |
| `items` | array[v1FbpDraftListResponseItem] |  | Drafts. |
| `last_id` | integer |  | Identifier of the last value on the page. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/direct/seller-dlv/create`
**Create draft with delivery by seller**  
operationId: `FbpDraftDirectSellerDlvCreate`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bundle_id` | string | ✓ | Identifier of the validated product list. |
| `delivery_details` | `v1FbpDraftDirectSellerDlvCreateRequestDirectDetails` | ✓ |  |
| `package_units_count` | integer | ✓ | Number of package units. |
| `warehouse_id` | integer | ✓ | Seller warehouse identifier. |

**响应 200**: Draft created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `draft_id` | integer |  | Draft identifier. |
| `row_version` | integer |  | Identifier of the current draft version. |
| `supply_id` | string |  | Supply request identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/direct/seller-dlv/edit`
**Update draft with information about delivery by seller**  
operationId: `FbpDraftDirectSellerDlvEdit`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `driver_name` | string | ✓ | Driver's full name. |
| `row_version` | integer | ✓ | Identifier of the current draft version. |
| `supply_id` | string | ✓ | Supply request identifier. |
| `vehicle_number` | string | ✓ | Vehicle number. |
| `vehicle_type` | string | ✓ | Vehicle type. |

**响应 200**: Draft updated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | `v1OrderDraftValidationError` |  |  |
| `is_error` | boolean |  | `true` if there is an error.  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/direct/timeslot/edit`
**Edit time slot in draft**  
operationId: `FbpDraftDirectTimeslotEdit`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `row_version` | integer | ✓ | Identifier of the current draft version. |
| `supply_id` | string | ✓ | Supply request identifier. |
| `timeslot_start` | string | ✓ | Start of the time slot. |

**响应 200**: Time slot edited
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error_reasons` | array[v1FbpDraftDirectTimeslotEditResponseReserveFailureType] |  | Error reason:   - `RESERVE_FAILURE_TYPE_UNSPECIFIED`: undefined;   - `REQUEST_VALIDATION`: reservati |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/direct/timeslot/get`
**Get list of time slots for direct supply**  
operationId: `FbpDraftDirectGetTimeslot`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bundle_id` | string | ✓ | Identifier of the validated product list. |
| `interval_end` | string | ✓ | End date of the required time slot period. |
| `interval_start` | string | ✓ | Start date of the required time slot period. |
| `warehouse_id` | integer | ✓ | Seller warehouse identifier. |

**响应 200**: Time slot list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `reasons` | array[v1FbpDraftDirectGetTimeslotResponseEmptyTimeslotsReason] |  | Reasons for the lack of time slots: - `EMPTY_TIMESLOTS_REASON_UNSPECIFIED`: undefined; - `LOGISTICS_ |
| `timeslots` | array[v1FbpDraftDirectGetTimeslotResponseTimeslot] |  | List of available time slots. |
| `warehouse_timezone_name` | string |  | Time zone of the seller's warehouse. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/direct/create`
**Create supply request draft without specifying delivery method**  
operationId: `FbpDraftDirectCreate`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bundle_id` | string | ✓ | Identifier of the validated product list. To get it, use the [/v1/fbp/draft/direct/product/validate] |
| `delivery_details` | `v1FbpDraftDirectCreateRequestDirectDetails` | ✓ |  |
| `package_units_count` | integer | ✓ | Number of items per package. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Draft created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `draft_id` | integer |  | Draft identifier. |
| `row_version` | integer |  | Identifier of the current draft version. |
| `supply_id` | string |  | Supply identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/direct/delete`
**Delete draft of supply request**  
operationId: `FbpDraftDirectDelete`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Draft deleted
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cancellation_state` | `v1CancellationState` |  |  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/direct/product/validate`
**Validate product list for partner warehouse**  
operationId: `FbpDraftDirectProductValidate`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `skus` | array[v1FbpDraftDirectProductValidateRequestSkuItem] | ✓ | Product identifiers in the Ozon system, SKU. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Validation result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `approved_items` | array[v1FbpDraftDirectProductValidateResponseApprovedItem] |  | Confirmed products. |
| `bundle_generated` | boolean |  | `true` if the validated product list is created. |
| `bundle_id` | string |  | Identifier of the validated product list. |
| `rejected_items` | array[v1FbpDraftDirectProductValidateResponseRejectedItem] |  | Rejected products. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/direct/registrate`
**Transfer draft to current supply**  
operationId: `FbpDraftDirectRegistrate`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `row_version` | integer | ✓ | Identifier of the current draft version. |
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Success
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | `v1FbpDraftDirectRegistrateResponseRegistrationError` |  |  |
| `is_error` | boolean |  | `true` if there is an error. |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/direct/tpl-dlv/create`
**Create supply request for delivery by a third-party transport company**  
operationId: `FbpAPI_FbpDraftDirectTplDlvCreate`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bundle_id` | string | ✓ | Identifier of the validated product list. |
| `delivery_details` | `v1FbpDraftDirectTplDlvCreateRequestDirectDetails` | ✓ |  |
| `package_units_count` | integer | ✓ | Number of package units. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Generation status
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `draft_id` | integer |  | Draft identifier. |
| `row_version` | integer |  | Identifier of the current draft version. |
| `supply_id` | string |  | Supply identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/direct/tpl-dlv/edit`
**Edit a draft of shipment with a third-party transport company**  
operationId: `FbpAPI_FbpDraftDirectTplDlvEdit`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `row_version` | integer | ✓ | Identifier of the current draft version. |
| `supply_id` | string | ✓ | Supply identifier. |
| `tracking_number` | string | ✓ | Shipment tracking number. |
| `transport_company_name` | string | ✓ | Logistics provider name. |

**响应 200**: Draft edited
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | `v1OrderDraftValidationError` |  |  |
| `is_error` | boolean |  | `true` if there is an error.  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/drop-off/province/list`
**Get province list**  
operationId: `FbpDraftDropOffProvinceList`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Province list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `provinces` | array[FbpDraftDropOffProvinceListResponseProvince] |  | Province list. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/drop-off/point/list`
**Get list of drop-off points in province**  
operationId: `FbpDraftDropOffPointList`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `next_page_number` | integer |  | Next page number. |
| `page_size` | integer | ✓ | Number of elements on the page. |
| `province_uuid` | string | ✓ | Unique province identifier. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: List of drop-off points
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `drop_off_points` | array[FbpDraftDropOffPointListResponseDropOffPoint] |  | List of drop-off points. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/drop-off/point/timetable`
**Get drop-off point schedule**  
operationId: `FbpDraftDropOffPointTimetable`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `drop_off_point_id` | integer | ✓ | Drop-off point identifier. |
| `province_uuid` | string | ✓ | Unique province identifier. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Drop-off point schedule
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `calendar` | array[v1FbpDraftDropOffPointTimetableResponseCalendar] |  | Work schedule of the drop-off point. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/drop-off/product/validate`
**Check product list that partner's warehouse can accept**  
operationId: `FbpDraftDropOffProductValidate`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `skus` | array[v1FbpDraftDropOffProductValidateRequestSkuItem] | ✓ | Product identifiers in the Ozon system, SKU. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Check result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `approved_items` | array[v1FbpDraftDropOffProductValidateResponseApprovedItem] |  | Accepted products. |
| `bundle_generated` | boolean |  | `true` if bundle is created.  |
| `bundle_id` | string |  | Identifier of the validated product list. |
| `rejected_items` | array[v1FbpDraftDropOffProductValidateResponseRejectedItem] |  | Rejected products. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/drop-off/create`
**Create draft for delivery to drop-off point**  
operationId: `FbpDraftDropOffCreate`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bundle_id` | string | ✓ | Identifier of the validated product list. |
| `delivery_details` | `v1FbpDraftDropOffCreateRequestDeliveryDetails` | ✓ |  |
| `package_units_count` | integer | ✓ | Number of package units. |
| `warehouse_id` | integer | ✓ | Seller warehouse identifier. |

**响应 200**: Draft created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `draft_id` | integer |  | Draft identifier. |
| `row_version` | integer |  | Identifier of the current draft version. |
| `supply_id` | string |  | Supply request identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/drop-off/delete`
**Delete draft for delivery to drop-off point**  
operationId: `FbpDraftDropOffDelete`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply request identifier. |

**响应 200**: Draft deleted
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cancellation_state` | `v1CancellationState` |  |  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/drop-off/dlv/edit`
**Edit delivery details for drop-off draft**  
operationId: `FbpDraftDropOffDlvEdit`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `drop_off_date` | string | ✓ | Delivery date. |
| `drop_off_point_id` | integer | ✓ | Drop-off point identifier. |
| `drop_off_province_uuid` | string | ✓ | Unique province identifier. |
| `row_version` | integer | ✓ | Draft identifier. |
| `supply_id` | string | ✓ | Supply request identifier. |

**响应 200**: Success
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/drop-off/registrate`
**Transfer draft to current supply**  
operationId: `FbpDraftDropOffRegistrate`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `row_version` | integer | ✓ | Identifier of the current draft version. |
| `supply_id` | string | ✓ | Supply request identifier. |

**响应 200**: Success
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | `v1FbpDraftDropOffRegistrateResponseRegistrationError` |  |  |
| `is_error` | boolean |  | `true` if there is an error.  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/pick-up/registrate`
**Transfer draft to current supply**  
operationId: `FbpDraftPickUpRegistrate`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `row_version` | integer | ✓ | Identifier of the current draft version. |
| `supply_id` | string | ✓ | Supply request identifier. |

**响应 200**: Success
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | `v1FbpDraftPickUpRegistrateResponseRegistrationError` |  |  |
| `is_error` | boolean |  | `true` if there is an error.  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/pick-up/create`
**Create request draft for pick-up supply**  
operationId: `FbpAPI_FbpDraftPickupCreate`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bundle_id` | string | ✓ | Supply contents identifier. |
| `delivery_details` | `v1FbpDraftPickupCreateRequestDeliveryDetails` | ✓ |  |
| `package_units_count` | integer | ✓ | Number of package units. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Draft created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `draft_id` | integer |  | Identifier of the supply request draft. |
| `row_version` | integer |  | Identifier of the current draft version. |
| `supply_id` | string |  | Supply identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/pick-up/delete`
**Cancel request draft for pick-up supply**  
operationId: `FbpAPI_FbpDraftPickUpDelete`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Draft canceled
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cancellation_state` | `v1CancellationState` |  |  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/pick-up/dlv/edit`
**Update request draft for pick-up supply**  
operationId: `FbpAPI_FbpDraftPickupDlvEdit`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pickup_details` | `v1FbpDraftPickupDlvEditRequestDeliveryDetails` | ✓ |  |
| `row_version` | integer | ✓ | Identifier of the current draft version. |
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Draft updated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/draft/pick-up/product/validate`
**Validate product list for pick-up supply**  
operationId: `FbpAPI_FbpDraftPickUpProductValidate`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `skus` | array[v1FbpDraftPickUpProductValidateRequestSkuItem] | ✓ | List of product SKUs. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: List validated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `approved_items` | array[v1FbpDraftPickUpProductValidateResponseApprovedItem] |  | Confirmed products. |
| `bundle_generated` | boolean |  | `true` if the validated product list is created.  |
| `bundle_id` | string |  | Identifier of the validated product list. |
| `rejected_items` | array[v1FbpDraftPickUpProductValidateResponseRejectedItem] |  | Rejected products. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/order/direct/cancel`
**Cancel supply**  
operationId: `FbpAPI_FbpOrderDirectCancel`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply request identifier. |

**响应 200**: Cancellation result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | `v1OrderValidationError` |  |  |
| `is_error` | boolean |  | `true` if there is an error.  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/order/direct/seller-dlv/edit`
**Update information about delivery by seller**  
operationId: `FbpAPI_FbpOrderDirectSellerDlvEdit`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `driver_name` | string | ✓ | Driver's full name. |
| `row_version` | integer | ✓ | Identifier of the current draft version. |
| `supply_id` | string | ✓ | Supply request identifier. |
| `vehicle_number` | string | ✓ | Vehicle number. |
| `vehicle_type` | string | ✓ | Vehicle type. |

**响应 200**: Information updated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | `v1OrderValidationError` |  |  |
| `is_error` | boolean |  | `true` if there is an error.  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/order/direct/timeslot/edit`
**Edit time slot in supply request**  
operationId: `FbpAPI_FbpEditTimeslot`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `row_version` | integer | ✓ | Identifier of the current draft version. |
| `supply_id` | string | ✓ | Supply request identifier. |
| `timeslot_start` | string | ✓ | Start of the time slot. |

**响应 200**: Time slot edited
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error_reasons` | array[v1FbpEditTimeslotResponseReserveFailureType] |  | Error reason: - `RESERVE_FAILURE_TYPE_UNSPECIFIED`: undefined; - `REQUEST_VALIDATION`: reservation d |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/order/direct/timeslot/list`
**Get list of time slots for supply**  
operationId: `FbpAPI_FbpAvailableTimeslotList`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `interval_end` | string | ✓ | End date of the required time slot period. |
| `interval_start` | string | ✓ | Start date of the required time slot period. |
| `supply_id` | string | ✓ | Supply request identifier. |

**响应 200**: Time slot list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `reasons` | array[v1FbpAvailableTimeslotListResponseEmptyTimeslotsReason] |  | Reasons for the lack of time slots: - `EMPTY_TIMESLOTS_REASON_UNSPECIFIED`: undefined; - `LOGISTICS_ |
| `timeslots` | array[fbpv1Timeslot] |  | List of available time slots. |
| `warehouse_timezone_name` | string |  | Time zone of the seller's warehouse. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/order/drop-off/cancel`
**Cancel supply to drop-off point**  
operationId: `FbpAPI_FbpOrderDropOffCancel`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Supply canceled
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | `v1OrderValidationError` |  |  |
| `is_error` | boolean |  | `true` if there is an error.  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/order/drop-off/dlv/edit`
**Edit information about supply to drop-off point**  
operationId: `FbpAPI_FbpOrderDropOffDlvEdit`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `drop_off_date` | string | ✓ | Date of delivery to drop-off point. |
| `row_version` | integer | ✓ | Identifier of the current draft version. |
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Information passed
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/order/drop-off/timetable`
**Get drop-off point working schedule**  
operationId: `FbpAPI_FbpOrderDropOffTimetable`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `drop_off_point_id` | integer | ✓ | Drop-off point identifier. |
| `province_uuid` | string | ✓ | Unique province identifier. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Working schedule
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `calendar` | array[v1FbpOrderDropOffTimetableResponseCalendar] |  | Work schedule of the drop-off point. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/order/pick-up/cancel`
**Cancel pick-up supply**  
operationId: `FbpAPI_FbpOrderPickUpCancel`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Cancellation status
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | `v1OrderValidationError` |  |  |
| `is_error` | boolean |  | `true` if there is an error.  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/order/pick-up/dlv/edit`
**Edit pick-up point details**  
operationId: `FbpAPI_FbpOrderPickUpDlvEdit`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pickup_details` | `v1FbpOrderPickUpDlvEditRequestPickUpDetails` | ✓ |  |
| `row_version` | integer | ✓ | Identifier of the current draft version. |
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Edit status
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | `v1OrderValidationError` |  |  |
| `is_error` | boolean |  | `true` if there is an error.  |
| `row_version` | integer |  | Identifier of the current draft version. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/act-from/create`
**Generate acceptance certificate**  
operationId: `FbpAPI_FbpCreateAct`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Success
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `errors` | array[FbpCreateActResponseCreateActErrorReason] |  | Error reason: - `CREATE_ACT_ERROR_REASON_UNSPECIFIED`: undefined; - `INVALID_ORDER_TYPE`: can't crea |
| `file_uuid` | string |  | Acceptance certificate identifier. |
| `is_success` | boolean |  | `true` if the request doesn't contain errors.  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/act-from/get`
**Get status of acceptance certificate generation**  
operationId: `FbpAPI_FbpCheckActState`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file_uuid` | string | ✓ | Acceptance certificate identifier. |

**响应 200**: Status of acceptance certificate generation
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cdn_url` | string |  | Link to acceptance certificate. |
| `error` | `FbpCheckActStateResponseErrorReason` |  |  |
| `status` | `v1FbpCheckActStateResponseStatus` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/act-to/create`
**Generate waybill**  
operationId: `FbpAPI_FbpCreateConsignmentNote`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Success
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string |  | Waybill identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/act-to/get`
**Get status of waybill generation**  
operationId: `FbpAPI_FbpCheckConsignmentNoteState`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string | ✓ | Waybill identifier. |
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Status of waybill generation
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error_message` | string |  | Error description. |
| `label_url` | string |  | Link to supply labels. |
| `state` | `FbpCheckConsignmentNoteStateResponseStateType` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/archive/get`
**Get details on completed supply**  
operationId: `FbpAPI_FbpArchiveGet`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Completed supply details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `act_file_uuid` | string |  | Acceptance certificate identifier. |
| `bundle_id` | string |  | Identifier of the validated product list. |
| `bundle_sku_summary` | `v1ArchiveSkuSummary` |  |  |
| `business_flow_type_id` | integer |  | Supply type identifier. |
| `created_date` | string |  | Date and time of the supply request creation. |
| `decline_reason` | `v1ArchiveDeclineReason` |  |  |
| `delivery_details` | `fbpv1DeliveryDetails` |  |  |
| `has_act` | boolean |  | `true` if an acceptance certificate was generated.  |
| `has_label` | boolean |  | `true` if labels were generated.  |
| `id` | integer |  | Archive record number. |
| `order_draft_id` | integer |  | Supply draft identifier. |
| `order_number` | string |  | Completed supply identifier. |
| `package_units_count` | integer |  | Number of package units. |
| `receive_date` | string |  | Date and time of the supply acceptance. |
| `row_version` | integer |  | Identifier of the current draft version. |
| `status` | `v1ArchiveStatusEnum` |  |  |
| `supply_id` | string |  | Supply identifier. |
| `warehouse_id` | integer |  | Warehouse identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/archive/list`
**Get list of completed supplies**  
operationId: `FbpAPI_FbpArchiveList`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `count` | string | ✓ | Number of items in the response. |
| `last_id` | string |  | Identifier of the last value on the page. Leave this field empty for the initial request.  To get th |

**响应 200**: List of completed supplies
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `has_next` | boolean |  | `true` if not all values are returned in the response.  |
| `items` | array[v1FbpArchiveListResponseItem] |  | Completed supplies. |
| `last_id` | integer |  | Creation date of the supply request. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/label/create`
**Create label generation task**  
operationId: `FbpAPI_FbpCreateLabel`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Task created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string |  | Identifier of the label generation task. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/label/get`
**Get status of label generation task**  
operationId: `FbpAPI_FbpGetLabel`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string | ✓ | Identifier of the label generation task. |
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Task created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `label_url` | string |  | Link to supply labels. |
| `state` | `FbpGetLabelResponseLabelCreationStateTypeEnum` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/order/get`
**Get information about supply**  
operationId: `FbpAPI_FbpOrderGet`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_id` | string | ✓ | Supply identifier. |

**响应 200**: Supply details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `attention_reasons` | array[v1OrderAttentionTypeEnum] |  | Warning reasons: - `ORDER_ATTENTION_TYPE_UNSPECIFIED`: undefined; - `OLD`: expired request; - `TIME_ |
| `bundle_uuid` | string |  | Identifier of the validated product list. |
| `can_be_cancelled` | boolean |  | `true` if the supply request can be canceled.  |
| `cancellation_state` | `v1CancellationState` |  |  |
| `created_date` | string |  | Creation date of the supply request. |
| `delivery_details` | `fbpv1DeliveryDetails` |  |  |
| `draft_id` | integer |  | Draft identifier. |
| `has_consignment_note` | boolean |  | `true` if order has consignment note.  |
| `has_label` | boolean |  | `true` if order has labels.  |
| `id` | integer |  | Supply request identifier. |
| `locked` | boolean |  | `true` if supply is locked from editing.  |
| `order_number` | string |  | Order number. |
| `package_units_count` | integer |  | Number of package units. |
| `receive_date` | string |  | Date and time of the supply acceptance. |
| `row_version` | integer |  | Identifier of the current draft version. |
| `status` | `v1OrderStatusEnum` |  |  |
| `supply_id` | string |  | Supply identifier. |
| `warehouse_id` | integer |  | Warehouse identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/fbp/order/list`
**Get list of supplies**  
operationId: `FbpAPI_FbpOrderList`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1700-FBP-metody/) in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `count` | integer | ✓ | Number of supplies in the response. |
| `last_id` | integer |  | Identifier of the last supply on the page. Leave this field blank in the first request.  To get the  |

**响应 200**: List of supplies
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `has_next` | boolean |  | `true` if not all supplies were returned in the response.  |
| `items` | array[v1FbpOrderListResponseItem] |  | Supplies. |
| `last_id` | integer |  | Identifier of the last order on the page. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---