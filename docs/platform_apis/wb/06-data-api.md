# Wildberries Analytics and Data API 整理版

> 来源文件：`data.html.md`  
> Base URL：`https://seller-analytics-api.wildberries.ru`  
> 鉴权：`HeaderApiKey`，使用 **Analytics** 类别 token。部分接口仅支持 Personal / Service token 或需要 Jam 订阅。

## 目录

- [通用说明](#通用说明)
- [Sales Funnel 销售漏斗](#sales-funnel-销售漏斗)
- [Search Queries for Your Items 商品搜索词分析](#search-queries-for-your-items-商品搜索词分析)
- [Stocks Report 库存报告](#stocks-report-库存报告)
- [Item Rating 商品评分](#item-rating-商品评分)
- [Seller Analytics CSV 卖家分析 CSV 报告](#seller-analytics-csv-卖家分析-csv-报告)

## 通用说明

### 通用响应状态码

| 状态码 | 含义 |
|---|---|
| 200 | Success，请求成功 |
| 400 | Bad request，请求参数错误 |
| 401 | Unauthorized，未授权或 token 无效 |
| 402 | Payment required，需要付费/订阅 |
| 403 | Access denied，无权限 |
| 429 | Too many requests，请求过于频繁 |

### 常用对象

| 对象/字段 | 说明 |
|---|---|
| `selectedPeriod` / `currentPeriod` / `period` | 查询周期，通常包含 `start`、`end`，格式：`YYYY-MM-DD` |
| `pastPeriod` | 对比周期，通常天数需小于或等于当前周期 |
| `nmIds` / `nmIDs` / `nmId` / `nmID` | WB 商品编号。注意不同接口大小写不完全一致，应按接口文档传参 |
| `brandNames` / `brandName` | 品牌名称过滤 |
| `subjectIds` / `subjectIDs` / `subjectId` / `subjectID` | 商品子类目 ID |
| `tagIds` / `tagIDs` / `tagId` / `tagID` | 标签 ID |
| `orderBy` | 排序对象，一般包含 `field` 和 `mode`，`mode` 可为 `asc` / `desc` |
| `limit` | 返回数量限制 |
| `offset` | 分页偏移量 |

---

# Sales Funnel 销售漏斗

用于获取商品销售漏斗相关数据，包括浏览、加购、下单、买断、取消、转化率等指标。

数据通常每小时更新一次。多数订单、点击、加购数据会在事件发生后一小时内出现，少量数据可能延迟数天。

## 1. Listings Statistics per Period

### 基本信息

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/analytics/v3/sales-funnel/products` |
| URL | `https://seller-analytics-api.wildberries.ru/api/analytics/v3/sales-funnel/products` |
| 功能 | 按指定周期生成商品销售漏斗统计，并与历史周期对比 |
| 最大查询范围 | 最近 365 天 |
| 是否支持分页 | 是 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：2 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `selectedPeriod` | 是 | object | 当前查询周期 |
| `pastPeriod` | 否 | object | 对比周期；周期长度与 `selectedPeriod` 相同 |
| `nmIds` | 否 | uint64[]，0..1000 | WB 商品编号。空数组表示全部商品 |
| `brandNames` | 否 | string[] | 品牌过滤。空数组表示全部 |
| `subjectIds` | 否 | uint64[] | 子类目 ID 过滤。空数组表示全部 |
| `tagIds` | 否 | uint64[] | 标签 ID 过滤。空数组表示全部 |
| `skipDeletedNm` | 否 | boolean | 是否跳过已删除商品 |
| `orderBy` | 否 | object | 排序参数 |
| `limit` | 否 | uint32，<=1000，默认 50 | 返回商品数量 |
| `offset` | 否 | uint32，默认 0 | 偏移量 |

> 多个过滤条件同时传入时，返回同时满足所有条件的商品；无匹配时返回空数组。

### 请求示例

```json
{
  "selectedPeriod": {"start": "2023-06-01", "end": "2024-03-01"},
  "pastPeriod": {"start": "2023-06-01", "end": "2024-03-01"},
  "nmIds": [1234567],
  "brandNames": ["nike", "adidas"],
  "subjectIds": [64, 334],
  "tagIds": [32, 53],
  "skipDeletedNm": false,
  "orderBy": {"field": "openCard", "mode": "asc"},
  "limit": 231,
  "offset": 10
}
```

### 响应核心结构

```json
{
  "data": {
    "products": [
      {
        "product": {
          "nmId": 268913787,
          "title": "Кроссовки для бега",
          "vendorCode": "12345456",
          "brandName": "Demix",
          "subjectId": 105,
          "subjectName": "Кроссовки",
          "tags": [{"id": 1, "name": "Обувь"}],
          "productRating": 4.5,
          "feedbackRating": 4,
          "stocks": {"wb": 0, "mp": 0, "balanceSum": 0}
        },
        "statistic": {
          "selected": {},
          "past": {},
          "comparison": {}
        }
      }
    ],
    "currency": "RUB"
  }
}
```

核心指标包括：`openCount`、`cartCount`、`orderCount`、`orderSum`、`buyoutCount`、`buyoutSum`、`cancelCount`、`cancelSum`、`avgPrice`、`avgOrdersCountPerDay`、`addToWishlist`、`conversions`、`wbClub` 等。

---

## 2. Listings Statistics per Days

### 基本信息

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/analytics/v3/sales-funnel/products/history` |
| 功能 | 按天或按周返回商品销售漏斗统计 |
| 最大查询范围 | 最近一周 |
| 扩展查询 | 如需最长一年历史数据，使用 Seller Analytics CSV 的 `DETAIL_HISTORY_REPORT`，通常需要 Jam 订阅 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：2 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `selectedPeriod` | 是 | object | 查询周期 |
| `nmIds` | 是 | uint64[]，1..20 | WB 商品编号列表 |
| `skipDeletedNm` | 否 | boolean | 是否跳过已删除商品 |
| `aggregationLevel` | 否 | string，默认 `day` | 聚合级别：`day` / `week` |

### 请求示例

```json
{
  "selectedPeriod": {"start": "2023-06-01", "end": "2024-03-01"},
  "nmIds": [268913787],
  "skipDeletedNm": true,
  "aggregationLevel": "day"
}
```

### 响应核心结构

```json
[
  {
    "product": {
      "nmId": 268913787,
      "title": "Кроссовки для бега",
      "vendorCode": "12345456",
      "brandName": "Demix",
      "subjectId": 105,
      "subjectName": "Кроссовки"
    },
    "history": [
      {
        "date": "2024-10-23",
        "openCount": 45,
        "cartCount": 34,
        "orderCount": 19,
        "orderSum": 1262,
        "buyoutCount": 19,
        "buyoutSum": 1262,
        "buyoutPercent": 35,
        "addToCartConversion": 43,
        "cartToOrderConversion": 0,
        "addToWishlistCount": 0
      }
    ],
    "currency": "RUB"
  }
]
```

---

## 3. Grouped Listings Statistics per Days

### 基本信息

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/analytics/v3/sales-funnel/grouped/history` |
| 功能 | 按天或按周返回商品销售漏斗统计，按子类目、品牌、标签分组 |
| 最大查询范围 | 最近一周 |
| 扩展查询 | 如需最长一年，使用 Seller Analytics CSV 的 `GROUPED_HISTORY_REPORT`，通常需要 Jam 订阅 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：2 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `selectedPeriod` | 是 | object | 查询周期 |
| `brandNames` | 否 | string[] | 品牌过滤 |
| `subjectIds` | 否 | uint64[] | 子类目 ID 过滤 |
| `tagIds` | 否 | uint64[] | 标签 ID 过滤 |
| `skipDeletedNm` | 否 | boolean | 是否跳过已删除商品 |
| `aggregationLevel` | 否 | string，默认 `day` | `day` / `week` |

> 品牌、子类目、标签等分组请求中的条件组合数量不能超过 16。

### 请求示例

```json
{
  "selectedPeriod": {"start": "2023-06-01", "end": "2024-03-01"},
  "brandNames": ["nike", "adidas"],
  "subjectIds": [64, 334],
  "tagIds": [32, 53],
  "skipDeletedNm": false,
  "aggregationLevel": "day"
}
```

### 响应核心结构

```json
{
  "data": [
    {
      "product": {
        "nmId": 268913787,
        "title": "Кроссовки для бега",
        "vendorCode": "12345456",
        "brandName": "Demix",
        "subjectId": 105,
        "subjectName": "Кроссовки"
      },
      "history": [
        {
          "date": "2024-10-23",
          "openCount": 45,
          "cartCount": 34,
          "orderCount": 19,
          "orderSum": 1262,
          "buyoutCount": 19,
          "buyoutSum": 1262,
          "buyoutPercent": 35
        }
      ],
      "currency": "RUB"
    }
  ]
}
```

---

# Search Queries for Your Items 商品搜索词分析

用于获取商品搜索查询报告，包括主页面数据、分组分页、商品分页、商品搜索词 Top、搜索词订单与排名等。

> 这些接口通常需要 **Jam** 订阅。数据每小时更新一次。

## 4. Main Page

### 基本信息

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/v2/search-report/report` |
| 功能 | 生成搜索查询主报告页面数据，包括总体信息、商品位置、曝光/点击、分组表格数据 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：1 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `currentPeriod` | 是 | object | 当前周期 |
| `pastPeriod` | 否 | object | 对比周期，天数需小于或等于当前周期 |
| `nmIds` | 否 | int32[] | WB 商品编号过滤 |
| `subjectIds` | 否 | int32[] | 子类目 ID 过滤 |
| `brandNames` | 否 | string[] | 品牌过滤 |
| `tagIds` | 否 | int64[] | 标签 ID 过滤 |
| `positionCluster` | 是 | string | `all` / `firstHundred` / `secondHundred` / `below` |
| `orderBy` | 是 | object | 排序参数 |
| `includeSubstitutedSKUs` | 否 | boolean，默认 true | 是否显示带推广商品的直接查询数据 |
| `includeSearchTexts` | 否 | boolean，默认 true | 是否显示无推广商品的搜索查询数据 |
| `limit` | 是 | uint32，<=1000 | 返回商品组数量 |
| `offset` | 是 | uint32 | 偏移量 |

> `includeSubstitutedSKUs` 与 `includeSearchTexts` 不能同时为 `false`。

### 请求示例

```json
{
  "currentPeriod": {"start": "2024-02-10", "end": "2024-02-10"},
  "pastPeriod": {"start": "2024-02-08", "end": "2024-02-08"},
  "nmIds": [162579635, 166699779],
  "subjectIds": [32, 64],
  "brandNames": ["Adidas", "Nike"],
  "tagIds": [3, 5, 6],
  "positionCluster": "all",
  "orderBy": {"field": "avgPosition", "mode": "asc"},
  "includeSubstitutedSKUs": true,
  "includeSearchTexts": false,
  "limit": 130,
  "offset": 50
}
```

### 响应核心结构

```json
{
  "data": {
    "commonInfo": {},
    "positionInfo": {},
    "visibilityInfo": {},
    "groups": [],
    "currency": "RUB"
  }
}
```

主要数据包括：卖家评分、推广商品数量、商品总数、平均/中位搜索位置、曝光、点击、按日/周/月趋势、分组指标、商品列表等。

---

## 5. Pagination by Groups

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/v2/search-report/table/groups` |
| 功能 | 查询报告表格中的分组分页数据。仅在按品牌、子类目或标签过滤时可用 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：1 req/hour |

### 请求参数

与 Main Page 基本一致：

| 参数 | 必填 | 说明 |
|---|---:|---|
| `currentPeriod` | 是 | 当前周期 |
| `pastPeriod` | 否 | 对比周期 |
| `nmIds` | 否 | 商品编号过滤 |
| `subjectIds` | 否 | 子类目过滤 |
| `brandNames` | 否 | 品牌过滤 |
| `tagIds` | 否 | 标签过滤 |
| `orderBy` | 是 | 排序参数 |
| `positionCluster` | 是 | 平均搜索位置区间 |
| `includeSubstitutedSKUs` | 否 | 默认 true |
| `includeSearchTexts` | 否 | 默认 true |
| `limit` | 是 | <=1000 |
| `offset` | 是 | 偏移量 |

### 响应核心结构

```json
{
  "data": {
    "groups": [
      {
        "subjectName": "Phones",
        "subjectId": 50,
        "brandName": "Apple",
        "tagName": "phones",
        "tagId": 65,
        "metrics": {},
        "items": []
      }
    ],
    "currency": "RUB"
  }
}
```

---

## 6. Pagination by Items Within a Group

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/v2/search-report/table/details` |
| 功能 | 查询分组内商品分页，也可在无过滤条件下查询商品分页 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：1 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `currentPeriod` | 是 | object | 当前周期 |
| `pastPeriod` | 否 | object | 对比周期 |
| `subjectId` | 否 | int32 | 子类目 ID，作为分组条件之一 |
| `brandName` | 否 | string | 品牌，作为分组条件之一 |
| `tagId` | 否 | int64 | 标签 ID，作为分组条件之一 |
| `nmIds` | 否 | uint64[]，<=50 | WB 商品编号列表 |
| `orderBy` | 是 | object | 排序参数 |
| `positionCluster` | 是 | string | `all` / `firstHundred` / `secondHundred` / `below` |
| `includeSubstitutedSKUs` | 否 | boolean，默认 true | 是否包含带推广商品查询 |
| `includeSearchTexts` | 否 | boolean，默认 true | 是否包含搜索词查询 |
| `limit` | 是 | uint32，<=1000 | 返回商品数量 |
| `offset` | 是 | uint32 | 偏移量 |

### 响应核心结构

```json
{
  "data": {
    "products": [
      {
        "nmId": 268913787,
        "name": "iPhone 13 256 ГБ Серебристый",
        "vendorCode": "wb3ha2668w",
        "subjectName": "Смартфоны",
        "brandName": "Apple",
        "metrics": "avgPosition/openCard/addToCart/openToCart/orders/cartToOrder/visibility"
      }
    ],
    "currency": "RUB"
  }
}
```

---

## 7. Search Texts by Item

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/v2/search-report/product/search-texts` |
| 功能 | 获取商品 Top 搜索词 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：1 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `currentPeriod` | 是 | object | 当前周期 |
| `pastPeriod` | 否 | object | 对比周期 |
| `nmIds` | 是 | uint64[]，<=50 | 商品编号列表 |
| `topOrderBy` | 是 | string | Top 搜索词筛选方式：`openCard` / `addToCart` / `openToCart` / `orders` / `cartToOrder` |
| `includeSubstitutedSKUs` | 否 | boolean，默认 true | 是否包含带推广商品查询 |
| `includeSearchTexts` | 否 | boolean，默认 true | 是否包含搜索词查询 |
| `orderBy` | 是 | object | 排序参数 |
| `limit` | 是 | integer | 搜索词数量，标准最大 30；Advanced/Premium Jam 最大 100 |

### 请求示例

```json
{
  "currentPeriod": {"start": "2024-02-10", "end": "2024-02-10"},
  "pastPeriod": {"start": "2024-02-08", "end": "2024-02-08"},
  "nmIds": [162579635, 166699779],
  "topOrderBy": "openToCart",
  "includeSubstitutedSKUs": true,
  "includeSearchTexts": false,
  "orderBy": {"field": "avgPosition", "mode": "asc"},
  "limit": 20
}
```

### 响应核心结构

```json
{
  "data": {
    "items": [
      {
        "text": "костюм",
        "nmId": 211131895,
        "subjectName": "Phones",
        "brandName": "Apple",
        "vendorCode": "wb3ha2668w",
        "name": "iPhone 13 256 ГБ Серебристый",
        "frequency": {"current": 5, "dynamics": 50},
        "weekFrequency": 140,
        "medianPosition": {"current": 5, "dynamics": 50},
        "avgPosition": {"current": 5, "dynamics": 50},
        "openCard": {},
        "addToCart": {},
        "openToCart": {},
        "orders": {},
        "cartToOrder": {},
        "visibility": {}
      }
    ],
    "currency": "RUB"
  }
}
```

---

## 8. Orders and Positions by Item Search Texts

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/v2/search-report/product/orders` |
| 功能 | 获取指定商品在各搜索词下的订单量与搜索排名，按天分组 |
| 最大周期 | 7 天 |
| 历史范围 | 最多查询请求时刻前 365 天 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：1 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `period` | 是 | object | 查询周期，最大 7 天 |
| `nmId` | 是 | uint64 | WB 商品编号 |
| `searchTexts` | 是 | string[]，1..30 | 搜索词列表；Advanced/Premium Jam 最大 100 |

### 请求示例

```json
{
  "period": {"start": "2024-02-10", "end": "2024-02-10"},
  "nmId": 211131895,
  "searchTexts": ["костюм", "пиджак"]
}
```

### 响应核心结构

```json
{
  "data": {
    "total": [
      {"dt": "2024-02-10", "avgPosition": 10, "orders": 20}
    ],
    "items": [
      {
        "text": "string",
        "frequency": 0,
        "dateItems": [
          {"dt": "2024-02-10", "avgPosition": 10, "orders": 20}
        ]
      }
    ]
  }
}
```

---

# Stocks Report 库存报告

用于获取库存指标报告，包括当前 WB 仓库存、商品组库存、商品库存、尺码库存、仓库维度库存等。

库存报告中的库存通常展示当前日数据。若需最近 3 个月按日库存历史，可使用 Seller Analytics CSV 的 `STOCK_HISTORY_DAILY_CSV`。

## 9. WB Warehouses Inventory

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/analytics/v1/stocks-report/wb-warehouses` |
| 功能 | 获取当前 WB 仓库库存 |
| Token | Personal / Service |
| 数据更新 | 每 30 分钟 |
| 说明 | 1 行响应代表 1 个商品尺码在 1 个 WB 仓库中的数据 |
| 限流 | 3 req/min，burst 1 |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `nmIds` | 否 | int64[]，0..1000 | WB 商品编号 |
| `chrtIds` | 否 | int64[] | 尺码 ID，仅用于 `nmIds` 中指定商品 |
| `limit` | 否 | uint32，<=250000，默认 250000 | 返回行数 |
| `offset` | 否 | uint32，默认 0 | 偏移量 |

### 请求示例

```json
{
  "nmIds": [111222333, 47254354],
  "chrtIds": [111222333, 91663228],
  "limit": 250000,
  "offset": 500000
}
```

### 响应核心结构

```json
{
  "data": {
    "items": [
      {
        "nmId": 47254354,
        "chrtId": 91663228,
        "warehouseId": 507,
        "warehouseName": "Коледино",
        "regionName": "Центральный",
        "quantity": 43,
        "inWayToClient": 14,
        "inWayFromClient": 11
      }
    ]
  }
}
```

---

## 10. Group Data

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/v2/stocks-report/products/groups` |
| 功能 | 按商品组生成库存数据。商品组由 `subjectID + brandName + tagID` 组成 |
| 数据更新 | 每小时 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：2 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `nmIDs` | 否 | int64[] | 商品编号过滤 |
| `subjectIDs` | 否 | int32[] | 子类目过滤 |
| `brandNames` | 否 | string[] | 品牌过滤 |
| `tagIDs` | 否 | int64[] | 标签过滤 |
| `currentPeriod` | 是 | object | 查询周期 |
| `stockType` | 是 | string | `""` 全部；`wb` WB 仓；`mp` 卖家仓 |
| `skipDeletedNm` | 是 | boolean | 是否跳过已删除商品 |
| `availabilityFilters` | 是 | string[] | 库存状态过滤 |
| `orderBy` | 是 | object | 排序参数 |
| `limit` | 否 | uint32，<=1000，默认 100 | 返回组数量 |
| `offset` | 是 | uint32 | 偏移量 |

`availabilityFilters` 可选值：

| 值 | 含义 |
|---|---|
| `deficient` | Low stock，库存不足 |
| `actual` | Selling well，销售良好 |
| `balanced` | Selling steadily，销售稳定 |
| `nonActual` | Selling poorly，销售较差 |
| `nonLiquid` | Struggling，滞销 |
| `invalidData` | Not calculated，未计算 |

### 响应核心结构

```json
{
  "data": {
    "groups": [
      {
        "subjectID": 123456789,
        "subjectName": "Кружка",
        "brandName": "Крутая посуда",
        "tagID": 12345,
        "tagName": "Человек-Паук",
        "metrics": {},
        "items": []
      }
    ],
    "currency": "RUB"
  }
}
```

核心库存指标包括：`ordersCount`、`ordersSum`、`avgOrders`、`buyoutCount`、`buyoutSum`、`buyoutPercent`、`stockCount`、`stockSum`、`saleRate`、`avgStockTurnover`、`toClientCount`、`fromClientCount`、`lostOrdersCount`、`lostOrdersSum`、`lostBuyoutsCount`、`lostBuyoutsSum`。

---

## 11. Item Data

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/v2/stocks-report/products/products` |
| 功能 | 按商品获取库存数据。无过滤时可获取整个报告 |
| 数据更新 | 每小时 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：2 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `nmIDs` | 否 | int64[] | 商品编号过滤 |
| `subjectID` | 否 | int32 | 子类目 ID |
| `brandName` | 否 | string | 品牌 |
| `tagID` | 否 | int64 | 标签 ID |
| `currentPeriod` | 是 | object | 查询周期 |
| `stockType` | 是 | string | `""` / `wb` / `mp` |
| `skipDeletedNm` | 是 | boolean | 是否跳过已删除商品 |
| `orderBy` | 是 | object | 排序参数 |
| `availabilityFilters` | 是 | string[] | 库存状态过滤 |
| `limit` | 否 | uint32，<=1000，默认 100 | 返回商品数量 |
| `offset` | 是 | uint32 | 偏移量 |

### 响应核心结构

```json
{
  "data": {
    "items": [
      {
        "nmID": 123456789,
        "isDeleted": false,
        "subjectName": "Принтеры",
        "name": "Печатник 3000",
        "vendorCode": "pechatnik3000",
        "brandName": "Компик",
        "hasSizes": true,
        "metrics": {
          "ordersCount": 100,
          "stockCount": 50,
          "availability": "deficient"
        }
      }
    ],
    "currency": "RUB"
  }
}
```

---

## 12. Size Data

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/v2/stocks-report/products/sizes` |
| 功能 | 按商品尺码获取库存数据，可选择是否包含仓库明细 |
| 数据更新 | 每小时 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：2 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `nmID` | 是 | int64 | WB 商品编号 |
| `currentPeriod` | 是 | object | 查询周期 |
| `stockType` | 是 | string | `""` / `wb` / `mp` |
| `orderBy` | 是 | object | 排序参数 |
| `includeOffice` | 是 | boolean | 是否包含仓库明细 |

### 特殊响应规则

| 商品情况 | `includeOffice` | 响应 |
|---|---:|---|
| 商品有尺码 | true | 返回各尺码库存，并嵌套仓库明细 |
| 商品有尺码 | false | 返回各尺码库存，不含仓库明细 |
| 商品无尺码 | true | 返回仓库明细，不返回尺码库存 |
| 商品无尺码 | false | 响应为空 |

> 商品无尺码指 `techSize: "0"`，在商品库存接口中表现为 `hasSizes: false`。

### 响应核心结构

```json
{
  "data": {
    "offices": [
      {
        "regionName": "Центральный",
        "officeID": 123456,
        "officeName": "Коледино",
        "metrics": {}
      }
    ],
    "sizes": [
      {
        "name": "50",
        "chrtID": 123321,
        "offices": [],
        "metrics": {}
      }
    ],
    "currency": "RUB"
  }
}
```

---

## 13. Warehouse Data

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/v2/stocks-report/offices` |
| 功能 | 按仓库获取库存数据 |
| 数据更新 | 每小时 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：2 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `nmIDs` | 否 | int64[] | 商品编号过滤 |
| `subjectIDs` | 否 | int32[] | 子类目过滤 |
| `brandNames` | 否 | string[] | 品牌过滤 |
| `tagIDs` | 否 | int64[] | 标签过滤 |
| `currentPeriod` | 是 | object | 查询周期 |
| `stockType` | 是 | string | `""` / `wb` / `mp` |
| `skipDeletedNm` | 是 | boolean | 是否跳过已删除商品 |

### 响应核心结构

```json
{
  "data": {
    "regions": [
      {
        "regionName": "Центральный",
        "metrics": {
          "stockCount": 20,
          "stockSum": 20000,
          "saleRate": {"days": 5, "hours": 15},
          "toClientCount": 30,
          "fromClientCount": 40
        },
        "offices": [
          {
            "officeID": 123456,
            "officeName": "Коледино",
            "metrics": {}
          }
        ]
      }
    ],
    "currency": "RUB"
  }
}
```

> 卖家仓库存以聚合形式返回，通常 `regionName` 为 `Маркетплейс`，`offices` 为空数组。

---

# Item Rating 商品评分

## 14. Get Report

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/analytics/v1/item-rating` |
| 功能 | 获取商品评分报告 |
| Token | Personal / Service |
| 数据更新 | 每小时 |
| 限流 | 3 req/min |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `currentPeriod` | 是 | object | 当前周期 |
| `pastPeriod` | 否 | object | 对比周期，天数小于或等于当前周期 |
| `nmIds` | 否 | int32[]，<=50 | 商品编号过滤 |
| `subjectIds` | 否 | int32[]，<=50 | 子类目过滤 |
| `brandNames` | 否 | string[]，<=50 | 品牌过滤 |
| `tagIds` | 否 | int64[]，<=50 | 标签过滤 |
| `isNotIncludeNMsWithoutSales` | 否 | boolean，默认 false | 是否不统计无销量商品 |
| `orderBy` | 是 | object | 排序参数 |
| `limit` | 否 | uint32，<=1000，默认 100 | 返回商品数量 |
| `offset` | 是 | uint32 | 偏移量 |

### 请求示例

```json
{
  "currentPeriod": {"start": "2026-02-10", "end": "2026-02-10"},
  "pastPeriod": {"start": "2026-02-08", "end": "2026-02-08"},
  "nmIds": [162579635, 166699779],
  "subjectIds": [232, 1364],
  "brandNames": ["Abikas", "Tike"],
  "tagIds": [3, 5, 6],
  "isNotIncludeNMsWithoutSales": true,
  "orderBy": {"field": "feedbackCount", "mode": "desc"},
  "limit": 130,
  "offset": 50
}
```

### 响应核心结构

```json
{
  "data": {
    "sellerRating": {"current": 3.56, "dynamics": 0.03},
    "feedbackIncrease": {
      "current": 26,
      "total": 116,
      "dynamics": 23,
      "fiveStar": {},
      "fourStar": {},
      "threeStar": {},
      "twoStar": {},
      "oneStar": {}
    },
    "cards": [
      {
        "nmId": 123456789,
        "title": "iPh 17 512 ГБ Серебристый",
        "vendorCode": "wb3ha2668w",
        "subjectId": 50,
        "subjectName": "Phones",
        "brandName": "Attlee",
        "tagName": "Phones",
        "tagId": 65,
        "pinnedFeedback": true,
        "rating": 10,
        "feedbackRating": {"current": 3.87, "dynamics": 0.31, "percentile": 1.7},
        "feedbackCount": {"current": 12, "dynamics": 9},
        "disqualified": 7
      }
    ]
  }
}
```

---

# Seller Analytics CSV 卖家分析 CSV 报告

用于创建、查询、重试和下载 CSV 格式的卖家分析报告。

## CSV 报告流程

1. 使用 `POST /api/v2/nm-report/downloads` 创建报告生成任务。
2. 使用 `GET /api/v2/nm-report/downloads` 查询报告状态。
3. 如状态为 `FAILED`，使用 `POST /api/v2/nm-report/downloads/retry` 重新生成。
4. 报告成功后，使用 `GET /api/v2/nm-report/downloads/file/{downloadId}` 下载 ZIP 压缩包，内部为 CSV 文件。

### 重要限制

| 限制 | 内容 |
|---|---|
| 最大查询周期 | 普通分析报告最多 1 年 |
| 库存报告周期 | 最多 3 个月 |
| 每日生成上限 | 20 个报告/天 |
| 报告保留时间 | 报告生成成功后保留 48 小时 |
| Jam 订阅 | 除库存报告外，大多数 CSV 分析报告需要 Jam 订阅 |

### 支持的报告类型

| `reportType` | 说明 |
|---|---|
| `DETAIL_HISTORY_REPORT` | 销售漏斗报告，按 WB 商品编号分组 |
| `GROUPED_HISTORY_REPORT` | 销售漏斗报告，按类目/品牌/标签分组 |
| `SEARCH_QUERIES_PREMIUM_REPORT_GROUP` | 搜索查询报告，按分组 |
| `SEARCH_QUERIES_PREMIUM_REPORT_PRODUCT` | 搜索查询报告，按商品 |
| `SEARCH_QUERIES_PREMIUM_REPORT_TEXT` | 搜索词报告 |
| `STOCK_HISTORY_REPORT_CSV` | 库存指标历史报告 |
| `STOCK_HISTORY_DAILY_CSV` | 每日库存历史报告 |

---

## 15. Create the Report

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/v2/nm-report/downloads` |
| 功能 | 创建高级卖家分析 CSV 报告生成任务 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：1 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `id` | 是 | uuid string | 报告 ID，由卖家生成，必须唯一 |
| `reportType` | 是 | string | 报告类型，见上方报告类型表 |
| `userReportName` | 否 | string | 报告名称；不传则自动生成 |
| `params` | 是 | object | 报告参数，不同 `reportType` 参数不同 |

> 不要对不同报告复用同一个 `id`，否则可能导致生成错误。`includeSubstitutedSKUs` 和 `includeSearchTexts` 不能同时为 `false`。

### 请求示例：销售漏斗按商品报告

```json
{
  "id": "06eae887-9d9f-491f-b16a-bb1766fcb8d2",
  "reportType": "DETAIL_HISTORY_REPORT",
  "userReportName": "Listing report",
  "params": {
    "nmIDs": [1234567],
    "subjectIds": [1234567],
    "brandNames": ["Name"],
    "tagIds": [1234567],
    "startDate": "2024-06-21",
    "endDate": "2024-06-23",
    "timezone": "Europe/Moscow",
    "aggregationLevel": "day",
    "skipDeletedNm": false
  }
}
```

### 响应示例

```json
{
  "data": "Началось формирование файла/отчета"
}
```

---

## 16. Get the Reports List

| 项目 | 内容 |
|---|---|
| Method | `GET` |
| Endpoint | `/api/v2/nm-report/downloads` |
| 功能 | 获取报告列表与生成状态 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：1 req/hour |

### Query 参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `filter[downloadIds]` | 否 | uuid[] | 报告 ID 过滤 |

### 响应核心结构

```json
{
  "data": [
    {
      "id": "06eae887-9d9f-491f-b16a-bb1766fcb8d2",
      "createdAt": "2024-06-26 20:05:32",
      "status": "SUCCESS",
      "name": "Card report",
      "size": 123,
      "startDate": "2024-06-21",
      "endDate": "2023-04-23"
    }
  ]
}
```

常见状态：`SUCCESS`、`FAILED`、生成中状态以接口实际返回为准。

---

## 17. Regenerate the Report

| 项目 | 内容 |
|---|---|
| Method | `POST` |
| Endpoint | `/api/v2/nm-report/downloads/retry` |
| 功能 | 当报告生成失败时，重新创建生成任务 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：1 req/hour |

### 请求参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `downloadId` | 是 | uuid string | 报告 ID |

### 请求示例

```json
{
  "downloadId": "06eea887-9d9f-491f-b16a-bb1766fcb8d2"
}
```

### 响应示例

```json
{
  "data": "Retry"
}
```

---

## 18. Get the Report

| 项目 | 内容 |
|---|---|
| Method | `GET` |
| Endpoint | `/api/v2/nm-report/downloads/file/{downloadId}` |
| 功能 | 下载指定报告 ID 对应的 CSV 报告 ZIP 文件 |
| 响应类型 | `application/zip` |
| 可下载时间 | 报告生成成功后 48 小时内 |
| 限流 | Personal / Service / Base with secret：3 req/min；Base：1 req/hour |

### Path 参数

| 参数 | 必填 | 类型 | 说明 |
|---|---:|---|---|
| `downloadId` | 是 | uuid string | 报告 ID |

### CSV 内容示例

```csv
nmID,dt,openCardCount,addToCartCount,ordersCount,ordersSumRub,buyoutsCount,buyoutsSumRub,cancelCount,cancelSumRub,addToCartConversion,cartToOrderConversion,buyoutPercent,addToWishlist,currency
70027655,2024-11-21,1,0,0,0,0,0,0,0,0,0,0,0,RUB
...
150317666,2024-11-21,2,0,0,0,0,0,0,0,0,0,0,0,RUB
```

---

## 附录：接口清单

| # | 分类 | Method | Endpoint | 功能 |
|---:|---|---|---|---|
| 1 | Sales Funnel | POST | `/api/analytics/v3/sales-funnel/products` | 周期商品销售漏斗统计 |
| 2 | Sales Funnel | POST | `/api/analytics/v3/sales-funnel/products/history` | 按天/周商品销售漏斗统计 |
| 3 | Sales Funnel | POST | `/api/analytics/v3/sales-funnel/grouped/history` | 按分组的商品销售漏斗历史统计 |
| 4 | Search Queries | POST | `/api/v2/search-report/report` | 搜索查询主报告 |
| 5 | Search Queries | POST | `/api/v2/search-report/table/groups` | 分组分页 |
| 6 | Search Queries | POST | `/api/v2/search-report/table/details` | 分组内商品分页 |
| 7 | Search Queries | POST | `/api/v2/search-report/product/search-texts` | 商品 Top 搜索词 |
| 8 | Search Queries | POST | `/api/v2/search-report/product/orders` | 搜索词订单与排名 |
| 9 | Stocks Report | POST | `/api/analytics/v1/stocks-report/wb-warehouses` | WB 仓库当前库存 |
| 10 | Stocks Report | POST | `/api/v2/stocks-report/products/groups` | 商品组库存数据 |
| 11 | Stocks Report | POST | `/api/v2/stocks-report/products/products` | 商品库存数据 |
| 12 | Stocks Report | POST | `/api/v2/stocks-report/products/sizes` | 尺码库存数据 |
| 13 | Stocks Report | POST | `/api/v2/stocks-report/offices` | 仓库库存数据 |
| 14 | Item Rating | POST | `/api/analytics/v1/item-rating` | 商品评分报告 |
| 15 | Seller Analytics CSV | POST | `/api/v2/nm-report/downloads` | 创建 CSV 报告 |
| 16 | Seller Analytics CSV | GET | `/api/v2/nm-report/downloads` | 获取报告列表 |
| 17 | Seller Analytics CSV | POST | `/api/v2/nm-report/downloads/retry` | 重新生成报告 |
| 18 | Seller Analytics CSV | GET | `/api/v2/nm-report/downloads/file/{downloadId}` | 下载报告文件 |
