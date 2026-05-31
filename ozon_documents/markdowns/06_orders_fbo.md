# FBO 订单 API（Ozon 仓发货）

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v2/posting/fbo/list` | Shipments list |
| POST | `/v2/posting/fbo/get` | Shipment details |
| POST | `/v1/posting/fbo/cancel-reason/list` | Shipments cancellation reasons by FBO scheme |
| POST | `/v1/supply-order/status/counter` | Number of supply requests by status |
| POST | `/v1/supply-order/bundle` | Supply or supply request contents |
| POST | `/v3/supply-order/list` | List of supply requests to the Ozon warehouse |
| POST | `/v3/supply-order/get` | Supply request details |
| POST | `/v1/supply-order/timeslot/get` | Supply time slots |
| POST | `/v1/supply-order/timeslot/update` | Update supply time slot |
| POST | `/v1/supply-order/timeslot/status` | Supply time slot status |
| POST | `/v1/supply-order/pass/create` | Specify driver and vehicle details |
| POST | `/v1/supply-order/pass/status` | Driver and vehicle details entry status |
| GET | `/v1/supplier/available_warehouses` | Ozon warehouses workload |
| POST | `/v1/cluster/list` | Information about clusters and their warehouses |
| POST | `/v1/warehouse/fbo/list` | Finding points to ship the supply |
| POST | `/v1/draft/create` | Create a supply request draft |
| POST | `/v1/draft/create/info` | Supply request draft details |
| POST | `/v1/draft/timeslot/info` | Available supply time slots |
| POST | `/v1/draft/supply/create` | Create a supply request from the draft |
| POST | `/v1/draft/supply/create/status` | Supply request creating details |
| POST | `/v1/supply-order/cancel` | Cancel supply request |
| POST | `/v1/supply-order/cancel/status` | Get status of canceled supply request |
| POST | `/v1/posting/cancel` | Cancel shipment from order |
| POST | `/v1/posting/cancel/status` | Check shipment cancellation status |
| POST | `/v1/posting/marks` | Get item labels from shipment |

---

## 接口详情


### POST `/v2/posting/fbo/list`
**Shipments list**  
operationId: `PostingAPI_GetFboPostingList`  

Returns a list of shipments for a specified period of time. You can additionally filter the shipments by their status.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `dir` | string |  | Sorting direction: - `ASC`—ascending, - `DESC`—descending.  |
| `filter` | `postingGetFboPostingListRequestFilter` | ✓ |  |
| `limit` | integer | ✓ | Number of values in the response. Maximum is 1000, minimum is 1. |
| `offset` | integer |  | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |
| `translit` | boolean |  | `true` if the address transliteration from Cyrillic to Latin is enabled.  |
| `with` | `postingFboPostingWithParams` |  |  |

**响应 200**: Shipments list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v2FboPostingV2] |  | Shipment list. |
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

### POST `/v2/posting/fbo/get`
**Shipment details**  
operationId: `PostingAPI_GetFboPosting`  

Returns information about the shipment by its identifier.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |
| `translit` | boolean |  | `true` if the address transliteration from Cyrillic to Latin is enabled.  |
| `with` | `postingFboPostingWithParams` |  |  |

**响应 200**: Shipment details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v2FboPosting` |  |  |
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

### POST `/v1/posting/fbo/cancel-reason/list`
**Shipments cancellation reasons by FBO scheme**  
operationId: `PostingAPI_GetPostingFboCancelReasonList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Shipment cancellation reasons
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `reasons` | array[v1CancelReasonListByOrderResponseReasonFbo] |  | Cancellation reason information. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/supply-order/status/counter`
**Number of supply requests by status**  
operationId: `SupplyOrderAPI_SupplyOrderStatusCounter`  

Returns the number of supply requests in a specific status.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: Request status and number of requests in this status
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | array[v1SupplyOrderStatusCounterResponseItem] |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/supply-order/bundle`
**Supply or supply request contents**  
operationId: `SupplyOrderBundle`  

Use the method for getting the contents of a supply or draft supply request. A single call to the method can get the contents of one supply or one draft supply request.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bundle_ids` | array[string] | ✓ | Identifiers of supply contents. You can get them using the[/v3/supply-order/get](#operation/SupplyOr |
| `is_asc` | boolean |  | `true`, to sort in ascending order.  |
| `item_tags_calculation` | `GetSupplyOrderBundleRequestItemTagsCalculation` |  |  |
| `last_id` | string |  | Identifier of the last SKU value on the page. |
| `limit` | integer | ✓ | Number of products on the page. |
| `query` | string |  | Search query, for example: by name, article code, or SKU.  |
| `sort_field` | `v1ItemSortField` |  |  |

**响应 200**: Supply contents
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | array[v1ItemResponse] |  | List of products in the supply request. |
| `total_count` | integer |  | Quantity of products in the request. |
| `has_next` | boolean |  | Indication that the response hasn't returned all products: - `true`: create another request with a d |
| `last_id` | string |  | Identifier of the last value on the page. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v3/supply-order/list`
**List of supply requests to the Ozon warehouse**  
operationId: `SupplyOrderList`  

Supply requests to a specific warehouse and through a [virtual distribution center (vDC)](https://seller-edu.ozon.ru/fbo/scheme-of-work/about#чем-отличаются-процессы-при-заявках-через-врц-и-напрямую-на-склад) are taken into account.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `SupplyOrderListRequestFilter` | ✓ |  |
| `last_id` | string |  | Last value identifier on the page. Leave this field empty for the first request.  To get the next va |
| `limit` | integer | ✓ | Number of values per page. |
| `sort_by` | `SupplyOrderListRequestSortByEnum` | ✓ |  |
| `sort_dir` | `SupplyOrderListRequestSortDirEnum` |  |  |

**响应 200**: List of supply requests
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `last_id` | string |  | Last value identifier on the page.  To get the next values, specify the received value in the `last_ |
| `order_ids` | array[string] |  | Supply request identifiers. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v3/supply-order/get`
**Supply request details**  
operationId: `SupplyOrderGet`  

Supply requests to a specific warehouse and through a [virtual distribution center (vDC)](https://seller-edu.ozon.ru/fbo/scheme-of-work/about#чем-отличаются-процессы-при-заявках-через-врц-и-напрямую-на-склад) are taken into account.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `order_ids` | array[string] | ✓ | Supply request identifiers. |

**响应 200**: Supply request details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `orders` | array[SupplyOrderGetResponseOrder] |  | List of supply requests. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/supply-order/timeslot/get`
**Supply time slots**  
operationId: `SupplyOrderAPI_GetSupplyOrderTimeslots`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_order_id` | integer | ✓ | Supply request identifier. |

**响应 200**: List of supply time slots
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `timeslots` | array[v1SupplyOrderTimeslot] |  | Supply time slot. |
| `timezone` | any |  | Time zone. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/supply-order/timeslot/update`
**Update supply time slot**  
operationId: `SupplyOrderAPI_UpdateSupplyOrderTimeslot`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_order_id` | integer | ✓ | Supply request identifier. |
| `timeslot` | `v1SupplyOrderTimeslot` | ✓ |  |

**响应 200**: Time slot updated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `errors` | array[v1UpdateTimeslotError] |  | Possible errors:    - `UNSPECIFIED`: no status specified;   - `INVALID_ORDER_STATE`: incorrect order |
| `operation_id` | string |  | Operation identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/supply-order/timeslot/status`
**Supply time slot status**  
operationId: `SupplyOrderAPI_GetSupplyOrderTimeslotStatus`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string | ✓ | Operation identifier. |

**响应 200**: Details status
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `errors` | array[v1UpdateTimeslotError] |  | Possible errors:    - `UNSPECIFIED`: no status specified;   - `INVALID_ORDER_STATE`: incorrect order |
| `status` | `v1GetSupplyOrderTimeslotStatusResponseStatus` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/supply-order/pass/create`
**Specify driver and vehicle details**  
operationId: `SupplyOrderAPI_SupplyOrderPassCreate`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `supply_order_id` | integer | ✓ | Supply request identifier. |
| `vehicle` | `v1VehicleInfo` | ✓ |  |

**响应 200**: Details specified
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error_reasons` | array[v1SetVehicleError] |  | Possible errors:   - `UNSPECIFIED`: no status specified;   - `INVALID_ORDER_STATE`: incorrect order  |
| `operation_id` | string |  | Operation identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/supply-order/pass/status`
**Driver and vehicle details entry status**  
operationId: `SupplyOrderAPI_SupplyOrderPassStatus`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string | ✓ | Operation identifier. |

**响应 200**: Status
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `errors` | array[v1SetVehicleError] |  | Possible errors: - `UNSPECIFIED`: no status specified; - `INVALID_ORDER_STATE`: incorrect order stat |
| `result` | `v1SupplyOrderPassStatusResponseStatus` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### GET `/v1/supplier/available_warehouses`
**Ozon warehouses workload**  
operationId: `SupplierAPI_SupplierAvailableWarehouses`  

Method returns a list of active Ozon warehouses with information about their average workload in the nearest future.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Warehouses workload information
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | any |  | Method result. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/cluster/list`
**Information about clusters and their warehouses**  
operationId: `SupplyDraftAPI_DraftClusterList`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cluster_ids` | array[string] |  | Clusters identifiers. |
| `cluster_type` | `v1ClusterType` | ✓ |  |

**响应 200**: Clusters details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `clusters` | array[v1DraftClusterListResponseCluster] |  | Cluster details. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/warehouse/fbo/list`
**Finding points to ship the supply**  
operationId: `SupplyDraftAPI_DraftGetWarehouseFboList`  

Use the method to find shipping points for cross-docking and direct supplies. 

You can view the addresses of all points on the map and in a table in the [Knowledge Base](https://seller-edu.ozon.ru/fbo/warehouses/adresa-skladov-fbo).

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter_by_supply_type` | array[v1CreateType] | ✓ | Supply type: - `CREATE_TYPE_CROSSDOCK`—cross-docking, - `CREATE_TYPE_DIRECT`—direct.  |
| `search` | string | ✓ | Search by warehouse name. To search for pick-up points, specify the full name.  |

**响应 200**: Warehouses details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `search` | array[DraftGetWarehouseFboListResponseSearch] |  | Warehouse search result. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/draft/create`
**Create a supply request draft**  
operationId: `SupplyDraftAPI_DraftCreate`  

<aside class="warning">
  Method is deprecated and disabled on March 16, 2026. Switch to the <a href="https://docs.ozon.ru/api/seller/#operation/DraftCrossdockCreate">/v1/draft/crossdock/create</a>, <a href="https://docs.ozon.ru/api/seller/#operation/DraftDirectCreate">/v1/draft/direct/create</a>, or <a href="https://docs.ozon.ru/api/seller/#operation/DraftMultiClusterCreate">/v1/draft/multi-cluster/create</a> methods.
</aside>

<aside class="warning">A supply request draft is available for 30 minutes.

You can create supply request drafts twice per minute and 50 times per hour.
The maximum nu

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cluster_ids` | array[string] |  | Cluster identifiers for the supply request. You can get them using the [/v1/cluster/list](#operation |
| `drop_off_point_warehouse_id` | integer |  | Shipping point identifier: pick-up point or sorting center. You can get it using the [/v1/warehouse/ |
| `items` | array[DraftCreateRequestItem] | ✓ | Products. |
| `type` | `v1CreateType` | ✓ |  |

**响应 200**: Supply draft created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string |  | Identifier of the supply request draft. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/draft/create/info`
**Supply request draft details**  
operationId: `SupplyDraftAPI_DraftCreateInfo`  

<aside class="warning">
  Method is deprecated and disabled on March 16, 2026. Switch to the <a href="https://docs.ozon.ru/api/seller/#operation/DraftCreateInfo">/v2/draft/create/info</a> method.
</aside>

<aside class="warning">
You can create supply request drafts twice per minute and 50 times per hour.
If you reach the limit, you get the 429 error.</aside>

Returns information about the created supply request draft. The response lists the placement warehouses in each selected cluster that accept all products.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string | ✓ | Unique identifier for generation of the supply request draft.  |

**响应 200**: Supply request draft details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `clusters` | array[draftv1Cluster] |  | Clusters. |
| `draft_id` | integer |  | Identifier of the supply request draft. |
| `errors` | array[v1CalculationError] |  | Errors. |
| `status` | `v1CalculationStatus` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/draft/timeslot/info`
**Available supply time slots**  
operationId: `SupplyDraftAPI_DraftTimeslotInfo`  

<aside class="warning">
  Method is deprecated and disabled on March 16, 2026. Switch to the <a href="https://docs.ozon.ru/api/seller/#operation/DraftTimeslotInfo">/v2/draft/timeslot/info</a> method.
</aside>

<aside class="warning">The supply request draft is available for 30 minutes.</aside>

Returns available supply time slots at final shipping warehouses. For cross-docking supplies, the response returns time slots of the shipping warehouse passed when creating the draft.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string | ✓ | Start date of the available supply time slots period. |
| `date_to` | string | ✓ | End date of the available supply time slots period.  The maximum period is 28 days from the current  |
| `draft_id` | integer | ✓ | Identifier of the supply request draft. You can get it using the [/v1/draft/create/info](#operation/ |
| `warehouse_ids` | array[string] | ✓ | Placement warehouse identifiers. |

**响应 200**: Supply time slot details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `drop_off_warehouse_timeslots` | array[v1DropOffWarehouse] |  | Warehouses supply time slots. |
| `requested_date_from` | string |  | Start date of the necessary period. |
| `requested_date_to` | string |  | End date of the necessary period. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/draft/supply/create`
**Create a supply request from the draft**  
operationId: `SupplyDraftAPI_DraftSupplyCreate`  

<aside class="warning">
  Method is deprecated and disabled on March 16, 2026. Switch to the <a href="https://docs.ozon.ru/api/seller/#operation/DraftSupplyCreate">/v2/draft/supply/create</a> method.
</aside>

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `draft_id` | integer | ✓ | Identifier of the supply request draft. |
| `timeslot` | `v1DayTimeSlot` |  |  |
| `warehouse_id` | integer | ✓ | Placement warehouse identifier. You can get it using the [/v1/draft/create/info](#operation/SupplyDr |

**响应 200**: Request created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string |  | Supply request identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/draft/supply/create/status`
**Supply request creating details**  
operationId: `SupplyDraftAPI_DraftSupplyCreateStatus`  

<aside class="warning">
  Method is deprecated and disabled on March 16, 2026. Switch to the <a href="https://docs.ozon.ru/api/seller/#operation/DraftSupplyCreateStatus">/v2/draft/supply/create/status</a> method.
</aside>

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string | ✓ | Supply request identifier. |

**响应 200**: Supply request creating details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error_messages` | array[string] |  | Requests creation errors. |
| `result` | `DraftSupplyCreateStatusResponseResult` |  |  |
| `status` | `v1DraftSupplyCreateStatus` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/supply-order/cancel`
**Cancel supply request**  
operationId: `SupplyOrderAPI_SupplyOrderCancel`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `order_id` | integer | ✓ | Supply request identifier. |

**响应 200**: Processing supply request cancellation
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string |  | Operation identifier for canceling the request. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/supply-order/cancel/status`
**Get status of canceled supply request**  
operationId: `SupplyOrderAPI_SupplyOrderCancelStatus`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `operation_id` | string | ✓ | Operation identifier for canceling the supply request. |

**响应 200**: Status of canceled supply request
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `error_reasons` | array[SupplyOrderCancelStatusResponseCancelOrderError] |  | Reason why the supply request can't be canceled:   - `INVALID_ORDER_STATE`: incorrect status of the  |
| `result` | `SupplyOrderCancelStatusResponseResult` |  |  |
| `status` | `v1SupplyOrderCancelStatusResponseStatus` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/posting/cancel`
**Cancel shipment from order**  
operationId: `PostingAPI_PostingCancel`  

Cancels a shipment within an order. Use the cancellation reason identifier `reasons.id` from the [/v1/cancel-reason/list-by-posting](#operation/CancelReasonAPI_CancelReasonListByPosting) method.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment number. |
| `reason_id` | integer | ✓ | Cancellation reason identifier. |
| `reason_message` | string |  | Additional cancellation details. |

**响应 200**: Cancellation status message
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `message` | string |  | Message. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/posting/cancel/status`
**Check shipment cancellation status**  
operationId: `PostingAPI_PostingCancelStatus`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string |  | Shipment identifier. |

**响应 200**: Shipment cancellation status
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `order_number` | string |  | Order number. |
| `posting_number` | array[string] |  | Shipment identifier. |
| `state` | string |  | Shipment cancellation status. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/posting/marks`
**Get item labels from shipment**  
operationId: `PostingAPI_PostingMarks`  

Returns item giveout statuses and "Chestny ZNAK" labeling codes for each shipment.

The method returns labeling codes of received items in the `issued_exemplars` parameter. Specify them in the receipt and remove them from circulation.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_numbers` | array[string] |  | Shipment identifiers. |

**响应 200**: List of shipment items with labels
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `invalid_postings` | array[string] |  | List of invalid shipment identifiers. |
| `issued_exemplars` | array[PostingMarksResponseIssuedExemplar] |  | List of product items given to customers. |
| `non_issued_exemplars` | array[PostingMarksResponseNonIssuedExemplar] |  | List of product items not given to customers. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---