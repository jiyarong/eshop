# 商品管理 API

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/description-category/tree` | Tree of product category and type |
| POST | `/v1/description-category/attribute` | Category characteristics list |
| POST | `/v1/description-category/attribute/values` | Characteristics value directory |
| POST | `/v1/description-category/attribute/values/search` | Search by reference values of a characteristic |
| POST | `/v3/product/import` | Create or update a product |
| POST | `/v1/product/import/info` | Get the product import status |
| POST | `/v1/product/import-by-sku` | Create a product by SKU |
| POST | `/v1/product/attributes/update` | Update product characteristics |
| POST | `/v1/product/pictures/import` | Upload and update product images |
| POST | `/v3/product/list` | List of products |
| POST | `/v1/product/rating-by-sku` | Get products' content rating by SKU |
| POST | `/v3/product/info/list` | Get a list of products by identifiers |
| POST | `/v4/product/info/attributes` | Get a description of the product characteristics |
| POST | `/v1/product/info/description` | Get product description |
| POST | `/v4/product/info/limit` | Product range limit, limits on product creation and update |
| POST | `/v1/product/update/offer-id` | Change product identifiers from the seller's system |
| POST | `/v1/product/archive` | Archive a product |
| POST | `/v1/product/unarchive` | Unarchive a product |
| POST | `/v2/products/delete` | Remove a product without an SKU from the archive |
| POST | `/v1/product/info/subscription` | Number of users subscribed to product availability alerts |
| POST | `/v1/product/related-sku/get` | Get related SKUs |
| POST | `/v2/product/pictures/info` | Get products images |
| POST | `/v1/product/info/wrong-volume` | List of products with incorrect VWC |
| POST | `/v1/barcode/add` | Bind barcodes to products |
| POST | `/v1/barcode/generate` | Generate barcodes for products |
| POST | `/v1/brand/company-certification/list` | List of certified brands |
| GET | `/v1/product/certificate/accordance-types` | List of accordance types (version 1) |
| GET | `/v2/product/certificate/accordance-types/list` | List of accordance types (version 2) |
| GET | `/v1/product/certificate/types` | Directory of document types |
| POST | `/v2/product/certification/list` | List of certified categories |
| POST | `/v1/product/certification/list` | List of certified categories |
| POST | `/v1/product/certificate/create` | Adding certificates for products |
| POST | `/v1/product/certificate/bind` | Link the certificate to the product |
| POST | `/v1/product/certificate/delete` | Delete certificate |
| POST | `/v1/product/certificate/info` | Certificate information |
| POST | `/v1/product/certificate/list` | Certificates list |
| POST | `/v1/product/certificate/product_status/list` | Product statuses list |
| POST | `/v1/product/certificate/products/list` | List of products associated with the certificate |
| POST | `/v1/product/certificate/unbind` | Unbind products from a certificate |
| POST | `/v1/product/certificate/rejection_reasons/list` | Possible certificate rejection reasons |
| POST | `/v1/product/certificate/status/list` | Possible certificate statuses |

---

## 接口详情


### POST `/v1/description-category/tree`
**Tree of product category and type**  
operationId: `DescriptionCategoryAPI_GetTree`  

Returns product categories in the tree view. 

New products can be created in the last level categories only.
This means that you need to match these particular categories with the categories of your site.
We don't create new categories by user request.

<aside class="warning">
   Choose the category for the product carefully: there are different commission fees for different categories.
</aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `language` | `languageLanguage` |  |  |

**响应 200**: Category tree
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v1GetTreeResponseItem] |  | Categories list. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/description-category/attribute`
**Category characteristics list**  
operationId: `DescriptionCategoryAPI_GetAttributes`  

Getting characteristics for specified product category and type.

If the `dictionary_id` value is `0`, there is no directory.
If the value is different, there are directories. 
Get them using the [/v1/description-category/attribute/values](#operation/DescriptionCategoryAPI_GetAttributeValues) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `description_category_id` | integer | ✓ | Category identifier. You can get it using the [/v1/description-category/tree](#operation/Description |
| `language` | `languageLanguage` |  |  |
| `type_id` | integer | ✓ | Product type identifier. You can get it using the [/v1/description-category/tree](#operation/Descrip |

**响应 200**: Category characteristics
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v1GetAttributesResponseAttribute] |  | Method result. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/description-category/attribute/values`
**Characteristics value directory**  
operationId: `DescriptionCategoryAPI_GetAttributeValues`  

Returns characteristics value directory.

To check if an attribute has a nested directory, use the [/v1/description-category/attribute](#operation/DescriptionCategoryAPI_GetAttributes) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `attribute_id` | integer | ✓ | Characteristics identifier. You can get it using the [/v1/description-category/attribute](#operation |
| `description_category_id` | integer | ✓ | Category identifier. You can get it using the [/v1/description-category/tree](#operation/Description |
| `language` | `languageLanguage` |  |  |
| `last_value_id` | integer |  | Identifier of the directory to start the response with. If `last_value_id` is 10, the response will  |
| `limit` | integer | ✓ | Number of values in the response:  - maximum—2000,  - minimum—1.  |
| `type_id` | integer | ✓ | Product type identifier. You can get it using the [/v1/description-category/tree](#operation/Descrip |

**响应 200**: Characteristics directory
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `has_next` | boolean |  | Indication that only part of characteristic values was returned in the response: - `true`—make a req |
| `result` | array[v1GetAttributeValuesResponseDictionaryValue] |  | Characteristic values. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/description-category/attribute/values/search`
**Search by reference values of a characteristic**  
operationId: `DescriptionCategoryAPI_SearchAttributeValues`  

Returns characteristic reference values for the specified `value` in the request.

To check if an attribute has a nested directory, use the [/v1/description-category/attribute](#operation/DescriptionCategoryAPI_GetAttributes) method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `attribute_id` | integer | ✓ | Characteristic identifier. You can get it using the [/v1/description-category/attribute](#operation/ |
| `description_category_id` | integer | ✓ | Category identifier. You can get it using the [/v1/description-category/tree](#operation/Description |
| `limit` | integer | ✓ | Number of values in the response. The minimum value is 1, the maximum is 100. |
| `type_id` | integer | ✓ | Product type identifier. You can get it using the [/v1/description-category/tree](#operation/Descrip |
| `value` | string | ✓ | By this value the system searches for reference values. It must be at least 2 characters. |

**响应 200**: Reference values of a characteristic.
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[SearchAttributeValuesResponseValue] |  | Characteristic values. |
**响应 default**: Error.
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v3/product/import`
**Create or update a product**  
operationId: `ProductAPI_ImportProductsV3`  

<aside class="warning">
If you're selling from China or Hong Kong under the FBP scheme, generate a barcode for each product item. Partner warehouses don't accept products without barcodes.
</aside>

This method allows you to create products and update their details.

You can add or update a certain number of products per day. To find out the limit, use
[/v4/product/info/limit](#operation/ProductAPI_GetUploadQuota). If the number of product creations
and updates exceeds the limit, an `item_limit_exceeded` error will appear.

You can pass up to 100 products in one request.
Each product is a sepa

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | array[v3ImportProductsRequestItem] |  | Data array. |

**响应 200**: New product has been created / Product details have been updated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v3ImportProductsResponseResult` |  |  |
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

### POST `/v1/product/import/info`
**Get the product import status**  
operationId: `ProductAPI_GetImportProductsInfo`  

Allows you to get the status of a product description page creation or update process.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `task_id` | integer | ✓ | Importing products task code. You can get it using the [/v3/product/import](#operation/ProductAPI_Im |

**响应 200**: Product import status
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `productGetImportProductsInfoResponseResult` |  |  |
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

### POST `/v1/product/import-by-sku`
**Create a product by SKU**  
operationId: `ProductAPI_ImportProductsBySKU`  

The method creates a [copy of the product description page](https://docs.ozon.ru/global/en/products/upload/upload-types/copying/?country=OTHER) with the specified SKU.

The method creates a copy of PDP from other seller. You cannot create a copy of your product.

You cannot create a copy if the seller has prohibited the copying of their PDPs.

It's not possible to update products using SKU.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | array[productImportProductsBySKURequestItem] |  | Products details. |

**响应 200**: The product is created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `productImportProductsBySKUResponseResult` |  |  |
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

### POST `/v1/product/attributes/update`
**Update product characteristics**  
operationId: `ProductAPI_ProductUpdateAttributes`  

This method allows you to add characteristics and change their values. You can't delete characteristics that are already filled out. To completely update characteristics, use <a href="#operation/ProductAPI_ImportProductsV3">/v3/product/import</a>.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | any |  | Products and characteristics to be updated. |

**响应 200**: Task for product update is created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `task_id` | integer |  | Products update task code.  To check the update status, pass the received value to the [/v1/product/ |
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

### POST `/v1/product/pictures/import`
**Upload and update product images**  
operationId: `ProductAPI_ProductImportPictures`  

The method for uploading and updating product images.

Each time you call the method, pass all the images that should be on the product description page. For example, if you call a method and upload 10 images, and then call the method a second time and load one imahe,
then all 10 previous ones will be erased.

To upload image, pass a link to it in a public cloud storage. The image format is JPG or PNG.

Arrange the pictures in the `images` array as you want to see them on the site. The first picture in the array will
be the main one for the product.

You can upload up to 30 pictures for each p

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `color_image` | string |  | Marketing color. |
| `images` | any |  | Array of links to images, up to 30 links. The images in the array are arranged in the order of their |
| `images360` | any |  | Array of 360 images—up to 70 files. |
| `product_id` | integer | ✓ | Product identifier in the Ozon system, `product_id`. |

**响应 200**: Preliminary method result
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `productv1ProductInfoPicturesResponseResult` |  |  |
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

### POST `/v3/product/list`
**List of products**  
operationId: `ProductAPI_GetProductList`  

Method for getting a list of all products.

When using the filter by `offer_id` or `product_id` identifiers, other parameters aren't required.
At a time you can use only one identifier group with 1000 products or less.

If you don't use identifiers for display, specify the `limit` and `last_id` parameters in subsequent requests.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `productv3GetProductListRequestFilter` |  |  |
| `last_id` | string |  | Identifier of the last value on the page. Leave this field blank in the first request.  To get the n |
| `limit` | integer |  | Number of values per page. Minimum is 1, maximum is 1000. |

**响应 200**: List of products
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `productv3GetProductListResponseResult` |  |  |
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

### POST `/v1/product/rating-by-sku`
**Get products' content rating by SKU**  
operationId: `ProductAPI_GetProductRatingBySku`  

Method for getting products' content rating and recommendations on how to increase it.

[Learn more about content rating](https://docs.ozon.ru/global/en/products/general-information/content-rating/)

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `skus` | any | ✓ | Product identifiers in the Ozon system, SKUs, for which content rating should be returned. |

**响应 200**: Products' content rating
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `products` | any |  | Products' content rating. |
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

### POST `/v3/product/info/list`
**Get a list of products by identifiers**  
operationId: `ProductAPI_GetProductInfoList`  

Method for getting an array of products by their identifiers.

Request body must contain an array of identifiers of the same type. The response contains an `items` array.

In one request, you can pass up to 1,000 products by `offer_id`, `product_id`, and `sku` parameters in total.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `offer_id` | array[string] |  | Product identifier in the seller's system. |
| `product_id` | array[string] |  | Product identifier in the Ozon system, `product_id`. |
| `sku` | array[string] |  | Product identifier in the Ozon system, SKU. |

**响应 200**: Products list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | array[v3GetProductInfoListResponseItem] |  | Data array. |
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

### POST `/v4/product/info/attributes`
**Get a description of the product characteristics**  
operationId: `ProductAPI_GetProductAttributesV4`  

Returns a product characteristics description by product identifier or visibility. You can search for the product by `offer_id`, `product_id` or `sku`.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `productv4Filter` |  |  |
| `last_id` | string |  | Identifier of the last value on the page. Leave this field blank in the first request.  To get the n |
| `limit` | integer |  | Number of values per page. |
| `sort_by` | string |  | Parameter by which you can sort the products: - `sku`: sorting by product identifier in Ozon system; |
| `sort_dir` | string |  | Sorting direction: - `asc`—ascending, - `desc`—descending.  |

**响应 200**: Description of the product characteristics
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | any |  | Request results. |
| `last_id` | string |  | Identifier of the last value on the page.  To get the next values, specify the recieved value in the |
| `total` | integer |  | Number of products in the list. |
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

### POST `/v1/product/info/description`
**Get product description**  
operationId: `ProductAPI_GetProductInfoDescription`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `offer_id` | string |  | Product identifier in the seller's system. |
| `product_id` | integer |  | Product identifier in the Ozon system, `product_id`. |

**响应 200**: Product description
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `productGetProductInfoDescriptionResponseProduct` |  |  |
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

### POST `/v4/product/info/limit`
**Product range limit, limits on product creation and update**  
operationId: `ProductAPI_GetUploadQuota`  

Method for getting information about the following limits:
- Product range limit: how many products you can create in your personal account.
- Products creation limit: how many products you can create per day.
- Products update limit: how many products you can update per day.

If you have a product range limit and you exceed it, you won't be able to create new products.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: Product range limit, limits on product creation and update
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `daily_create` | `GetUploadQuotaResponseDailyCreate` |  |  |
| `daily_update` | `GetUploadQuotaResponseDailyUpdate` |  |  |
| `total` | `GetUploadQuotaResponseTotal` |  |  |
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

### POST `/v1/product/update/offer-id`
**Change product identifiers from the seller's system**  
operationId: `ProductAPI_ProductUpdateOfferID`  

Method for changing the `offer_id` linked to products. You can change multiple `offer_id` in this method.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `update_offer_id` | any | ✓ | List of pairs with new and old values of product identifiers |

**响应 200**: Information on changing product identifiers
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `errors` | any |  | Errors list. |
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

### POST `/v1/product/archive`
**Archive a product**  
operationId: `ProductAPI_ProductArchive`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `product_id` | array[integer] | ✓ | Product identifiers. You can pass up to 100 identifiers at a time. |

**响应 200**: Product is archived
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | boolean |  | The result of processing the request. `true` if the request was executed without errors. |
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

### POST `/v1/product/unarchive`
**Unarchive a product**  
operationId: `ProductAPI_ProductUnarchive`  

Method is available to sellers from China and Turkey. You can restore up to 10 archived products per day via the `product_id` parameter.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `product_id` | array[integer] | ✓ | Product identifiers in the Ozon system. You can pass up to 100 identifiers at a time.  You can resto |

**响应 200**: Product is unarchived
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | boolean |  | The result of processing the request. `true` if the request was executed without errors. |
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

### POST `/v2/products/delete`
**Remove a product without an SKU from the archive**  
operationId: `ProductAPI_DeleteProducts`  

You can pass up to 500 identifiers in one request.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `products` | array[DeleteProductsRequestProduct] | ✓ | Product identifier. |

**响应 200**: Product is removed
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `status` | array[DeleteProductsResponseDeleteStatus] |  | Product processing status. |
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

### POST `/v1/product/info/subscription`
**Number of users subscribed to product availability alerts**  
operationId: `ProductAPI_GetProductInfoSubscription`  

You can pass multiple products in a request.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `skus` | array[string] | ✓ | List of SKUs, product identifiers in the Ozon system. |

**响应 200**: Number of subscribed users
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v1GetProductInfoSubscriptionResponseResult] |  | Method result. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/related-sku/get`
**Get related SKUs**  
operationId: `ProductAPI_ProductGetRelatedSKU`  

Method for getting a single SKU based on the old SKU FBS and SKU FBO identifiers.
The response will contain all SKUs related to the passed ones.

The method can handle any SKU, even hidden or deleted.

In one request, you can pass up to 200 SKUs.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sku` | any | ✓ | List of SKUs. |

**响应 200**: Information on SKUs
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | any |  | Related SKUs information. |
| `errors` | any |  | Errors. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/product/pictures/info`
**Get products images**  
operationId: `ProductAPI_ProductInfoPicturesV2`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `product_id` | any | ✓ | Product identifier in the Ozon system, `product_id`. |

**响应 200**: Products images
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `items` | array[v2ProductInfoPicturesResponseItem] |  | Product images. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/info/wrong-volume`
**List of products with incorrect VWC**  
operationId: `ProductAPI_ProductInfoWrongVolume`  

Returns a list of products with incorrect volume and weight characteristics (VWC). If you specified them correctly, please contact Ozon support.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `limit` | integer | ✓ | Maximum number of values in the response. |

**响应 200**: Information on products with incorrect VWC
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `cursor` | string |  | Cursor for the next data sample. |
| `products` | any |  | Product list. |
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

### POST `/v1/barcode/add`
**Bind barcodes to products**  
operationId: `add-barcode`  

If a product has a barcode that isn't specified in your account, bind it using this method.
If a product doesn't have a barcode, you can create it using the [/v1/barcode/generate](#operation/generate-barcode) method.

Each product can have up to 100 barcodes.
You can use the method for no more than 20 requests per minute in one account.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `barcodes` | array[v1Barcode] | ✓ | List of barcodes and products. |

**响应 200**: Barcodes are bound
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `errors` | array[v1AddBarcodeResult] |  | Errors while binding barcodes. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/barcode/generate`
**Generate barcodes for products**  
operationId: `generate-barcode`  

If a product doesn't have a barcode, you can create it using this method.
If a barcode already exists, but it isn't specified in your account, you can bind it using the [/v1/barcode/add](#operation/add-barcode) method.

You can't generate barcodes for more than 100 products per request. 
You can use the method for no more than 20 requests per minute in one account.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `product_ids` | array[string] | ✓ | List of products for which you want to generate barcodes. |

**响应 200**: Barcodes generated
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `errors` | array[v1GenerateBarcodeResult] |  | Errors while generating barcodes. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/brand/company-certification/list`
**List of certified brands**  
operationId: `BrandAPI_BrandCompanyCertificationList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | integer | ✓ | Number of the page returned in the request. |
| `page_size` | integer | ✓ | Number of elements on the page. |

**响应 200**: Brands list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `BrandCompanyCertificationListResponseBrandCertificationResult` |  |  |
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

### GET `/v1/product/certificate/accordance-types`
**List of accordance types (version 1)**  
operationId: `ProductAPI_ProductCertificateAccordanceTypes`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Directory of accordance types
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[productProductCertificateAccordanceTypesResponseType] |  | Certificate types and names list. |
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

### GET `/v2/product/certificate/accordance-types/list`
**List of accordance types (version 2)**  
operationId: `CertificateAccordanceTypes`  

**响应 200**: List of accordance types
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v2ProductCertificateAccordanceTypesResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### GET `/v1/product/certificate/types`
**Directory of document types**  
operationId: `ProductAPI_ProductCertificateTypes`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Directory of document types
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[productProductCertificateTypesResponseType] |  | List of certificate types and names. |
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

### POST `/v2/product/certification/list`
**List of certified categories**  
operationId: `ProductAPI_ProductCertificationList`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | integer | ✓ | Page number. |
| `page_size` | integer | ✓ | Number of elements on the page. |

**响应 200**: List of certified categories
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `certification` | array[ProductCertificationListResponseCertificationv2] |  | Certified categories details. |
| `total` | integer |  | Total number of categories. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/certification/list`
**List of certified categories**  
operationId: `ProductAPI_V1ProductCertificationList`  

<aside class="warning">
  From April 14, 2025, method will be disabled. Switch to the <a href="#operation/ProductAPI_ProductCertificationList">/v2/product/certification/list</a> method.
</aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | integer |  | Number of the page returned in the query. |
| `page_size` | integer |  | Number of elements on the page. |

**响应 200**: List of certified categories
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `ProductCertificationListResponseCertificationResult` |  |  |
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

### POST `/v1/product/certificate/create`
**Adding certificates for products**  
operationId: `ProductAPI_ProductCertificateCreate`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`multipart/form-data`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `files` | array[file] | ✓ | Array of certificates for the product. Valid extensions are jpg, jpeg, png, pdf. |
| `name` | string | ✓ | Certificate name. Maximum 100 characters. |
| `number` | string | ✓ | Certificate number. Maximum 100 characters. |
| `type_code` | string | ✓ | Certificate type. To get the list of types, use the [GET /v1/product/certificate/types](#operation/P |
| `accordance_type_code` | string |  | Accordance type. To get the list of types, use the [GET /v1/product/certificate/accordance-types](#o |
| `issue_date` | string | ✓ | Issue date of the certificate. |
| `expire_date` | string |  | Expiration date of the certificate. Can be empty for permanent certificates.  Format: `2021-04-30T11 |

**响应 200**: Uploaded certificate identifier
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

### POST `/v1/product/certificate/bind`
**Link the certificate to the product**  
operationId: `ProductAPI_ProductCertificateBind`  

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `certificate_id` | integer | ✓ | Certificate identifier that was assigned when it was uploaded. |
| `product_id` | array[integer] | ✓ | An array of product identifiers that this certificate applies to. |

**响应 200**: Certificate is linked to the product
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | boolean |  | The result of processing the request. `true` if the request was executed without errors. |
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

### POST `/v1/product/certificate/delete`
**Delete certificate**  
operationId: `CertificateDelete`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `certificate_id` | integer | ✓ | Certificate identifier. |

**响应 200**: Certificate deleted
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1ProductCertificateDeleteResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/certificate/info`
**Certificate information**  
operationId: `CertificateInfo`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `certificate_number` | string | ✓ | Certificate identifier. |

**响应 200**: Certificate information
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1Certificate` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/certificate/list`
**Certificates list**  
operationId: `CertificateList`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `offer_id` | string |  | Product identifier associated with the certificate. Pass the parameter if you need certificates that |
| `status` | string |  | Certificate status. Pass the parameter if you need certificates with a certain status. |
| `type` | string |  | Certificate type. Pass the parameter if you need certificates with a certain type. |
| `page` | integer | ✓ | Page from which the list should be displayed. The minimum value is 1. |
| `page_size` | integer | ✓ | Number of objects on the page. The value is from 1 to 1000. |

**响应 200**: Certificates list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1ProductCertificateListResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/certificate/product_status/list`
**Product statuses list**  
operationId: `ProductStatusList`  

A method for getting a list of possible statuses of products when binding them to a certificate.

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: Product statuses list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v1StatusCodeNamePair] |  | Product statuses. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/certificate/products/list`
**List of products associated with the certificate**  
operationId: `CertificateProductsList`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `certificate_id` | integer | ✓ | Certificate identifier. |
| `product_status_code` | string |  | Status of the product verification when binding to a certificate. |
| `page` | integer | ✓ | Page from which the list should be displayed. The minimum value is 1. |
| `page_size` | integer | ✓ | Number of objects on the page. The value is from 1 to 1000. |

**响应 200**: List of products
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | `v1ProductCertificateProductsListResponseResult` |  |  |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/certificate/unbind`
**Unbind products from a certificate**  
operationId: `CertificateUnbind`  

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `certificate_id` | integer | ✓ | Certificate identifier. |
| `product_id` | array[string] | ✓ | List of product identifiers that you want to unbind from a certificate. |

**响应 200**: Product was unbind from a certificate
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[ProductCertificateUnbindResponseItem] |  | Method result. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/certificate/rejection_reasons/list`
**Possible certificate rejection reasons**  
operationId: `RejectionReasonsList`  

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: Reasons for certificate rejection
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v1StatusCodeNamePairRejection] |  | Certificate rejection reasons. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/product/certificate/status/list`
**Possible certificate statuses**  
operationId: `CertificateStatusList`  

**请求体** (`application/json`):

```json
{"type": "object", "title": "object"}
```

**响应 200**: Certificate statuses
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | array[v1StatusCodeNamePairStatuses] |  | Possible certificate statuses. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---