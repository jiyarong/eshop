# FBW Supplies API

> **Base URL:** `https://supplies-api.wildberries.ru`
>
> **Authorization:** `HeaderApiKey` — requires a [token](https://dev.wildberries.ru/en/docs/openapi/api-information#tag/Authorization/How-to-create-a-personal-access-base-or-test-token) for the **Supplies** category.

---

## 1. Information for Forming Supplies

APIs for retrieving information needed to form supplies to WB warehouses.

### 1.1 Acceptance Options

```
POST /api/v1/acceptance/options
```

Returns information about warehouses and package types available for supply. The warehouses list is determined by the item's SKU and quantity.

#### Rate Limits

| Type             | Period | Limit      | Interval | Burst      |
| ---------------- | ------ | ---------- | -------- | ---------- |
| Personal         | 1 min  | 6 requests | 10 s     | 6 requests |
| Service          | 1 min  | 6 requests | 10 s     | 6 requests |
| Base with secret | 1 min  | 6 requests | 10 s     | 6 requests |
| Base             | 1 h    | 2 requests | 30 min   | 1 request  |

#### Query Parameters

| Parameter    | Type    | Required | Description |
| ------------ | ------- | -------- | ----------- |
| `warehouseID` | integer | No       | Warehouse ID. If not specified, returns data for all warehouses. **Maximum one value.** |

#### Request Body (JSON, required)

Array of objects (max 5000 items):

| Field    | Type    | Required | Constraints          | Description              |
| -------- | ------- | -------- | -------------------- | ------------------------ |
| `quantity` | integer | Yes      | 1 … 999999           | Total quantity of items planned for supply. Max 999999. |
| `barcode`  | string  | Yes      | —                    | Barcode from the listing. |

**Example:**

```json
[
  { "quantity": 1,  "barcode": "k" },
  { "quantity": 7,  "barcode": "1111111111" }
]
```

#### Responses

| Status | Description       |
| ------ | ----------------- |
| 200    | Success           |
| 400    | Incorrect request |
| 401    | Unauthorized      |
| 402    | Payment required  |
| 403    | Access denied     |
| 404    | Not found         |
| 429    | Too many requests |

##### 200 Response Example

```json
{
  "result": [
    {
      "barcode": "Seller",
      "warehouses": null,
      "error": {
        "title": "barcode validation error",
        "detail": "barcode Seller is not found"
      },
      "isError": true
    },
    {
      "barcode": "123456789",
      "warehouses": [
        {
          "warehouseID": 205349,
          "canBox": true,
          "canMonopallet": false,
          "canSupersafe": false,
          "isBoxOnPallet": false
        },
        {
          "warehouseID": 211622,
          "canBox": false,
          "canMonopallet": true,
          "canSupersafe": false,
          "isBoxOnPallet": true
        },
        {
          "warehouseID": 214951,
          "canBox": true,
          "canMonopallet": false,
          "canSupersafe": false,
          "isBoxOnPallet": true
        },
        {
          "warehouseID": 206319,
          "canBox": true,
          "canMonopallet": false,
          "canSupersafe": false,
          "isBoxOnPallet": true
        }
      ]
    }
  ],
  "requestId": "kr53d2bRKYmkK2N6zaNKHs"
}
```

##### Response Fields

| Field                           | Type    | Description |
| ------------------------------- | ------- | ----------- |
| `result[].barcode`              | string  | Barcode from the request. |
| `result[].warehouses`           | array   | Available warehouses; `null` if an error occurred. |
| `result[].warehouses[].warehouseID` | integer | Warehouse ID. |
| `result[].warehouses[].canBox`      | boolean | Whether box-type packaging is allowed. |
| `result[].warehouses[].canMonopallet` | boolean | Whether monopallet-type packaging is allowed. |
| `result[].warehouses[].canSupersafe`  | boolean | Whether supersafe-type packaging is allowed. |
| `result[].warehouses[].isBoxOnPallet` | boolean | Whether box-on-pallet is required. |
| `result[].error`                | object  | Error details if the barcode is invalid. |
| `result[].error.title`          | string  | Short error description. |
| `result[].error.detail`         | string  | Detailed error message. |
| `result[].isError`              | boolean | Error indicator for this barcode. |
| `requestId`                     | string  | Unique request identifier. |

---

### 1.2 Warehouses List

```
GET /api/v1/warehouses
```

Returns the Wildberries warehouses list.

#### Rate Limits

| Type             | Period | Limit      | Interval | Burst      |
| ---------------- | ------ | ---------- | -------- | ---------- |
| Personal         | 1 min  | 6 requests | 10 s     | 6 requests |
| Service          | 1 min  | 6 requests | 10 s     | 6 requests |
| Base with secret | 1 min  | 6 requests | 10 s     | 6 requests |
| Base             | 12 h   | 1 request  | 12 h     | 1 request  |

#### Request

No request parameters.

#### Responses

| Status | Description      |
| ------ | ---------------- |
| 200    | Success          |
| 401    | Unauthorized     |
| 403    | Access denied    |
| 404    | Not found        |
| 429    | Too many requests |

##### 200 Response Example

```json
[
  {
    "ID": 300461,
    "name": "Гомель 2",
    "address": "Гомель, Могилёвская улица 1/А",
    "workTime": "24/7",
    "isActive": false,
    "isTransitActive": true
  }
]
```

##### Response Fields

| Field            | Type    | Description |
| ---------------- | ------- | ----------- |
| `ID`             | integer | Warehouse ID. |
| `name`           | string  | Warehouse name. |
| `address`        | string  | Warehouse address. |
| `workTime`       | string  | Working hours (e.g. `"24/7"`). |
| `isActive`       | boolean | Whether the warehouse is active. |
| `isTransitActive` | boolean | Whether transit operations are active. |

---

### 1.3 Transit Directions

```
GET /api/v1/transit-tariffs
```

Returns information about available transit directions.

#### Rate Limits

| Type             | Period | Limit      | Interval | Burst       |
| ---------------- | ------ | ---------- | -------- | ----------- |
| Personal         | 1 min  | 6 requests | 10 s     | 10 requests |
| Service          | 1 min  | 6 requests | 10 s     | 10 requests |
| Base with secret | 1 min  | 6 requests | 10 s     | 10 requests |
| Base             | 12 h   | 1 request  | 12 h     | 1 request   |

#### Request

No request parameters.

#### Responses

| Status | Description      |
| ------ | ---------------- |
| 200    | Success          |
| 401    | Unauthorized     |
| 429    | Too many requests |

##### 200 Response Example

```json
[
  {
    "transitWarehouseName": "Обухово",
    "destinationWarehouseName": "Краснодар",
    "activeFrom": "2024-11-03T21:01:00Z",
    "boxTariff": null,
    "palletTariff": 7500
  },
  {
    "transitWarehouseName": "СЦ Гомель 2",
    "destinationWarehouseName": "Краснодар (Тихорецкая)",
    "activeFrom": "2025-04-08T21:00:48.019Z",
    "boxTariff": [
      { "from": 0, "to": 1500, "value": 5.3 },
      { "from": 1500, "to": 0, "value": 3.9 }
    ],
    "palletTariff": 6500
  }
]
```

##### Response Fields

| Field                     | Type             | Description |
| ------------------------- | ---------------- | ----------- |
| `transitWarehouseName`    | string           | Name of the transit warehouse. |
| `destinationWarehouseName` | string           | Name of the destination warehouse. |
| `activeFrom`              | string (ISO 8601) | Date from which the direction is active. |
| `boxTariff`               | array / null     | Box tariff tiers; `null` if not applicable. |
| `boxTariff[].from`        | number           | Range start (grams). |
| `boxTariff[].to`          | number           | Range end (grams, `0` = unlimited). |
| `boxTariff[].value`       | number           | Tariff value. |
| `palletTariff`            | number           | Pallet tariff cost. |

---

## 2. Supplies Information

APIs for retrieving information about item supplies for storage in WB warehouses.

### 2.1 Supplies List

```
POST /api/v1/supplies
```

Returns a list of supplies. Returns the last 1000 supplies by default.

#### Rate Limits

| Type             | Period | Limit       | Interval | Burst       |
| ---------------- | ------ | ----------- | -------- | ----------- |
| Personal         | 1 min  | 30 requests | 2 s      | 10 requests |
| Service          | 1 min  | 30 requests | 2 s      | 10 requests |
| Base with secret | 1 min  | 30 requests | 2 s      | 10 requests |
| Base             | 1 h    | 2 requests  | 30 min   | 1 request   |

#### Query Parameters

| Parameter | Type    | Required | Default | Constraints | Description |
| --------- | ------- | -------- | ------- | ----------- | ----------- |
| `limit`   | integer | No       | 1000    | 1 … 1000    | Number of objects in the response. |
| `offset`  | integer | No       | 0       | —           | From which element to start outputting data. |

#### Request Body (JSON, required)

| Field      | Type          | Required | Description |
| ---------- | ------------- | -------- | ----------- |
| `dates`    | Array of objects | No       | Filter by date range. |
| `dates[].from` | string (date) | Yes (if `dates` present) | Start date (e.g. `"2024-03-04"`). |
| `dates[].till` | string (date) | Yes (if `dates` present) | End date (e.g. `"2025-03-24"`). |
| `dates[].type` | string        | Yes (if `dates` present) | Date type (e.g. `"factDate"`). |
| `statusIDs` | Array of integers | No       | Filter by supply statuses. |

**Status Values:**

| ID  | Status             |
| --- | ------------------ |
| 1   | Not planned        |
| 2   | Planned            |
| 3   | Unloading allowed  |
| 4   | Accepting          |
| 5   | Accepted           |
| 6   | Unloaded at the gate |

**Example Request:**

```json
{
  "dates": [
    { "from": "2024-03-04", "till": "2025-03-24", "type": "factDate" }
  ],
  "statusIDs": [5, 6]
}
```

#### Responses

| Status | Description      |
| ------ | ---------------- |
| 200    | Success          |
| 400    | Bad request      |
| 401    | Unauthorized     |
| 402    | Payment required |
| 429    | Too many requests |

##### 200 Response Example

```json
[
  {
    "phone": "+7 916 *** 44 44",
    "supplyID": null,
    "preorderID": 34597755,
    "createDate": "2024-12-29T16:58:26+03:00",
    "supplyDate": null,
    "factDate": null,
    "updatedDate": null,
    "statusID": 1,
    "boxTypeID": 1
  },
  {
    "phone": "+7 916 *** 33 33",
    "supplyID": 26596368,
    "preorderID": 34601223,
    "createDate": "2024-12-29T16:57:59+03:00",
    "supplyDate": "2024-12-29T00:00:00+03:00",
    "factDate": null,
    "updatedDate": null,
    "statusID": 2,
    "boxTypeID": 5
  },
  {
    "phone": "+7 000 *** 36 76",
    "supplyID": 22677736,
    "preorderID": 27363170,
    "createDate": "2024-08-22T18:10:59+03:00",
    "supplyDate": "2024-08-22T00:00:00+03:00",
    "factDate": "2024-08-22T12:24:14+03:00",
    "updatedDate": "2024-08-22T18:33:45+03:00",
    "statusID": 6,
    "boxTypeID": 2,
    "isBoxOnPallet": false
  }
]
```

##### Response Fields

| Field           | Type              | Description |
| --------------- | ----------------- | ----------- |
| `phone`         | string            | Masked phone number of the contact person. |
| `supplyID`      | integer / null    | Supply ID (`null` if not planned). |
| `preorderID`    | integer           | Pre-order ID. |
| `createDate`    | string (ISO 8601) | Creation date. |
| `supplyDate`    | string (ISO 8601) / null | Planned supply date. |
| `factDate`      | string (ISO 8601) / null | Actual supply date. |
| `updatedDate`   | string (ISO 8601) / null | Last update date. |
| `statusID`      | integer           | Supply status (1–6, see status table above). |
| `boxTypeID`     | integer           | Box type identifier. |
| `isBoxOnPallet` | boolean           | Whether the box is on a pallet. |

---

### 2.2 Supply Details

```
GET /api/v1/supplies/{ID}
```

Returns supply details by ID.

#### Rate Limits

| Type             | Period | Limit       | Interval | Burst       |
| ---------------- | ------ | ----------- | -------- | ----------- |
| Personal         | 1 min  | 30 requests | 2 s      | 10 requests |
| Service          | 1 min  | 30 requests | 2 s      | 10 requests |
| Base with secret | 1 min  | 30 requests | 2 s      | 10 requests |
| Base             | 1 h    | 2 requests  | 30 min   | 1 request   |

#### Path Parameters

| Parameter | Type    | Required | Description |
| --------- | ------- | -------- | ----------- |
| `ID`      | integer | Yes      | Supply ID or order ID. |

#### Query Parameters

| Parameter      | Type    | Required | Default | Description |
| -------------- | ------- | -------- | ------- | ----------- |
| `isPreorderID` | boolean | No       | `false` | `true` — search by order ID (passed in `ID`); `false` — search by supply ID. |

#### Responses

| Status | Description      |
| ------ | ---------------- |
| 200    | Success          |
| 400    | Bad request      |
| 401    | Unauthorized     |
| 402    | Payment required |
| 404    | Not found        |
| 429    | Too many requests |

##### 200 Response Example

```json
{
  "phone": "+7 903 *** 98 62",
  "statusID": 5,
  "boxTypeID": 2,
  "createDate": "2025-07-15T17:17:45+03:00",
  "supplyDate": "2025-07-15T00:00:00+03:00",
  "factDate": "2025-07-18T11:37:32+03:00",
  "updatedDate": "2025-07-18T12:59:53+03:00",
  "warehouseID": 507,
  "warehouseName": "Коледино",
  "actualWarehouseID": 507,
  "actualWarehouseName": "Коледино",
  "transitWarehouseID": null,
  "transitWarehouseName": "",
  "acceptanceCost": 5000,
  "paidAcceptanceCoefficient": 10,
  "rejectReason": null,
  "supplierAssignName": "Магазин",
  "storageCoef": "215",
  "deliveryCoef": "200",
  "quantity": 10,
  "readyForSaleQuantity": 0,
  "acceptedQuantity": 10,
  "unloadingQuantity": 10,
  "depersonalizedQuantity": 0,
  "isBoxOnPallet": true
}
```

##### Response Fields

| Field                      | Type              | Description |
| -------------------------- | ----------------- | ----------- |
| `phone`                    | string            | Masked phone number of the contact person. |
| `statusID`                 | integer           | Supply status (1–6). |
| `boxTypeID`                | integer           | Box type identifier. |
| `createDate`               | string (ISO 8601) | Creation date. |
| `supplyDate`               | string (ISO 8601) / null | Planned supply date. |
| `factDate`                 | string (ISO 8601) / null | Actual supply date. |
| `updatedDate`              | string (ISO 8601) / null | Last update date. |
| `warehouseID`              | integer           | Planned warehouse ID. |
| `warehouseName`            | string            | Planned warehouse name. |
| `actualWarehouseID`        | integer           | Actual warehouse ID (where accepted). |
| `actualWarehouseName`      | string            | Actual warehouse name. |
| `transitWarehouseID`       | integer / null    | Transit warehouse ID. |
| `transitWarehouseName`     | string            | Transit warehouse name. |
| `acceptanceCost`           | number            | Acceptance cost. |
| `paidAcceptanceCoefficient` | number            | Paid acceptance coefficient. |
| `rejectReason`             | string / null     | Reason for rejection (if any). |
| `supplierAssignName`       | string            | Supplier assignment name. |
| `storageCoef`              | string            | Storage coefficient. |
| `deliveryCoef`             | string            | Delivery coefficient. |
| `quantity`                 | integer           | Total quantity of items. |
| `readyForSaleQuantity`     | integer           | Quantity ready for sale. |
| `acceptedQuantity`         | integer           | Quantity accepted. |
| `unloadingQuantity`        | integer           | Quantity unloaded. |
| `depersonalizedQuantity`   | integer           | Quantity depersonalized. |
| `isBoxOnPallet`            | boolean           | Whether the box is on a pallet. |

---

### 2.3 Supply Items

```
GET /api/v1/supplies/{ID}/goods
```

Returns information about the items in the supply.

#### Rate Limits

| Type             | Period | Limit       | Interval | Burst       |
| ---------------- | ------ | ----------- | -------- | ----------- |
| Personal         | 1 min  | 30 requests | 2 s      | 10 requests |
| Service          | 1 min  | 30 requests | 2 s      | 10 requests |
| Base with secret | 1 min  | 30 requests | 2 s      | 10 requests |
| Base             | 1 h    | 2 requests  | 30 min   | 1 request   |

#### Path Parameters

| Parameter | Type    | Required | Description |
| --------- | ------- | -------- | ----------- |
| `ID`      | integer | Yes      | Supply ID or order ID. |

#### Query Parameters

| Parameter      | Type    | Required | Default | Constraints | Description |
| -------------- | ------- | -------- | ------- | ----------- | ----------- |
| `limit`        | integer | No       | 100     | 1 … 1000    | Number of objects in the response. |
| `offset`       | integer | No       | 0       | —           | From which element to start outputting data. |
| `isPreorderID` | boolean | No       | `false` | —           | `true` — search by order ID; `false` — search by supply ID. |

#### Responses

| Status | Description      |
| ------ | ---------------- |
| 200    | Success          |
| 400    | Bad request      |
| 401    | Unauthorized     |
| 402    | Payment required |
| 429    | Too many requests |

##### 200 Response Example

```json
[
  {
    "barcode": "1234567891234",
    "vendorCode": "wb4sewt0vg",
    "nmID": 987456654,
    "needKiz": true,
    "tnved": "6204430000",
    "techSize": "C",
    "color": "красный",
    "supplierBoxAmount": 10,
    "quantity": 10,
    "readyForSaleQuantity": 0,
    "unloadingQuantity": 0,
    "acceptedQuantity": 0
  }
]
```

##### Response Fields

| Field                 | Type    | Description |
| --------------------- | ------- | ----------- |
| `barcode`             | string  | Item barcode. |
| `vendorCode`          | string  | Vendor/article code. |
| `nmID`                | integer | Nomenclature ID. |
| `needKiz`             | boolean | Whether KIZ marking is required. |
| `tnved`               | string  | TN VED (commodity nomenclature) code. |
| `techSize`            | string  | Technical size. |
| `color`               | string  | Color. |
| `supplierBoxAmount`   | integer | Quantity per supplier box. |
| `quantity`            | integer | Total quantity. |
| `readyForSaleQuantity` | integer | Quantity ready for sale. |
| `unloadingQuantity`   | integer | Quantity unloaded. |
| `acceptedQuantity`    | integer | Quantity accepted. |

---

### 2.4 Supply Package

```
GET /api/v1/supplies/{ID}/package
```

Returns information about the package of the supply.

#### Rate Limits

| Type             | Period | Limit       | Interval | Burst       |
| ---------------- | ------ | ----------- | -------- | ----------- |
| Personal         | 1 min  | 30 requests | 2 s      | 10 requests |
| Service          | 1 min  | 30 requests | 2 s      | 10 requests |
| Base with secret | 1 min  | 30 requests | 2 s      | 10 requests |
| Base             | 1 h    | 2 requests  | 30 min   | 1 request   |

#### Path Parameters

| Parameter | Type    | Required | Description |
| --------- | ------- | -------- | ----------- |
| `ID`      | integer | Yes      | Supply ID. |

#### Responses

| Status | Description      |
| ------ | ---------------- |
| 200    | Success          |
| 400    | Bad request      |
| 401    | Unauthorized     |
| 402    | Payment required |
| 429    | Too many requests |

##### 200 Response Example

```json
[
  {
    "packageCode": "WB_689",
    "quantity": 1,
    "barcodes": [
      { "barcode": "1234567891234", "quantity": 1 }
    ]
  }
]
```

##### Response Fields

| Field                   | Type    | Description |
| ----------------------- | ------- | ----------- |
| `packageCode`           | string  | Package code (e.g. `"WB_689"`). |
| `quantity`              | integer | Number of packages. |
| `barcodes`              | array   | Barcodes contained in the package. |
| `barcodes[].barcode`    | string  | Item barcode. |
| `barcodes[].quantity`   | integer | Quantity of this barcode in the package. |

---

## Endpoint Summary

| #   | Method | Endpoint                              | Description                         |
| --- | ------ | ------------------------------------- | ----------------------------------- |
| 1.1 | POST   | `/api/v1/acceptance/options`          | Get available warehouses & package types by SKU/quantity |
| 1.2 | GET    | `/api/v1/warehouses`                  | List all WB warehouses             |
| 1.3 | GET    | `/api/v1/transit-tariffs`            | List available transit directions  |
| 2.1 | POST   | `/api/v1/supplies`                    | List supplies (last 1000 default)  |
| 2.2 | GET    | `/api/v1/supplies/{ID}`              | Get supply details by ID           |
| 2.3 | GET    | `/api/v1/supplies/{ID}/goods`        | Get items in a supply              |
| 2.4 | GET    | `/api/v1/supplies/{ID}/package`      | Get package info for a supply      |
