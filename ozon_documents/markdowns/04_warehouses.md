# 仓库管理 API

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/warehouse/list` | List of warehouses |
| POST | `/v1/delivery-method/list` | List of delivery methods for a warehouse |
| POST | `/v2/delivery-method/list` | List of delivery methods for realFBS warehouses |
| POST | `/v2/warehouse/list` | List of warehouses |
| POST | `/v1/warehouse/operation/status` | Get operation status |
| POST | `/v1/warehouse/archive` | Archive a warehouse |
| POST | `/v1/warehouse/unarchive` | Remove warehouse from archive |
| POST | `/v1/warehouse/invalid-products/get` | Get list of products with FBS delivery restrictions. |
| POST | `/v1/warehouse/warehouses-with-invalid-products` | Get list of warehouses with products restricted for delivery |
| POST | `/v1/warehouse/fbs/create/drop-off/list` | Get a list of drop-off points to create a warehouse |
| POST | `/v1/warehouse/fbs/update/drop-off/list` | Get a list of drop-off points for changing warehouse details |
| POST | `/v1/warehouse/fbs/create/drop-off/timeslot/list` | Get list of time slots for creating warehouse with drop-off shipment |
| POST | `/v1/warehouse/fbs/update/drop-off/timeslot/list` | Get list of time slots for updating warehouse with drop-off shipment |
| POST | `/v1/warehouse/fbs/create/pick-up/timeslot/list` | Get list of time slots for creating warehouse with pick-up shipment |
| POST | `/v1/warehouse/fbs/update/pick-up/timeslot/list` | Get list of time slots for updating warehouse with pick-up shipment |
| POST | `/v1/warehouse/fbs/create` | Create a warehouse |
| POST | `/v1/warehouse/fbs/update` | Update warehouse |
| POST | `/v1/warehouse/fbs/pickup/courier/create` | Create courier request for pickup shipments |
| POST | `/v1/warehouse/fbs/pickup/courier/cancel` | Cancel courier request for pickup shipments |
| POST | `/v1/warehouse/fbs/first-mile/update` | Update first mile |
| POST | `/v1/warehouse/fbs/pickup/history/list` | Get history of shippings to couriers |
| POST | `/v1/warehouse/fbs/pickup/planning/list` | Get warehouse list for courier delivery planning |
| POST | `/v1/polygon/create` | Create delivery polygon |
| POST | `/v1/polygon/bind` | Link delivery method to a delivery polygon |

---

## 接口详情


### POST `/v1/warehouse/list`
**List of warehouses**  
operationId: `WarehouseAPI_WarehouseList`  

<aside class="warning">
  Method is deprecated and will be disabled on April 7, 2026. Switch to the new version <a href="#operation/WarehouseListV2">/v2/warehouse/list</a>.
</aside>

Returns the list of FBS and rFBS warehouses. To get the list of FBO warehouses, use the [/v1/cluster/list](#operation/SupplyDraftAPI_DraftClusterList) method.

You can use the method once per minute.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | integer | ✓ | Number of values in the response. |
| `offset` | integer |  | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |

**响应 200**: List of warehouses
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[WarehouseListResponseWarehouse] |  | Warehouses list. |
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

### POST `/v1/delivery-method/list`
**List of delivery methods for a warehouse**  
operationId: `WarehouseAPI_DeliveryMethodList`  

<aside class="warning">
  Method is deprecated and will be disabled on April 7, 2026. Switch to the <a href="#operation/WarehouseAPI_DeliveryMethodListV2">/v2/delivery-method/list</a> method.
</aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `DeliveryMethodListRequestFilter` |  |  |
| `limit` | integer | ✓ | Number of items in a response. Maximum is 50, minimum is 1. |
| `offset` | integer |  | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |

**响应 200**: List of delivery methods for a warehouse
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `has_next` | boolean |  | Indication that only part of delivery methods was returned in the response: - `true`—make a request  |
| `result` | array[DeliveryMethodListResponseDeliveryMethod] |  | Method result. |
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

### POST `/v2/delivery-method/list`
**List of delivery methods for realFBS warehouses**  
operationId: `WarehouseAPI_DeliveryMethodListV2`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `filter` | `DeliveryMethodListV2RequestFilter` |  |  |
| `limit` | integer | ✓ | Number of values in the response. |
| `sort_dir` | `DeliveryMethodListV2RequestSortDirEnum` |  |  |

**响应 200**: List of delivery methods
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `has_next` | boolean |  | `true` if not all delivery methods are returned in the response.  |
| `delivery_methods` | array[DeliveryMethodListV2ResponseDeliveryMethod] |  | Delivery methods. |
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

### POST `/v2/warehouse/list`
**List of warehouses**  
operationId: `WarehouseListV2`  

Method returns a list of FBS and rFBS warehouses. To get a list of FBO warehouses, use the [/v1/warehouse/fbo/list](#operation/SupplyDraftAPI_DraftGetWarehouseFboList) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | integer | ✓ | Number of values in the response. |
| `cursor` | string |  | Cursor for the next data sample. |
| `warehouse_ids` | array[string] |  | Warehouse identifiers. |

**响应 200**: List of warehouses
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `warehouses` | array[WarehouseListV2ResponseWarehouse] |  | List of warehouses. |
| `has_next` | boolean |  | `true` if not all values are returned in the response.  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/operation/status`
**Get operation status**  
operationId: `GetWarehouseFBSOperationStatus`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string | ✓ | Operation identifier. |

**响应 200**: Operation status
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error` | `GetWarehouseFBSOperationStatusResponseError` |  |  |
| `result` | `GetWarehouseFBSOperationStatusResponseResult` |  |  |
| `status` | `GetWarehouseFBSOperationStatusResponseStatusEnum` |  |  |
| `type` | `GetWarehouseFBSOperationStatusResponseTypeEnum` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/archive`
**Archive a warehouse**  
operationId: `ArchiveWarehouseFBS`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `reason` | string | ✓ | Archiving reason. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Warehouse is archived
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string |  | Operation identifier. Get the operation status using the [/v1/warehouse/operation/status](#operation |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/unarchive`
**Remove warehouse from archive**  
operationId: `UnarchiveWarehouseFBS`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Warehouse is removed from archive
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string |  | Operation identifier. Get the operation status using the [/v1/warehouse/operation/status](#operation |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/invalid-products/get`
**Get list of products with FBS delivery restrictions.**  
operationId: `WarehouseInvalidProductsGet`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `last_id` | integer |  | Identifier of the last value on the page. Leave this field blank in the first request.  To get the n |
| `warehouse_id` | integer | ✓ | Warehouse identifier. Get the parameter value using the [/v1/warehouse/warehouses-with-invalid-produ |

**响应 200**: List of products with restrictions
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `has_next` | boolean |  | `true` if not all products are returned in the response.  |
| `last_id` | integer |  | Identifier of the last value on the page. To get the next values, specify the received value in the  |
| `validation_results` | array[WarehouseInvalidProductsGetResponseValidationResult] |  | Result of verification. |
| `warehouse_id` | integer |  | Warehouse identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/warehouses-with-invalid-products`
**Get list of warehouses with products restricted for delivery**  
operationId: `WarehouseWithInvalidProducts`  

Returns the identifiers of warehouses that have restricted products. Such products aren't available for delivery from the warehouse.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: List of warehouses
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `warehouse_ids` | array[string] |  | List of warehouses identifiers. There should be at least 1 product at the warehouse that isn't avail |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/create/drop-off/list`
**Get a list of drop-off points to create a warehouse**  
operationId: `WarehouseAPI_ListDropOffPointsForCreateFBSWarehouse`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `coordinates` | `v1ListDropOffPointsForCreateFBSWarehouseRequestCoordinates` |  |  |
| `country_code` | string | ✓ | Country code in the ISO 2 format.  |
| `is_kgt` | boolean | ✓ | `true` if the product is bulky.  |
| `search` | `ListDropOffPointsForCreateFBSWarehouseRequestSearch` |  |  |

**响应 200**: List received
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `points` | array[ListDropOffPointsForCreateFBSWarehouseResponseDropOffPoint] |  | Drop-off points list. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/update/drop-off/list`
**Get a list of drop-off points for changing warehouse details**  
operationId: `WarehouseAPI_ListDropOffPointsForUpdateFBSWarehouse`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `search` | `ListDropOffPointsForUpdateFBSWarehouseRequestSearch` |  |  |
| `warehouse_id` | integer | ✓ | Filter by existing FBS warehouse. |

**响应 200**: List received
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `points` | array[ListDropOffPointsForUpdateFBSWarehouseResponseDropOffPoint] |  | List of drop-off points. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/create/drop-off/timeslot/list`
**Get list of time slots for creating warehouse with drop-off shipment**  
operationId: `WarehouseFbsCreateDropOffTimeslotList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `drop_off_point_id` | integer | ✓ | Drop-off point identifier. |

**响应 200**: List of time slots
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `timeslots` | array[v1WarehouseFbsCreateDropOffTimeslotListResponseTimeslot] |  | List of time slots. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/update/drop-off/timeslot/list`
**Get list of time slots for updating warehouse with drop-off shipment**  
operationId: `WarehouseFbsUpdateDropOffTimeslotList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `drop_off_point_id` | integer | ✓ | Drop-off point identifier. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: List of time slots
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `timeslots` | array[v1WarehouseFbsUpdateDropOffTimeslotListResponseTimeslot] |  | List of time slots. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/create/pick-up/timeslot/list`
**Get list of time slots for creating warehouse with pick-up shipment**  
operationId: `WarehouseFbsCreatePickUpTimeslotList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `address_coordinates` | `v1WarehouseFbsCreatePickUpTimeslotListRequestAddressCoordinates` | ✓ |  |
| `is_kgt` | boolean | ✓ | `true` if the product is bulky.  |

**响应 200**: List of time slots
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `is_pickup_supported` | boolean |  | `true` if pick-up shipment is supported.  |
| `timeslots` | array[v1WarehouseFbsCreatePickUpTimeslotListResponseTimeslot] |  | List of time slots. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/update/pick-up/timeslot/list`
**Get list of time slots for updating warehouse with pick-up shipment**  
operationId: `WarehouseFbsUpdatePickUpTimeslotList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: List of time slots
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `timeslots` | array[v1WarehouseFbsUpdatePickUpTimeslotListResponseTimeslot] |  | List of time slots. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/create`
**Create a warehouse**  
operationId: `WarehouseAPI_CreateWarehouseFBS`  

If you create a warehouse with delivery to a drop-off point, use the [/v1/warehouse/fbs/create/drop-off/list](#operation/WarehouseAPI_ListDropOffPointsForCreateFBSWarehouse) method to get a list of points.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `address_coordinates` | `CreateWarehouseFBSRequestAddressCoordinates` | ✓ |  |
| `cut_in_time` | integer | ✓ | Order acceptance time in minutes. For example, if you pass `3000`, order acceptance finishes in 50 h |
| `drop_off_point_id` | integer |  | Drop-off point identifier. |
| `first_mile_type` | `CreateWarehouseFBSRequestFirstMileTypeEnum` | ✓ |  |
| `is_kgt` | boolean | ✓ | `true` if the product is bulky.  |
| `name` | string | ✓ | Warehouse name. |
| `options` | `CreateWarehouseFBSRequestOptions` |  |  |
| `phone` | string | ✓ | Warehouse phone number. Specify in the +7(XXX)XXX-XX-XX format. |
| `timeslot_id` | integer | ✓ | Time slot identifier. |
| `working_days` | array[CreateWarehouseFBSRequestWorkingDaysEnum] |  | Warehouse working days: - `MONDAY`, - `TUESDAY`, - `WEDNESDAY`, - `THURSDAY`, - `FRIDAY`, - `SATURDA |

**响应 200**: Warehouse created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string |  | Operation identifier for creating an FBS warehouse. To get the operation status, use the [/v1/wareho |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/update`
**Update warehouse**  
operationId: `UpdateWarehouseFBS`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `address_coordinates` | `v1UpdateWarehouseFBSRequestAddressCoordinates` | ✓ |  |
| `name` | string |  | Warehouse name. |
| `options` | `v1UpdateWarehouseFBSRequestOptions` |  |  |
| `phone` | string |  | Warehouse phone number. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |
| `working_days` | array[v1UpdateWarehouseFBSRequestWorkingDaysEnum] |  | Warehouse working days.  |

**响应 200**: Warehouse updated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string |  | Operation identifier. You can get the operation status using the [/v1/warehouse/operation/status](#o |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/pickup/courier/create`
**Create courier request for pickup shipments**  
operationId: `WarehouseFbsPickUpCourierCreate`  

The method allows you to schedule a courier pickup for shipments.

[Learn more about courier pickup under the FBS scheme in the Seller Knowledge Base](https://seller-edu.ozon.ru/fbs/ozon-logistika/otgruzka-kyruery)

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `warehouse_id` | integer | ✓ | Warehouse identifier.  To get a list of warehouses for pickup scheduling, use [/v1/warehouse/fbs/pic |

**响应 200**: Request created
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/pickup/courier/cancel`
**Cancel courier request for pickup shipments**  
operationId: `WarehouseFbsPickUpCourierCancel`  

The method allows you to cancel a scheduled courier arrival.

[Learn more about courier pickup under the FBS scheme in the Seller Knowledge Base](https://seller-edu.ozon.ru/fbs/ozon-logistika/otgruzka-kyruery)

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: Request canceled
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/first-mile/update`
**Update first mile**  
operationId: `UpdateWarehouseFBSFirstMile`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cut_in_time` | integer | ✓ | Order acceptance time in minutes. For example, if you pass `3000`, order acceptance finishes in 50 h |
| `drop_off_point_id` | integer |  | Order drop-off point identifier. Required if `first_mile_type = DROP_OFF`. |
| `first_mile_type` | `v1UpdateWarehouseFBSFirstMileRequestFirstMileTypeEnum` | ✓ |  |
| `timeslot_id` | integer | ✓ | Time slot identifier. |
| `warehouse_id` | integer | ✓ | Warehouse identifier. |

**响应 200**: First mile updated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string |  | Operation identifier. You can get the operation status using the [/v1/warehouse/operation/status](#o |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbs/pickup/history/list`
**Get history of shippings to couriers**  
operationId: `WarehouseFbsPickUpHistoryList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `filter` | `v1WarehouseFbsPickUpHistoryListRequestFilter` |  |  |
| `limit` | integer | ✓ | Number of values per page. |

**响应 200**: Shipping history
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1WarehouseFbsPickUpHistoryListResponseResult` |  |  |
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

### POST `/v1/warehouse/fbs/pickup/planning/list`
**Get warehouse list for courier delivery planning**  
operationId: `WarehouseFbsPickUpPlanningList`  

To create a shipment, use the [/v1/warehouse/fbs/pickup/courier/create](#operation/WarehouseFbsPickUpCourierCreate) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Warehouse list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1WarehouseFbsPickUpPlanningListResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/polygon/create`
**Create delivery polygon**  
operationId: `PolygonAPI_CreatePolygon`  

You can link a polygon to the delivery method.

Create a polygon getting its coordinates on https://geojson.io: mark at least 3 points on the map and connect them.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `coordinates` | string | ✓ | Delivery polygon coordinates in `[[[lat long]]]` format.  |

**响应 200**: Polygon created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `polygon_id` | integer |  | Polygon identifier. |
**响应 400**: Invalid parameter
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error message:    - `coordinates not provided`—you didn't pass coordinates;   - `invalid coordinates |
**响应 403**: Access denied
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/polygon/bind`
**Link delivery method to a delivery polygon**  
operationId: `PolygonAPI_BindPolygon`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `delivery_method_id` | integer | ✓ | Delivery method identifier. |
| `polygons` | array[PolygonBindRequestpolygon] | ✓ | Polygons list. |
| `warehouse_location` | `PolygonBindRequestwh_location` | ✓ |  |

**响应 200**: Success
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