# 物流与配送 API

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

Methods in the Ozon Logistics section require an <a href="#tag/OAuth-token"><b>OAuth token</b></a> in a private or public application.

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/delivery/check` | Check delivery availability for customer |
| POST | `/v2/delivery/checkout` | Get available delivery options |
| POST | `/v1/delivery/map` | Display points on map |
| POST | `/v1/delivery/point/info` | Get pick-up point information |
| POST | `/v1/delivery/point/list` | Get pick-up point list |

---

## 接口详情


### POST `/v1/delivery/check`
**Check delivery availability for customer**  
operationId: `DeliveryCheck`  

Checks availability of Ozon delivery for customers. It doesn't take into account purchase amount limits, product categories, or geographic restrictions.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `client_phone` | string | ✓ | Customer phone number. |

**响应 200**: Success
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `is_possible` | boolean |  | `true` if delivery is available.  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/delivery/checkout`
**Get available delivery options**  
operationId: `DeliveryCheckout`  

Checks availability of product delivery to a specified address or pick-up point and displays delivery times.

Check product availability and routes during checkout to calculate delivery times.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `buyer_phone` | string |  | Customer phone number. |
| `delivery_schema` | `v2DeliveryCheckoutRequestV2DeliverySchemaEnum` |  |  |
| `delivery_type` | `v1DeliveryCheckoutRequestDeliveryType` |  |  |
| `items` | array[v1DeliveryCheckoutRequestItem] |  | Product information. |

**响应 200**: Success
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `splits` | array[DeliveryCheckoutResponseSplit] |  | Request result. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/delivery/map`
**Display points on map**  
operationId: `DeliveryMap`  

Returns pick-up points grouped into clusters within the area specified by the `viewport` parameter. 

Use the values from the `clusters.viewport` parameter to get a list of points or smaller clusters within a large cluster.

To get information about a specific pick-up point, use the [/v1/delivery/point/info](#operation/DeliveryPointInfo) method.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `viewport` | `v1DeliveryMapRequestViewport` |  |  |
| `zoom` | integer |  | Map scale. |

**响应 200**: Success
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `clusters` | array[DeliveryMapResponseCluster] |  | Clusters. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/delivery/point/info`
**Get pick-up point information**  
operationId: `DeliveryPointInfo`  

Returns information about pick-up points.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `map_point_ids` | array[string] |  | Identifiers of map points. |

**响应 200**: Pick-up point information
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `points` | array[v1DeliveryPointInfoResponsePoint] |  | Pick-up point information. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/delivery/point/list`
**Get pick-up point list**  
operationId: `DeliveryAPI_DeliveryPointList`  

Returns coordinates of all pick-up points without grouping them into clusters.

**请求体** (`application/json`):

```json
{"type": "object"}
```

**响应 200**: Pick-up point list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `points` | array[v1DeliveryPointListResponsePoint] |  | Pick-up points. |

---