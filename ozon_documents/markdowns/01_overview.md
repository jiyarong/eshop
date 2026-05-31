# 概览与认证

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

### What is Ozon Seller API

Ozon Seller API is a software interface for working with the Ozon marketplace and exchanging information between the seller's system and Ozon.

Seller API methods allow you to change store data, such as product stocks and prices, and retrieve data, such as information about returns or a list of warehouses.

Working with the API consists of sending a request and receivi

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/roles` | Get a list of roles and methods based on the API key |
| POST | `/v1/seller/info` | Get information about seller account |
| POST | `/v1/seller/ozon-logistics/info` | Get information about connecting to Ozon Logistics |
| POST | `/v1/rating/summary` | Get information on current seller ratings |
| POST | `/v1/rating/history` | Get information on seller ratings for the period |
| POST | `/v1/rating/index/fbs/info` | Get FBS and rFBS error index |
| POST | `/v1/rating/index/fbs/posting/list` | List of shipments that affected FBS and rFBS error index |

---

## 接口详情


### POST `/v1/roles`
**Get a list of roles and methods based on the API key**  
operationId: `AccessAPI_RolesByToken`  

Method for getting information about roles and methods available for your API key.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: List of roles and methods
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `expires_at` | string |  | Date and time when the key expires. |
| `roles` | array[RolesByTokenResponseRoles] |  | Information about available roles and methods. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller/info`
**Get information about seller account**  
operationId: `SellerAPI_SellerInfo`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Seller account details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `company` | `SellerInfoResponseCompany` |  |  |
| `ratings` | array[SellerInfoResponseRating] |  | Rating list. |
| `subscription` | `SellerInfoResponseSubscription` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller/ozon-logistics/info`
**Get information about connecting to Ozon Logistics**  
operationId: `SellerAPI_SellerOzonLogisticsInfo`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Information about connecting to Ozon Logistics
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `available_schemas` | array[SellerOzonLogisticsInfoResponseAvailableSchemasEnum] |  | Available scheme type. |
| `ozon_logistics_enabled` | boolean |  | `true` if Ozon Logistics is connected.  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/rating/summary`
**Get information on current seller ratings**  
operationId: `RatingAPI_RatingSummaryV1`  

Seller rating on the following metrics: price index, delivery on time, cancellation rate, complaints, and other.
Matches the **Ratings → Seller ratings** section in your personal account.

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: Information on ratings
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `groups` | any |  | Rating groups list. |
| `localization_index` | any |  | Localization index details. If you had no sales in the last 14 days, the parameter fields will be em |
| `penalty_score_exceeded` | boolean |  | An indication that the penalty points balance is exceeded. |
| `premium` | boolean |  | An indication that you have the [Premium](https://seller-edu.ozon.ru/seller-rating/about-rating/prem |
| `premium_plus` | boolean |  | An indication that you have the [Premium Plus](https://seller-edu.ozon.ru/seller-rating/about-rating |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/rating/history`
**Get information on seller ratings for the period**  
operationId: `RatingAPI_RatingHistoryV1`  

Filtered information about ratings for a given period.
Matches the **Ratings → Seller ratings** section in your personal account.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string | ✓ | Period start. |
| `date_to` | string | ✓ | Period end. |
| `ratings` | any | ✓ | Filter by rating.  Ratings for which you want to get a value for the period:  - `rating_on_time`: th |
| `with_premium_scores` | boolean |  | Indication that the response should contain information about Premium program penxalty points. |

**响应 200**: Information on ratings
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `premium_scores` | any |  | Information on the Premium program penalty points. |
| `ratings` | any |  | Information on the seller ratings. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/rating/index/fbs/info`
**Get FBS and rFBS error index**  
operationId: `RatingAPI_GetFBSRatingIndexInfoV1`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Error index
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `currency_code` | string |  | Currency code of error processing cost. |
| `defects` | array[GetFBSRatingIndexInfoV1ResponseIndexDynamics] |  | Error index by day. |
| `index` | number |  | Error index value per period. |
| `period_from` | string |  | Billing period start date in the `YYYY-MM-DD` format. |
| `period_to` | string |  | Billing period end date in the `YYYY-MM-DD` format. |
| `processing_costs_sum` | number |  | Error processing costs per period. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/rating/index/fbs/posting/list`
**List of shipments that affected FBS and rFBS error index**  
operationId: `RatingAPI_ListFBSRatingIndexPostingsV1`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `filter` | `ListFBSRatingIndexPostingsV1RequestFilter` | ✓ |  |
| `limit` | integer | ✓ | Number of values in the response. |

**响应 200**: Shipment list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `errors` | array[ListFBSRatingIndexPostingsV1ResponseError] |  | Shipments that affected the index. |
| `has_next` | boolean |  | `true` if not all shipments are returned in the response.  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---