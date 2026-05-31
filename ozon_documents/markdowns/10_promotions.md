# 促销活动 API

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

To promote your products, participate in special offers that Ozon holds for customers.

Learn more about special offers in [Help Center](https://docs.ozon.ru/global/en/promotion/marketing/promo/).

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/v1/actions` | Available special offers |
| POST | `/v1/actions/candidates` | Products that can participate in a special offer |
| POST | `/v1/actions/products` | Products in a special offer |
| POST | `/v1/actions/products/activate` | Add products to special offer |
| POST | `/v1/actions/products/deactivate` | Remove products from special offer |
| POST | `/v1/actions/discounts-task/list` | List of discount requests |
| POST | `/v1/actions/discounts-task/approve` | Approve a discount request |
| POST | `/v1/actions/discounts-task/decline` | Decline a discount request |
| POST | `/v1/seller-actions/create/discount` | Create special offer with "Discount" mechanics |
| POST | `/v1/seller-actions/create/discount-with-condition` | Create special offer with "Discount of order amount" mechanics |
| POST | `/v1/seller-actions/create/installment` | Create special offer with "Interest-free installment" mechanics |
| POST | `/v1/seller-actions/create/multi-level-discount` | Create special offer with "Multi-level discount from the amount" mechanics |
| POST | `/v1/seller-actions/create/ozon-card-discount` | Create special offer with "Increased discount with Ozon Bank card" mechanics |
| POST | `/v1/seller-actions/create/voucher` | Create special offer with "Discount by promo code" mechanics |
| POST | `/v1/seller-actions/update/discount` | Update special offer with "Discount" mechanic |
| POST | `/v1/seller-actions/update/discount-with-condition` | Update special offer with "Discount of order amount" mechanic |
| POST | `/v1/seller-actions/update/installment` | Update special offer with "Interest-free installment" mechanic |
| POST | `/v1/seller-actions/update/multi-level-discount` | Update special offer with "Multi-level discount from the total amount" mechanic |
| POST | `/v1/seller-actions/update/ozon-card-discount` | Update special offer with "Increased discount with Ozon Bank card" mechanic |
| POST | `/v1/seller-actions/update/voucher` | Update special offer with "Discount by promo code" mechanic |
| POST | `/v1/seller-actions/products/add` | Add products to special offer |
| POST | `/v1/seller-actions/products/candidates` | Get list of products that can participate in special offer |
| POST | `/v1/seller-actions/products/delete` | Remove products from special offer |
| POST | `/v1/seller-actions/products/list` | Get list of products in special offer |
| POST | `/v1/seller-actions/archive` | Archive special offer |
| POST | `/v1/seller-actions/change-activity` | Enable or disable special offer |
| POST | `/v1/seller-actions/list` | Get list of special offers |
| POST | `/v1/seller-actions/voucher/get` | Get file with promo codes in CSV format |
| POST | `/v1/chat/send/message` | Send message |
| POST | `/v1/chat/start` | Create a new chat |
| POST | `/v2/chat/read` | Mark messages as read |
| POST | `/v1/analytics/data` | Analytics data |
| POST | `/v1/analytics/product-queries` | Get details on your product queries |
| POST | `/v1/analytics/product-queries/details` | Get query details by product |
| POST | `/v1/finance/realization/by-day` | Sales report per day |
| POST | `/v1/search-queries/text` | Get list of search queries by text |
| POST | `/v1/search-queries/top` | Get list of popular search queries |
| POST | `/v1/product/prices/details` | Get details on product prices |

---

## 接口详情


### GET `/v1/actions`
**Available special offers**  

A method for getting a list of Ozon special offers that you can participate in.

[Learn more about Ozon special offers](https://docs.ozon.ru/global/en/promotion/big-promotions/rasprodazha/)

**响应 200**: Special offers list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[GetSellerActionsV1ResponseAction] |  | Method result. |
**响应 default**: An unexpected error response
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/actions/candidates`
**Products that can participate in a special offer**  
operationId: `PromosCandidates`  

A method for getting a list of products that can participate in the special offer by the special offer identifier.
<br>
<aside class="warning">
Starting May 5, 2025, the <tt>offset<tt> pagination parameter will be disabled. Switch to the <tt>last_id<tt> parameter.
</aside>

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | number |  | Special offer identifier. You can get it using the [/v1/actions](#operation/Promos) method. |
| `limit` | number |  | Number of values in the response. The default value is 100. |
| `offset` | number |  | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |
| `last_id` | number |  | Identifier of the last value on the page. Leave this field blank in the first request. |

**响应 200**: Products list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `seller_apiGetSellerProductV1ResponseResult` |  |  |
**响应 default**: An unexpected error response
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/actions/products`
**Products in a special offer**  
operationId: `PromosProducts`  

A method for getting the list of products participating in the special offer by its identifier.
<br>
<aside class="warning">
Starting May 5, 2025, the <tt>offset<tt> pagination parameter will be disabled. Switch to the <tt>last_id<tt> parameter.
</aside>

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | number |  | Special offer identifier. You can get it using the [/v1/actions](#operation/Promos) method. |
| `limit` | number |  | Number of values in the response. The default value is 100. |
| `offset` | number |  | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |
| `last_id` | number |  | Identifier of the last value on the page. Leave this field blank in the first request. |

**响应 200**: Products list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `seller_apiGetSellerProductV1ResponseResult` |  |  |
**响应 default**: An unexpected error response
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/actions/products/activate`
**Add products to special offer**  
operationId: `PromosProductsActivate`  

A method for adding products to an available special offer.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | number | ✓ | Special offer identifier. You can get it using the [/v1/actions](#operation/Promos) method. |
| `products` | array[seller_apiProductPrice] | ✓ | Product list. |

**响应 200**: Products added to the special offer
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `seller_apiProductV1ResponseResult` |  |  |
**响应 default**: An unexpected error response
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/actions/products/deactivate`
**Remove products from special offer**  
operationId: `PromosProductsDeactivate`  

A method for removing products from the special offer.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | number | ✓ | Special offer identifier. You can get it using the [/v1/actions](#operation/Promos) method. |
| `product_ids` | array[number] | ✓ | List of products identifiers. |

**响应 200**: Products removed from the special offer
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `seller_apiProductV1ResponseResultDeactivate` |  |  |
**响应 default**: An unexpected error response
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/actions/discounts-task/list`
**List of discount requests**  
operationId: `promos_task_list`  

<aside class="warning">
 Method is deprecated and will be disabled. Switch to the new version <a href="#operation/GetDiscountTaskListV2">/v2/actions/discounts-task/list</a>.
</aside> 

 Method for getting a list of products that customers want to buy with discount.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `status` | `v1DiscountTaskStatus` | ✓ |  |
| `page` | integer | ✓ | Page number from which you want to download the list of discount requests. |
| `limit` | integer | ✓ | The maximum number of requests on a page. |

**响应 200**: List of discount requests
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v1GetDiscountTaskListResponseTask] |  | List of requests. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/actions/discounts-task/approve`
**Approve a discount request**  
operationId: `promos_task_approve`  

You can approve applications in statuses:
- `NEW`—new,
- `SEEN`—viewed.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `tasks` | array[v1ApproveDiscountTasksRequestTask] | ✓ | List of discount requests. |

**响应 200**: Applications approved
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1ApproveDeclineDiscountTasksResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/actions/discounts-task/decline`
**Decline a discount request**  
operationId: `promos_task_decline`  

You can decline applications in statuses:
- `NEW`—new,
- `SEEN`—viewed.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `tasks` | array[v1DeclineDiscountTasksRequestTask] | ✓ | List of discount requests. |

**响应 200**: Applications declined
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1ApproveDeclineDiscountTasksResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/create/discount`
**Create special offer with "Discount" mechanics**  
operationId: `SellerActionsCreateDiscount`  

<aside class="warning">
Not available for sellers from CIS.
</aside>

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_end` | string | ✓ | Date and time when the special offer ends. |
| `date_start` | string | ✓ | Date and time when the special offer starts. |
| `min_action_percent` | number | ✓ | Minimum discount percentage. |
| `title` | string |  | Special offer name. |

**响应 200**: Special offer created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/create/discount-with-condition`
**Create special offer with "Discount of order amount" mechanics**  
operationId: `SellerActionsCreateDiscountWithCondition`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_end` | string | ✓ | Date and time when the special offer ends. |
| `date_start` | string | ✓ | Date and time when the special offer starts. |
| `discount_type` | `v1SellerActionsCreateDiscountWithConditionRequestDiscountTypeEnum` | ✓ |  |
| `discount_value` | number | ✓ | Discount size. |
| `min_order_amount` | number | ✓ | Order amount from which the discount applies. |
| `title` | string |  | Special offer name. |

**响应 200**: Special offer created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/create/installment`
**Create special offer with "Interest-free installment" mechanics**  
operationId: `SellerActionsCreateInstallment`  

Installment period is 6 months.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_start` | string | ✓ | Date and time when the special offer starts. |
| `title` | string | ✓ | Special offer name. |

**响应 200**: Special offer created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/create/multi-level-discount`
**Create special offer with "Multi-level discount from the amount" mechanics**  
operationId: `SellerActionsCreateMultiLevelDiscount`  

Products are added to the special offer automatically, you don't need to use the [/v1/seller-actions/products/add](#operation/SellerActionsProductsAdd) method.
 
You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_end` | string | ✓ | Date and time when the special offer ends. |
| `date_start` | string | ✓ | Date and time when the special offer starts. |
| `discount_levels` | array[v1SellerActionsCreateMultiLevelDiscountRequestDiscountLevel] | ✓ | Discount levels. |
| `discount_type` | `v1SellerActionsCreateMultiLevelDiscountRequestDiscountTypeEnum` | ✓ |  |
| `is_legal_entities_segment` | boolean |  | `true`, if the special offer is for legal entities only.  |
| `title` | string |  | Special offer name. |

**响应 200**: Special offer created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/create/ozon-card-discount`
**Create special offer with "Increased discount with Ozon Bank card" mechanics**  
operationId: `SellerActionsCreateOzonCardDiscount`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_end` | string | ✓ | Date and time when the special offer ends. |
| `date_start` | string | ✓ | Date and time when the special offer starts. |
| `discount_value` | number | ✓ | Discount size. |
| `title` | string | ✓ | Special offer name. |

**响应 200**: Special offer created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/create/voucher`
**Create special offer with "Discount by promo code" mechanics**  
operationId: `SellerActionsCreateVoucher`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `budget` | integer | ✓ | Special offer budget. If the budget runs out, the special offer stops. |
| `date_end` | string | ✓ | Date and time when the special offer ends. |
| `date_start` | string | ✓ | Date and time when the special offer starts. |
| `discount_type` | `v1SellerActionsCreateVoucherRequestDiscountTypeEnum` | ✓ |  |
| `discount_value` | number | ✓ | Discount size. |
| `title` | string | ✓ | Special offer name. |
| `user_ids` | array[string] |  | Identifiers of users who have access to the promo code. |
| `voucher_parameters` | `v1SellerActionsCreateVoucherRequestVoucherParameter` | ✓ |  |

**响应 200**: Special offer created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/update/discount`
**Update special offer with "Discount" mechanic**  
operationId: `SellerActionsUpdateDiscount`  

<aside class="warning">
Not available for sellers from CIS.
</aside>

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |
| `action_parameters` | `v1SellerActionsUpdateDiscountRequestActionParameters` |  |  |

**响应 200**: Special offer updated
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

### POST `/v1/seller-actions/update/discount-with-condition`
**Update special offer with "Discount of order amount" mechanic**  
operationId: `SellerActionsUpdateDiscountWithCondition`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |
| `action_parameters` | `v1SellerActionsUpdateDiscountWithConditionRequestActionParameters` |  |  |

**响应 200**: Special offer updated
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

### POST `/v1/seller-actions/update/installment`
**Update special offer with "Interest-free installment" mechanic**  
operationId: `SellerActionsUpdateInstallment`  

The installment period is 6 months.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |
| `action_parameters` | `v1SellerActionsUpdateInstallmentRequestActionParameters` |  |  |

**响应 200**: Special offer updated
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

### POST `/v1/seller-actions/update/multi-level-discount`
**Update special offer with "Multi-level discount from the total amount" mechanic**  
operationId: `SellerActionsUpdateMultiLevelDiscount`  

Products are added to the special offer automatically. You don't need to use the [/v1/seller-actions/products/add](#operation/SellerActionsProductsAdd) method.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |
| `action_parameters` | `v1SellerActionsUpdateMultiLevelDiscountRequestActionParameters` |  |  |

**响应 200**: Special offer updated
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

### POST `/v1/seller-actions/update/ozon-card-discount`
**Update special offer with "Increased discount with Ozon Bank card" mechanic**  
operationId: `SellerActionsUpdateOzonCardDiscount`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |
| `action_parameters` | `v1SellerActionsUpdateOzonCardDiscountRequestActionParameters` |  |  |

**响应 200**: Special offer updated
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

### POST `/v1/seller-actions/update/voucher`
**Update special offer with "Discount by promo code" mechanic**  
operationId: `SellerActionsUpdateVoucher`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera/) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer |  | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |
| `action_parameters` | `v1SellerActionsUpdateVoucherRequestActionParameters` |  |  |

**响应 200**: Special offer updated
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

### POST `/v1/seller-actions/products/add`
**Add products to special offer**  
operationId: `SellerActionsProductsAdd`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer | ✓ | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |
| `products` | array[v1SellerActionsProductsAddRequestProduct] | ✓ | Product details. |

**响应 200**: Products added
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/products/candidates`
**Get list of products that can participate in special offer**  
operationId: `SellerActionsProductsCandidates`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer | ✓ | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |
| `cursor` | integer |  | Cursor for the next data sample. |
| `limit` | integer | ✓ | Maximum number of values in the response. |

**响应 200**: List of products
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | integer |  | Cursor for the next data sample. |
| `has_next` | boolean |  | Indication that only part of values was returned in the response: - `true`: make a request with a ne |
| `products` | array[v1SellerActionsProductsCandidatesResponseProduct] |  | Product details. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/products/delete`
**Remove products from special offer**  
operationId: `SellerActionsProductsDelete`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer | ✓ | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |
| `skus` | array[string] | ✓ | Product identifiers in the Ozon system, SKU. |

**响应 200**: Products deleted
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/products/list`
**Get list of products in special offer**  
operationId: `SellerActionsProductsList`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer | ✓ | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |
| `cursor` | integer |  | Cursor for the next data sample. |
| `limit` | integer | ✓ | Maximum number of values in the response. |

**响应 200**: List of products
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | integer |  | Cursor for the next data sample. |
| `has_next` | boolean |  | Indication that only part of values was returned in the response: - `true`: make a request with a ne |
| `products` | array[v1SellerActionsProductsListResponseProduct] |  | Product details. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/archive`
**Archive special offer**  
operationId: `SellerActionsArchive`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer | ✓ | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |

**响应 200**: Special offer archived
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/change-activity`
**Enable or disable special offer**  
operationId: `SellerActionsChangeActivity`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer | ✓ | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |
| `is_turn_on` | boolean | ✓ | `true` to enable the special offer.  |

**响应 200**: Success
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/list`
**Get list of special offers**  
operationId: `SellerActionsList`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_ids` | array[string] |  | Special offer identifiers. |
| `action_type` | array[SellerActionsListRequestActionTypeEnum] |  | Special offer mechanics:   - `DISCOUNT`: discount;   - `VOUCHER_DISCOUNT`: discount via promo code;  |
| `limit` | integer | ✓ | Number of values per page. |
| `offset` | integer |  | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |
| `search` | string |  | Search by special offer name. |
| `status` | array[SellerActionsListRequestStatusEnum] |  | Special offer status.  |

**响应 200**: List of special offers
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `actions` | array[SellerActionsListResponseAction] |  | List of special offers. |
| `total` | integer |  | Total number of special offers. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/seller-actions/voucher/get`
**Get file with promo codes in CSV format**  
operationId: `SellerActionsVoucherGet`  

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1872-Novye-metody-dlia-raboty-s-aktsiiami-sellera) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `action_id` | integer | ✓ | Special offer identifier. Get the parameter value using the [/v1/seller-actions/list](#operation/Sel |

**响应 200**: File with promo codes
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file` | string |  | Link to the CSV file with promo codes. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/chat/send/message`
**Send message**  
operationId: `ChatAPI_ChatSendMessage`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions) or Premium Pro subscription.

Sends a message to an existing chat by its identifier.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `chat_id` | string | ✓ | Chat identifier. |
| `text` | string | ✓ | Message text in the plain text format from 1 to 1000 symbols. |

**响应 200**: Message is sent
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | string |  | Method result. |
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

### POST `/v1/chat/start`
**Create a new chat**  
operationId: `ChatAPI_ChatStart`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions) or Premium Pro subscription.

Creates a new chat on the shipment with the customer. For example, to clarify the address or the product model.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `posting_number` | string | ✓ | Shipment identifier. |

**响应 200**: New chat was created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `ChatStartResponseResult` |  |  |
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

### POST `/v2/chat/read`
**Mark messages as read**  
operationId: `ChatAPI_ChatReadV2`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions) or Premium Pro subscription.

A method for marking the selected message and messages before it as read.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `chat_id` | string | ✓ | Chat identifier. |
| `from_message_id` | integer |  | Message identifier. |

**响应 200**: Success
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `unread_count` | integer |  | Number of unread messages in the chat. |
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

### POST `/v1/analytics/data`
**Analytics data**  
operationId: `AnalyticsAPI_AnalyticsGetData`  

Specify the period and metrics that are required. The response will contain analytical data grouped by the `dimensions` parameter.

There are restrictions for sellers without the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions) or Premium Pro subscription:
- data is available for the last 3 months,
- some of the data grouping methods and metrics aren't available.

There are no restrictions for sellers with [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions) or Premium Pro subscription.

You can use the method for no more than 1 request per minute.
Match

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string | ✓ | Date from which the data will be in the report. |
| `date_to` | string | ✓ | Date up to which the data will be in the report. |
| `dimension` | array[seller_serviceanalyticsDimension] | ✓ | Data grouping in the report.  Data grouping available to all sellers:   - `unknownDimension`—unknown |
| `filters` | array[analyticsFilter] |  | Filters. |
| `limit` | integer | ✓ | Number of items in the response:   - maximum is 1000,   - minimum is 1.  |
| `metrics` | array[analyticsMetric] | ✓ | Specify up to 14 metrics. If there are more, you will get an error with the `InvalidArgument` code.  |
| `offset` | integer |  | Number of elements to be skipped in the response. For example, if `offset = 10`, the response starts |
| `sort` | array[analyticsSorting] |  | Report sorting settings. |

**响应 200**: Analytics data
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `AnalyticsGetDataResponseResult` |  |  |
| `timestamp` | string |  | Report creation time. |
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

### POST `/v1/analytics/product-queries`
**Get details on your product queries**  
operationId: `AnalyticsAPI_AnalyticsProductQueries`  

Use the method to get data about your product queries. Full analytics is available with the [Premium](https://docs.ozon.ru/global/en/promotion/subscriptions/premium/), [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions/premium-plus/), or Premium Pro subscription. Without subscription, you can see a part of the metrics. The method is similar to the **Products in Search → Queries for my product** tab in your personal account.

You can view analytics by queries for certain dates. To do this, specify the interval in the `date_from` and `date_to` fields. Data for the last month a

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string | ✓ | Date when analytics generation starts. |
| `date_to` | string |  | Date when analytics generation ends. |
| `page` | integer |  | Number of the page returned in the request. |
| `page_size` | integer | ✓ | Number of elements on the page. |
| `skus` | array[string] | ✓ | List of SKUs—product identifiers in the Ozon system. Analytics on requests is returned for them. Max |
| `sort_by` | `AnalyticsProductQueriesRequestSortBy` |  |  |
| `sort_dir` | `AnalyticsProductQueriesRequestSortDir` |  |  |

**响应 200**: Details on your product queries
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `analytics_period` | `AnalyticsProductQueriesResponseAnalyticsPeriod` |  |  |
| `items` | array[v1AnalyticsProductQueriesResponseItem] |  | Product list. |
| `page_count` | integer |  | Number of pages. |
| `total` | integer |  | Total number of queries. |
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

### POST `/v1/analytics/product-queries/details`
**Get query details by product**  
operationId: `AnalyticsAPI_AnalyticsProductQueriesDetails`  

Use the method to get details on product-specific queries. Full analytics is available with [Premium](https://docs.ozon.ru/global/en/promotion/subscriptions/premium/), [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions/premium-plus/), or Premium Pro subscription. Without a subscription, you can view a part of the metrics. Method is similar to viewing product details in the **Products in search → Requests for my product** tab in your personal account.

You can view analytics by queries for certain dates. To do this, specify the interval in the `date_from` and `date_to` fields

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `date_from` | string | ✓ | Date when analytics generation starts. |
| `date_to` | string |  | Date when analytics generation ends. |
| `limit_by_sku` | integer | ✓ | Available number of queries per SKU. Maximum is 15 queries. |
| `page` | integer |  | Number of the page returned in the request. |
| `page_size` | integer | ✓ | Number of elements on the page. |
| `skus` | array[string] | ✓ | Product identifiers in the Ozon system, SKU. They will return analytics on the queries. Maximum is 1 |
| `sort_by` | `v1AnalyticsProductQueriesDetailsRequestSortBy` |  |  |
| `sort_dir` | `v1AnalyticsProductQueriesDetailsRequestSortDir` |  |  |

**响应 200**: Details of specific product queries
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `analytics_period` | `v1AnalyticsProductQueriesDetailsResponseAnalyticsPeriod` |  |  |
| `page_count` | integer |  | Number of pages. |
| `queries` | array[AnalyticsProductQueriesDetailsResponseQuery] |  | List of queries. |
| `total` | integer |  | Total number of queries. |
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

### POST `/v1/finance/realization/by-day`
**Sales report per day**  
operationId: `FinanceAPI_GetRealizationByDayReportV1`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions) or Premium Pro subscription.

Returns sales amount data from the [sales report](#operation/FinanceAPI_GetRealizationReportV2) per day. Canceled or non-purchased products aren't included. Data is available for a maximum of 32 calendar days from the current date.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `day` | integer | ✓ | Day. |
| `month` | integer | ✓ | Month. |
| `year` | integer | ✓ | Year. |

**响应 200**: Sales report per day
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `rows` | array[GetRealizationReportByDayResponseRow] |  | Report table. |
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

### POST `/v1/search-queries/text`
**Get list of search queries by text**  
operationId: `SearchQueriesAPI_SearchQueriesText`  

Available for sellers with the Premium Pro subscription.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | string | ✓ | Number of values per page. |
| `offset` | string | ✓ | Number of elements to be skipped in the response. |
| `sort_by` | `SearchQueriesTextRequestSortBy` |  |  |
| `sort_dir` | `SearchQueriesTextRequestSortDir` |  |  |
| `text` | string | ✓ | Text search. |

**响应 200**: Search query list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `offset` | string |  | Number of search queries per page. |
| `search_queries` | array[v1SearchQueriesTextResponseSearchQuery] |  | Search query details. |
| `total` | string |  | Total number of search queries. |
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

### POST `/v1/search-queries/top`
**Get list of popular search queries**  
operationId: `SearchQueriesAPI_SearchQueriesTop`  

Available for sellers with the Premium Pro subscription.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | string | ✓ | Number of values per page. |
| `offset` | string | ✓ | Number of elements to be skipped in the response. |

**响应 200**: List of popular search queries
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `offset` | string |  | Number of search queries per page. |
| `search_queries` | array[v1SearchQueriesTopResponseSearchQuery] |  | Search query details. |
| `total` | string |  | Total number of search queries. |
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

### POST `/v1/product/prices/details`
**Get details on product prices**  
operationId: `ProductPricesDetails`  

Available for sellers with the Premium Pro subscription.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `skus` | array[string] | ✓ | List of SKUs. |

**响应 200**: Product prices details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `prices` | array[v1ProductPricesDetailsResponsePrice] |  | Product prices. |
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