# Wildberries Tariffs API

> **Base URL:** `https://common-api.wildberries.ru`  
> **Authorization:** `HeaderApiKey`  
> **Token:** Any [token category](https://dev.wildberries.ru/en/docs/openapi/api-information#tag/Authorization/Token-categories) can be used for all endpoints below.

Management of tariff plans, calculation of delivery and return costs, and obtaining current tariffs.

---

## Table of Contents

- [1. Commissions — Item Category Commission](#1-commissions--item-category-commission)
- [2. Stock Tariffs — Box Tariffs](#2-stock-tariffs--box-tariffs)
- [3. Stock Tariffs — Pallet Tariffs](#3-stock-tariffs--pallet-tariffs)
- [4. Supply Tariffs](#4-supply-tariffs)
- [5. Return Cost to Seller](#5-return-cost-to-seller)

---

## 1. Commissions — Item Category Commission

### Endpoint

```
GET /api/v1/tariffs/commission
```

### Description

Returns WB commission by parent categories of items according to the sales model.

### Rate Limits

| Type             | Period | Limit      | Interval | Burst      |
| ---------------- | ------ | ---------- | -------- | ---------- |
| Personal         | 1 min  | 1 request  | 1 min    | 2 requests |
| Service          | 1 min  | 1 request  | 1 min    | 2 requests |
| Base with secret | 1 min  | 1 request  | 1 min    | 2 requests |
| Base             | 1 h    | 5 requests | 12 min   | 1 request  |

### Query Parameters

| Parameter | Type   | Required | Description |
| --------- | ------ | -------- | ----------- |
| `locale`  | string | No       | Language of the `parentName` and `subjectName` response fields.<br>Possible values: `ru` (Russian), `en` (English), `zh` (Chinese).<br>Example: `locale=ru` |

### Responses

| Status Code | Description      |
| ----------- | ---------------- |
| **200**     | Success          |
| **400**     | Bad request      |
| **401**     | Unauthorized     |
| **402**     | Payment required |
| **429**     | Too many requests |

### Response Sample (200)

```json
{
  "report": [
    {
      "kgvpBooking": 14.5,
      "kgvpMarketplace": 15.5,
      "kgvpPickup": 14.5,
      "kgvpSupplier": 12.5,
      "kgvpSupplierExpress": 3,
      "paidStorageKgvp": 15.5,
      "parentID": 657,
      "parentName": "Бытовая техника",
      "subjectID": 6461,
      "subjectName": "Оборудование зуботехническое"
    }
  ]
}
```

### Response Fields

| Field                  | Type    | Description |
| ---------------------- | ------- | ----------- |
| `report`               | Array   | List of commission records by item category |
| `kgvpBooking`          | Number  | Commission for booking model |
| `kgvpMarketplace`      | Number  | Commission for marketplace model |
| `kgvpPickup`           | Number  | Commission for pickup model |
| `kgvpSupplier`         | Number  | Commission for supplier model |
| `kgvpSupplierExpress`  | Number  | Commission for supplier express model |
| `paidStorageKgvp`      | Number  | Commission for paid storage |
| `parentID`             | Integer | Parent category ID |
| `parentName`           | String  | Parent category name (language depends on `locale` parameter) |
| `subjectID`            | Integer | Subject/item category ID |
| `subjectName`          | String  | Subject/item category name (language depends on `locale` parameter) |

---

## 2. Stock Tariffs — Box Tariffs

### Endpoint

```
GET /api/v1/tariffs/box
```

### Description

For items inventory supplied to the warehouse in boxes, this method returns the rates for:

- Delivery from warehouse or sorting center to the buyer
- Delivery (return) from the buyer to the sorting center
- Storage on WB warehouse

> **Note:** The rates for boxes match the **Supersafe** rates.

### Rate Limits

| Type             | Period | Limit       | Interval | Burst      |
| ---------------- | ------ | ----------- | -------- | ---------- |
| Personal         | 1 min  | 60 requests | 1 s      | 5 requests |
| Service          | 1 min  | 60 requests | 1 s      | 5 requests |
| Base with secret | 1 min  | 60 requests | 1 s      | 5 requests |
| Base             | 1 h    | 1 request   | 1 h      | 1 request  |

### Query Parameters

| Parameter | Type   | Required | Description |
| --------- | ------ | -------- | ----------- |
| `date`    | string | **Yes**  | Date in `YYYY-MM-DD` format |

### Responses

| Status Code | Description      |
| ----------- | ---------------- |
| **200**     | Success          |
| **400**     | Bad request      |
| **401**     | Unauthorized     |
| **402**     | Payment required |
| **429**     | Too many requests |

### Response Sample (200)

```json
{
  "response": {
    "data": {
      "dtNextBox": "2024-02-01",
      "dtTillMax": "2024-03-31",
      "warehouseList": [
        {
          "boxDeliveryBase": "48",
          "boxDeliveryCoefExpr": "160",
          "boxDeliveryLiter": "11,2",
          "boxDeliveryMarketplaceBase": "40",
          "boxDeliveryMarketplaceCoefExpr": "125",
          "boxDeliveryMarketplaceLiter": "11",
          "boxStorageBase": "0,14",
          "boxStorageCoefExpr": "115",
          "boxStorageLiter": "0,07",
          "geoName": "Центральный федеральный округ",
          "warehouseName": "Коледино"
        }
      ]
    }
  }
}
```

### Response Fields

| Field                                 | Type   | Description |
| ------------------------------------- | ------ | ----------- |
| `response.data.dtNextBox`             | String | Date when the next box tariff update will be applied |
| `response.data.dtTillMax`             | String | Maximum date until which the current tariffs are valid |
| `response.data.warehouseList`         | Array  | List of warehouses with their box tariff coefficients |
| `warehouseList[].boxDeliveryBase`     | String | Base delivery cost for boxes |
| `warehouseList[].boxDeliveryCoefExpr` | String | Delivery coefficient expression for boxes |
| `warehouseList[].boxDeliveryLiter`    | String | Delivery cost per liter for boxes |
| `warehouseList[].boxDeliveryMarketplaceBase`       | String | Base marketplace delivery cost for boxes |
| `warehouseList[].boxDeliveryMarketplaceCoefExpr`   | String | Marketplace delivery coefficient expression |
| `warehouseList[].boxDeliveryMarketplaceLiter`      | String | Marketplace delivery cost per liter |
| `warehouseList[].boxStorageBase`      | String | Base storage cost for boxes |
| `warehouseList[].boxStorageCoefExpr`  | String | Storage coefficient expression for boxes |
| `warehouseList[].boxStorageLiter`     | String | Storage cost per liter for boxes |
| `warehouseList[].geoName`             | String | Geographical region name |
| `warehouseList[].warehouseName`       | String | Warehouse name |

---

## 3. Stock Tariffs — Pallet Tariffs

### Endpoint

```
GET /api/v1/tariffs/pallet
```

### Description

For items supplied to the WB warehouse on pallets, this method returns the costs of:

- Delivery from warehouse to the buyer
- Delivery (return) from the buyer to warehouse
- Storage on WB warehouse

> **Note:** The rates for pallets match the **Piece pallet** rates.

### Rate Limits

| Type             | Period | Limit       | Interval | Burst      |
| ---------------- | ------ | ----------- | -------- | ---------- |
| Personal         | 1 min  | 60 requests | 1 s      | 5 requests |
| Service          | 1 min  | 60 requests | 1 s      | 5 requests |
| Base with secret | 1 min  | 60 requests | 1 s      | 5 requests |
| Base             | 1 h    | 1 request   | 1 h      | 1 request  |

### Query Parameters

| Parameter | Type   | Required | Description |
| --------- | ------ | -------- | ----------- |
| `date`    | string | **Yes**  | Date in `YYYY-MM-DD` format |

### Responses

| Status Code | Description      |
| ----------- | ---------------- |
| **200**     | Success          |
| **400**     | Bad request      |
| **401**     | Unauthorized     |
| **402**     | Payment required |
| **429**     | Too many requests |

### Response Sample (200)

```json
{
  "response": {
    "data": {
      "dtNextPallet": "2024-02-01",
      "dtTillMax": "2024-03-31",
      "warehouseList": [
        {
          "palletDeliveryExpr": "170",
          "palletDeliveryValueBase": "51",
          "palletDeliveryValueLiter": "11,9",
          "palletStorageExpr": "155",
          "palletStorageValueExpr": "35.65",
          "warehouseName": "Коледино"
        }
      ]
    }
  }
}
```

### Response Fields

| Field                                      | Type   | Description |
| ------------------------------------------ | ------ | ----------- |
| `response.data.dtNextPallet`               | String | Date when the next pallet tariff update will be applied |
| `response.data.dtTillMax`                  | String | Maximum date until which the current tariffs are valid |
| `response.data.warehouseList`              | Array  | List of warehouses with their pallet tariff coefficients |
| `warehouseList[].palletDeliveryExpr`       | String | Delivery coefficient expression for pallets |
| `warehouseList[].palletDeliveryValueBase`  | String | Base delivery value for pallets |
| `warehouseList[].palletDeliveryValueLiter` | String | Delivery value per liter for pallets |
| `warehouseList[].palletStorageExpr`        | String | Storage coefficient expression for pallets |
| `warehouseList[].palletStorageValueExpr`   | String | Storage value expression for pallets |
| `warehouseList[].warehouseName`            | String | Warehouse name |

---

## 4. Supply Tariffs

### Endpoint

```
GET /api/tariffs/v1/acceptance/coefficients
```

### Description

Returns the supply tariffs for specific warehouses for the next 14 days.

> **Important:** Acceptance for delivery is only available when the following conditions are met:
> - `coefficient` is `0` or `1`
> - `allowUnload` is `true`

### Rate Limits

| Type             | Period | Limit      | Interval | Burst      |
| ---------------- | ------ | ---------- | -------- | ---------- |
| Personal         | 1 min  | 6 requests | 10 s     | 6 requests |
| Service          | 1 min  | 6 requests | 10 s     | 6 requests |
| Base with secret | 1 min  | 6 requests | 10 s     | 6 requests |
| Base             | 1 h    | 1 request  | 1 h      | 1 request  |

### Query Parameters

| Parameter      | Type   | Required | Description |
| -------------- | ------ | -------- | ----------- |
| `warehouseIDs` | string | No       | Comma-separated warehouse IDs. By default, data for all warehouses is returned.<br>Example: `warehouseIDs=507,117501` |

### Responses

| Status Code | Description       |
| ----------- | ----------------- |
| **200**     | Success           |
| **400**     | Incorrect request |
| **401**     | Unauthorized      |
| **402**     | Payment required  |
| **403**     | Access denied     |
| **404**     | Not found         |
| **429**     | Too many requests |

### Response Sample (200)

```json
[
  {
    "date": "2024-04-11T00:00:00Z",
    "coefficient": -1,
    "warehouseID": 217081,
    "warehouseName": "Сц Брянск 2",
    "allowUnload": false,
    "boxTypeID": 6,
    "storageCoef": null,
    "deliveryCoef": null,
    "deliveryBaseLiter": null,
    "deliveryAdditionalLiter": null,
    "storageBaseLiter": null,
    "storageAdditionalLiter": null,
    "isSortingCenter": true
  }
]
```

### Response Fields

| Field                      | Type    | Description |
| -------------------------- | ------- | ----------- |
| `date`                     | String  | Date and time (ISO 8601) |
| `coefficient`              | Integer | Supply coefficient. `-1` or `0` means supply is closed; `1` means supply is open (acceptance available). |
| `warehouseID`              | Integer | Warehouse ID |
| `warehouseName`            | String  | Warehouse name |
| `allowUnload`              | Boolean | Whether unloading is allowed at this warehouse |
| `boxTypeID`                | Integer | Box type ID |
| `storageCoef`              | Number  | Storage coefficient (nullable) |
| `deliveryCoef`             | Number  | Delivery coefficient (nullable) |
| `deliveryBaseLiter`        | Number  | Base delivery cost per liter (nullable) |
| `deliveryAdditionalLiter`  | Number  | Additional delivery cost per liter (nullable) |
| `storageBaseLiter`         | Number  | Base storage cost per liter (nullable) |
| `storageAdditionalLiter`   | Number  | Additional storage cost per liter (nullable) |
| `isSortingCenter`          | Boolean | Whether the warehouse is a sorting center |

---

## 5. Return Cost to Seller

### Endpoint

```
GET /api/v1/tariffs/return
```

### Description

Returns tariffs for:

- Transfer from Wildberries warehouse or sorting center to the seller
- Transfer of returned items that were not picked up by the seller

### Rate Limits

| Type             | Period | Limit       | Interval | Burst      |
| ---------------- | ------ | ----------- | -------- | ---------- |
| Personal         | 1 min  | 60 requests | 1 s      | 5 requests |
| Service          | 1 min  | 60 requests | 1 s      | 5 requests |
| Base with secret | 1 min  | 60 requests | 1 s      | 5 requests |
| Base             | 1 h    | 1 request   | 1 h      | 1 request  |

### Query Parameters

| Parameter | Type   | Required | Description |
| --------- | ------ | -------- | ----------- |
| `date`    | string | **Yes**  | Date in `YYYY-MM-DD` format |

### Responses

| Status Code | Description      |
| ----------- | ---------------- |
| **200**     | Success          |
| **400**     | Bad request      |
| **401**     | Unauthorized     |
| **402**     | Payment required |
| **429**     | Too many requests |

### Response Sample (200)

```json
{
  "response": {
    "data": {
      "dtNextDeliveryDumpKgt": "2024-02-01",
      "dtNextDeliveryDumpSrg": "2024-02-01",
      "dtNextDeliveryDumpSup": "2024-02-01",
      "warehouseList": [
        {
          "deliveryDumpKgtOfficeBase": "1 039",
          "deliveryDumpKgtOfficeLiter": "9,1",
          "deliveryDumpKgtReturnExpr": "1 050",
          "deliveryDumpSrgOfficeExpr": "170",
          "deliveryDumpSrgReturnExpr": "170",
          "deliveryDumpSupCourierBase": "229",
          "deliveryDumpSupCourierLiter": "9,1",
          "deliveryDumpSupOfficeBase": "129",
          "deliveryDumpSupOfficeLiter": "9,1",
          "deliveryDumpSupReturnExpr": "250",
          "warehouseName": "Электросталь"
        }
      ]
    }
  }
}
```

### Response Fields

| Field                                          | Type   | Description |
| ---------------------------------------------- | ------ | ----------- |
| `response.data.dtNextDeliveryDumpKgt`          | String | Next date for KGT delivery dump tariff update |
| `response.data.dtNextDeliveryDumpSrg`          | String | Next date for SRG delivery dump tariff update |
| `response.data.dtNextDeliveryDumpSup`          | String | Next date for SUP delivery dump tariff update |
| `response.data.warehouseList`                  | Array  | List of warehouses with return cost tariffs |
| `warehouseList[].deliveryDumpKgtOfficeBase`    | String | Base KGT office delivery dump cost |
| `warehouseList[].deliveryDumpKgtOfficeLiter`   | String | KGT office delivery dump cost per liter |
| `warehouseList[].deliveryDumpKgtReturnExpr`    | String | KGT return delivery dump coefficient expression |
| `warehouseList[].deliveryDumpSrgOfficeExpr`    | String | SRG office delivery dump coefficient expression |
| `warehouseList[].deliveryDumpSrgReturnExpr`    | String | SRG return delivery dump coefficient expression |
| `warehouseList[].deliveryDumpSupCourierBase`   | String | Base SUP courier delivery dump cost |
| `warehouseList[].deliveryDumpSupCourierLiter`  | String | SUP courier delivery dump cost per liter |
| `warehouseList[].deliveryDumpSupOfficeBase`    | String | Base SUP office delivery dump cost |
| `warehouseList[].deliveryDumpSupOfficeLiter`   | String | SUP office delivery dump cost per liter |
| `warehouseList[].deliveryDumpSupReturnExpr`    | String | SUP return delivery dump coefficient expression |
| `warehouseList[].warehouseName`                | String | Warehouse name |

---

## References

- [User Agreement of the WB API Service](https://dev.wildberries.ru/en/rules)
- [WB API Platform Access Agreement](https://legal.wildberries.ru/soglashenie-o-razmeschenii-avtorizovannykh-servisov-na-platforme-wb-api/country/ru/lang/ru/)
- [Policy on the Processing of Personal Data of RWB](https://dev.wildberries.ru/en/privacy)
- [WB API Price List for Third-Party Services](https://dev.wildberries.ru/api/price-list)
- [FAQ. Frequently Asked Questions](https://dev.wildberries.ru/en/faq)

---

© Wildberries 2004-2026. All rights reserved. Contact: <dev-info@rwb.ru>
