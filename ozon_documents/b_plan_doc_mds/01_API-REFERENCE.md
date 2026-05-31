# Ozon API 参考手册 — ecommerce-analytics

> 版本: 2026-05-13 | 语言: 中文为主，端点名保留原文
> 涵盖本项目实际使用的全部 API 端点、认证方式、posting_number 语义、白俄判定、已知陷阱与调用顺序。

---

## 目录

1. [两套 API 概览](#1-两套-api-概览)
2. [认证方式](#2-认证方式)
3. [Ozon Seller API 端点](#3-ozon-seller-api-端点)
   - [POST /v1/finance/accrual/types](#31-post-v1financeaccrualtypes)
   - [POST /v1/finance/accrual/by-day](#32-post-v1financeaccrualby-day)
   - [POST /v2/posting/fbo/get](#33-post-v2postingfboget)
   - [POST /v3/posting/fbs/get](#34-post-v3postingfbsget)
   - [CrossDock 越库链路](#35-crossdock-越库链路)
4. [Ozon Performance API 端点](#4-ozon-performance-api-端点)
   - [POST /api/client/token](#41-post-apiclienttoken)
   - [POST /api/client/statistics/json](#42-post-apiclientstatisticsjson)
   - [POST /api/client/statistic/products/generate](#43-post-apiclientstatisticproductsgenerate)
   - [GET /api/client/campaign/{id}/objects](#44-get-apiclientcampaignidobjects)
5. [posting_number 格式](#5-posting_number-格式)
6. [白俄判定逻辑](#6-白俄判定逻辑)
7. [费用类型码表](#7-费用类型码表)
8. [已知陷阱与注意事项](#8-已知陷阱与注意事项)
9. [典型调用顺序](#9-典型调用顺序)

---

## 1. 两套 API 概览

| 项目 | Ozon Seller API | Ozon Performance API |
|---|---|---|
| **Base URL** | `https://api-seller.ozon.ru` | `https://api-performance.ozon.ru` |
| **用途** | 财务计费、订单详情、仓储 | 广告投放数据与报告 |
| **认证** | Header: `Client-Id` + `Api-Key` | Header: `Authorization: Bearer <token>` |
| **密钥获取** | 卖家后台 → 设置 → Seller API → 生成密钥 | 卖家后台 → 设置 → API-密钥 → Performance API → 创建新密钥 |
| **密钥有效期** | 6 个月 | client_secret 永不过期，token 每 30 分钟刷新 |
| **速率限制** | 50 req/s 每 Client ID | 每日 100,000 请求；同时 1 个异步报告 |
| **语言时区** | 俄语；UTC | 俄语；UTC / MSK (+03:00) |

---

## 2. 认证方式

### 2.1 Seller API — Client-Id / Api-Key

每个请求均带三个 HTTP 头：

```
POST /v1/finance/accrual/by-day HTTP/1.1
Host: api-seller.ozon.ru
Client-Id: 123456
Api-Key: abc123...
Content-Type: application/json
```

环境变量：
- `OZON_CLIENT_ID` — 数字 Client ID
- `OZON_API_KEY` — API 密钥字符串

**安全检查**: 请求必须走 back-to-back (CORS 禁止浏览器直连)。所有时间戳为 UTC。

> ⚠️ v3 财务接口 `/v3/finance/transaction/list` 和 `/v3/finance/transaction/totals` 将于 **2026-07-06 关闭**。必须迁移到 v1 accrual 系列。

### 2.2 Performance API — Bearer Token

两步流程：

**Step 1** — 获取 token：

```
POST https://api-performance.ozon.ru/api/client/token
Content-Type: application/json

{
  "client_id": "XYZ@advertising.performance.ozon.ru",
  "client_secret": "b1u5XXDQW3wEqQ7dG...ancMyuhQtMNBI",
  "grant_type": "client_credentials"
}
```

响应 (HTTP 200)：

```json
{
  "access_token": "eyJhbG...hVVU...qTz2XXZBv41h4",
  "expires_in": 1800,
  "token_type": "Bearer"
}
```

- `expires_in` 单位为秒，典型 1800 (30 分钟)。
- 建议过期前 60 秒续期。

**Step 2** — 后续请求带 Bearer token：

```
GET /api/client/statistics/{UUID} HTTP/1.1
Host: api-performance.ozon.ru
Authorization: Bearer eyJhbG...hVVU...qTz2XXZBv41h4
```

环境变量：
- `OZON_PERF_CLIENT_ID`
- `OZON_PERF_SECRET`

---

## 3. Ozon Seller API 端点

### 3.1 POST /v1/finance/accrual/types

**用途**: 获取费用类型码表（一次性，建议本地缓存）。

**URL**: `https://api-seller.ozon.ru/v1/finance/accrual/types`

**方法**: POST

**请求头**:
```
Client-Id: <client_id>
Api-Key: <api_key>
Content-Type: application/json
```

**请求体**: 空对象 (payload 必须有，但内容可为空)

```json
{}
```

**返回格式 (HTTP 200)**:

```json
{
  "accrual_types": [
    {
      "id": 1,
      "name": "Acquiring",
      "description": "Эквайринг"
    },
    {
      "id": 32,
      "name": "Logistic",
      "description": "Логистика"
    },
    {
      "id": 69,
      "name": "SaleCommission",
      "description": "Комиссия за продажу"
    },
    {
      "id": 29,
      "name": "LastMileCourier",
      "description": "Доставка до места выдачи"
    },
    {
      "id": 16,
      "name": "Drop-Off",
      "description": "Обработка отправления Drop-off"
    },
    {
      "id": 12,
      "name": "CrossDock",
      "description": "Кросс-докинг"
    },
    {
      "id": 41,
      "name": "PPC",
      "description": "Оплата за клик"
    },
    {
      "id": 54,
      "name": "Promotion",
      "description": "Продвижение с оплатой за заказ"
    },
    {
      "id": 9,
      "name": "ClientReturn",
      "description": "Обработка возвратов"
    },
    {
      "id": 59,
      "name": "ReturnFlowLogistic",
      "description": "Обратная логистика"
    },
    {
      "id": 98,
      "name": "DeliveryToHandoverPlaceByOzon",
      "description": "Доставка до места передачи Ozon"
    }
  ]
}
```

**本地缓存**: 保存到 `data/ozon_accrual_types.json`（`{type_id: {name, desc}}`）。

**type_id=0**: 码表中不存在。本项目约定 `type_id=0` 表示 `SaleRevenue`（销售收入）。正值为销售入账，负值为退货冲正。这是 `/by-day` 返回的合成值，不为 API 原始枚举。

---

### 3.2 POST /v1/finance/accrual/by-day

**用途**: 按日拉取全部计费明细（β 版，替代弃用的 `/v3/finance/transaction/list`）。

**URL**: `https://api-seller.ozon.ru/v1/finance/accrual/by-day`

**方法**: POST

**请求头**: 同 3.1

**请求体**:

```json
{
  "date": "2026-05-04"
}
```

`date` 格式: `YYYY-MM-DD` (UTC)。

**返回格式 (HTTP 200)**:

```json
{
  "accruals": [
    {
      "accrued_category": "POSTING",
      "accrual_date": "2026-05-04",
      "date": "2026-05-04",
      "unit_number": "58948498-0312-1",
      "posting": {
        "products": [
          {
            "sku": 3583442225,
            "name": "Товар Пример",
            "quantity": 1,
            "commission": {
              "seller_price": {
                "amount": "9600.00",
                "currency_code": "RUB"
              },
              "sale_commission": {
                "amount": "-720.00",
                "currency_code": "RUB"
              }
            },
            "delivery": {
              "services": [
                {
                  "type_id": 32,
                  "name": "Logistic",
                  "accrued": {
                    "amount": "-297.00",
                    "currency_code": "RUB"
                  }
                },
                {
                  "type_id": 98,
                  "name": "DeliveryToHandoverPlaceByOzon",
                  "accrued": {
                    "amount": "-25.00",
                    "currency_code": "RUB"
                  }
                },
                {
                  "type_id": 29,
                  "name": "LastMileCourier",
                  "accrued": {
                    "amount": "-7.48",
                    "currency_code": "RUB"
                  }
                }
              ]
            }
          }
        ]
      }
    },
    {
      "accrued_category": "ITEM",
      "date": "2026-05-04",
      "unit_number": "58948498-0312-1",
      "item_fees": {
        "fees": [
          {
            "sku": 3583442225,
            "fees": [
              {
                "type_id": 1,
                "name": "Acquiring",
                "accrued": {
                  "amount": "-187.09",
                  "currency_code": "RUB"
                }
              }
            ]
          }
        ]
      }
    },
    {
      "accrued_category": "NON_ITEM",
      "date": "2026-05-04",
      "unit_number": "0179168565-0122-1",
      "non_item_fee": {
        "type_id": 94,
        "name": "DefectFineShipmentDelayRate",
        "accrued": {
          "amount": "-95.00",
          "currency_code": "RUB"
        }
      }
    }
  ]
}
```

**三种 accrued_category**:

| category | 含义 | 结构路径 | 有 SKU? |
|---|---|---|---|
| `POSTING` | 按订单的发货/退货计费 | `posting.products[]` → `commission` + `delivery.services[]` | 是 |
| `ITEM` | 按 SKU 维度的费用 | `item_fees.fees[]` → `fees[]` | 是 |
| `NON_ITEM` | 无 SKU 关联的费用 | `non_item_fee` | 否 |

**POSTING 内费用映射**:

| 数据路径 | type_id | 含义 |
|---|---|---|
| `commission.seller_price.amount` | 0 (合成) | 销售收入 (正)/退货冲正 (负) |
| `commission.sale_commission.amount` | 69 | 平台佣金 |
| `delivery.services[].type_id` | 32 | 物流费 (Logistic) |
| `delivery.services[].type_id` | 29 | 末端配送 (LastMileCourier) |
| `delivery.services[].type_id` | 16 | Drop-off 处理费 |
| `delivery.services[].type_id` | 98 | 到交接点配送 |

**归一化 CSV 列**: `date,type_id,type_name,amount,sku,posting_number,category`

**amount 符号**: Ozon 原始数据中费用为负数（扣款），收入为正数。本项目保持原始符号。

**典型调用**: 按天遍历日期范围，逐日拉取 → 归一化 → 保存 CSV（见 `src/ozon_fetcher_v1.py`）。

---

### 3.3 POST /v2/posting/fbo/get

**用途**: 查询单个 FBO 订单的详细信息，含配送城市（用于白俄判定）。

**URL**: `https://api-seller.ozon.ru/v2/posting/fbo/get`

**方法**: POST

**请求头**: 同 3.1

**请求体**:

```json
{
  "posting_number": "20725003-0450-2",
  "with": {
    "analytics_data": true
  }
}
```

`with.analytics_data: true` — 必须开启，否则不返回 `city` 字段。

**返回格式 (HTTP 200)**:

```json
{
  "result": {
    "posting_number": "20725003-0450-2",
    "order_id": 20725003,
    "order_number": "20725003-0450",
    "status": "delivered",
    "delivery_schema": "FBO",
    "warehouse_name": "ПЕТРОВСКОЕ_РФЦ",
    "analytics_data": {
      "city": "Тюмень",
      "region": "Тюменская область",
      "delivery_type": "PVZ",
      "warehouse_name": "ПЕТРОВСКОЕ_РФЦ",
      "client_delivery_date_begin": "2026-04-30T00:00:00Z",
      "client_delivery_date_end": "2026-05-05T00:00:00Z"
    },
    "financial_data": {
      "products": [
        {
          "product_id": 3583442225,
          "price": "9600.00",
          "quantity": 1
        }
      ]
    }
  }
}
```

**关键字段**:
- `result.delivery_schema`: `"FBO"` / `"FBS"` / `"RFBS"`
- `result.analytics_data.city`: 城市名（俄语）
- `result.warehouse_name`: 仓库名（含城市前缀）

**HTTP 错误处理**: FBO 查询 404 → 应 fallback 到 FBS (见 3.4)。

---

### 3.4 POST /v3/posting/fbs/get

**用途**: FBO 查询失败时的 fallback。覆盖 FBS/rFBS 订单。

**URL**: `https://api-seller.ozon.ru/v3/posting/fbs/get`

**方法**: POST

**请求头**: 同 3.1

**请求体** (与 FBO 格式相同):

```json
{
  "posting_number": "58948498-0312-1",
  "with": {
    "analytics_data": true
  }
}
```

**返回格式 (HTTP 200)**:

```json
{
  "result": {
    "posting_number": "58948498-0312-1",
    "status": "delivered",
    "delivery_schema": "FBS",
    "warehouse_name": "МИНСК_МПСЦ",
    "delivery_method": {
      "name": "Доставка в ПВЗ (Минск)",
      "warehouse_name": "МИНСК_МПСЦ"
    },
    "analytics_data": {
      "city": "Минск",
      "region": "Минская область",
      "delivery_type": "PVZ"
    }
  }
}
```

**关键差异**: FBS 有 `delivery_method.name` 字段，在白俄判定时作为 `warehouse_name` 前缀匹配失败时的兜底。

**并发**: 生产代码使用 20 线程并发查询目的地（见 `scripts/query_destinations.py`）。每个查询先 FBO 后 FBS，10 秒超时。

---

### 3.5 CrossDock 越库链路

**用途**: 将 NON_ITEM 中的 CrossDock 费用分摊到供应订单内的 SKU。

CrossDock 费用在 `/by-day` 中以 `NON_ITEM` 类别出现，`posting_number` 字段存储的是 **供应订单号**（supply order number），而非 posting 号。

**三步链路**:

**Step 1** — `POST /v3/supply-order/list` — 按订单号前缀模糊搜索

URL: `https://api-seller.ozon.ru/v3/supply-order/list`
请求体:

```json
{
  "filter": {
    "states": ["COMPLETED", "ACCEPTED_AT_STORAGE_WAREHOUSE", "REPORTS_CONFIRMATION_AWAITING"],
    "order_number_search": "0117355694"
  },
  "limit": 20,
  "sort_by": "ORDER_CREATION",
  "sort_dir": "DESC"
}
```

返回:

```json
{
  "order_ids": ["abc123-def456"]
}
```

**Step 2** — `POST /v3/supply-order/get` — 获取供应订单详情，取 `is_crossdock=true` 的 `bundle_id`

URL: `https://api-seller.ozon.ru/v3/supply-order/get`
请求体:

```json
{
  "order_ids": ["abc123-def456"]
}
```

返回 `orders[].supplies[]` → 找到 `is_crossdock: true` → 取 `bundle_id`。

**Step 3** — `POST /v1/supply-order/bundle` — 获取 bundle 内的 SKU 及数量

URL: `https://api-seller.ozon.ru/v1/supply-order/bundle`
请求体:

```json
{
  "bundle_ids": ["bundle_id_here"],
  "limit": 100,
  "is_asc": true
}
```

返回:

```json
{
  "items": [
    {"sku": "3583442225", "quantity": 1},
    {"sku": "3590307092", "quantity": 2}
  ]
}
```

**分摊**: 费用按 `quantity / total_quantity` 比例分给各 SKU。

**缓存**: 解析结果缓存到 `_CROSSDOCK_CACHE` (进程内 dict)，避免重复 API 调用。

---

## 4. Ozon Performance API 端点

### 4.1 POST /api/client/token

见 [2.2 认证方式](#22-performance-api--bearer-token)。

---

### 4.2 POST /api/client/statistics/json

**(内部路径 `/statistics/json`，Swagger 中为 `POST /api/client/statistics`)**

**用途**: 获取 PPC（Оплата за клик）广告活动的 per-SKU 精确支出。返回按 campaign 聚合的每日报告 JSON。

**URL**: `https://api-performance.ozon.ru/api/client/statistics/json`

**方法**: POST

**请求头**:
```
Authorization: Bearer <token>
Content-Type: application/json
```

**请求体**:

```json
{
  "campaigns": ["23118435", "23569936", "23684639"],
  "dateFrom": "2026-04-27",
  "dateTo": "2026-05-03",
  "groupBy": "DATE"
}
```

参数:
- `campaigns`: PayPerClick 活动 ID 列表（每个字符串）。**最多 10 个**（API 硬限制）。
- `dateFrom` / `dateTo`: `YYYY-MM-DD` 格式（注意：`/statistics` 用 `dateFrom/dateTo`，**不是** `from/to`）。
- `groupBy`: `"DATE"` — 按天分组。

**返回 (HTTP 200)**: 异步，返回 UUID，结构与 `/statistic/products/generate` 相同（见 4.3）。

```json
{
  "UUID": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**异步流程**: 提交 → 返回 UUID → `GET /api/client/statistics/{UUID}` 轮询 → 状态 `OK` → `GET /api/client/statistics/report?UUID={UUID}` 下载。

**下载 JSON 格式** (report ready):

```json
{
  "23118435": {
    "title": "Кампания Товар А",
    "report": {
      "rows": [
        {
          "date": "2026-04-27",
          "sku": "2639989504",
          "moneySpent": "1984.14",
          "views": "15230",
          "clicks": "345",
          "ctr": "2.27"
        },
        {
          "date": "2026-04-28",
          "sku": "2639989504",
          "moneySpent": "0.00",
          "views": "0",
          "clicks": "0",
          "ctr": "0.00"
        }
      ],
      "totals": {
        "moneySpent": "1984.14",
        "views": "15230",
        "clicks": "345"
      }
    }
  }
}
```

**每行关键字段**:
- `date`: 日期 YYYY-MM-DD
- `sku`: SKU 字符串
- `moneySpent`: PPC 花费 (₽)
- `views`: 展示数
- `clicks`: 点击数
- `ctr`: 点击率

**归属策略**: 用 `rows` 按 SKU 聚合原始值 → 与 `totals.moneySpent` 按比例缩放（消除日舍入误差）→ 得到 per-SKU 精确 PPC 支出。

**批量**: 每批 ≤10 个 campaign，批次间间隔 2 秒避免 429。

**限制**:
- 同时 1 个异步报告
- 每日 100,000 请求
- 日期范围 ≤62 天
- 每报告 ≤10 个 campaign

---

### 4.3 POST /api/client/statistic/products/generate

**用途**: 获取 SEARCH_PROMO（Оплата за заказ + Комбо-модель）的 per-SKU 推广支出。无需 campaign ID。

**URL**: `https://api-performance.ozon.ru/api/client/statistic/products/generate`

**方法**: POST

**请求头**: 同 4.2

**请求体**:

```json
{
  "from": "2026-04-28T00:00:00+03:00",
  "to": "2026-05-11T23:59:59+03:00"
}
```

> ⚠️ **关键**: 此端点使用 `from/to` (RFC 3339 格式)，不是 `dateFrom/dateTo`！时区通常用 MSK (+03:00)。

**返回 (HTTP 200)**:

```json
{
  "UUID": "b2c3d4e5-f6a7-8901-bcde-f12345678901"
}
```

**异步流程**: 同 `/statistics/json`：提交 → 轮询 → 下载。

**下载 CSV 格式** (分号分隔，UTF-8 BOM):

```csv
﻿Отчёт о расходах на продвижение товаров
SKU;Артикул;Название товара;Категория;Комбо-модель расход;Оплата за заказ расход;Итого расход
2639989504;ART-001;Товар Пример 1;Электроника;1500,00;0,00;1500,00
3590307092;ART-002;Товар Пример 2;Одежда;0,00;2222,24;2222,24
```

**列名映射**:
| 俄语列名 | 含义 | 解析键 |
|---|---|---|
| SKU | SKU | `sku` |
| Артикул | 货号 | `article` |
| Название товара | 商品名 | `product_name` |
| Категория | 类目 | `category` |
| Комбо-модель расход | 组合推广支出 ₽ | `combo_cost` |
| Оплата за заказ расход | 按订单付费支出 ₽ | `cpo_cost` |
| Итого расход | 总推广支出 ₽ | `total_cost` |

**注意**: CSV 第一行为报告标题，第二行为列名，第三行起为数据。解析须跳过标题行，定位含 `SKU` 和 `Расход` 的行作为表头。

**异步轮询细节**:

```
GET /api/client/statistics/{UUID}
```

响应:

```json
{
  "UUID": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
  "state": "PROCESSING"
}
```

`state` 可取值: `PROCESSING` / `OK`(就绪) / `ERROR`(失败) / `SUCCESS` / `READY` / `DONE`。

就绪后下载:

```
GET /api/client/statistics/report?UUID={UUID}
```

超时设置: 最大等待 120 秒，轮询间隔 3 秒。

---

### 4.4 GET /api/client/campaign/{id}/objects

**状态**: ⚠️ **已弃用，仅返回当前快照，不反映历史**

**用途**: 获取活动当前关联的 SKU 列表。

**URL**: `https://api-performance.ozon.ru/api/client/campaign/{campaignId}/objects`

**方法**: GET

**返回格式**:

```json
{
  "list": [
    {"id": "2639989504", "name": "Товар А"},
    {"id": "3590307092", "name": "Товар Б"}
  ]
}
```

**为什么不建议使用**:
- 这是**当前快照**，活动历史上可能投放过但现在已移除的 SKU 不会出现。
- SEARCH_PROMO 类型活动返回空列表。
- 本项目已迁移至 `/statistics/json`（返回历史实际投放的 SKU）。

---

## 5. posting_number 格式

`posting_number` 在 `/by-day` CSV 中出现为三种形式：

### 5.1 三段式 (订单 posting)

格式: `NNNNNNNNN-NNNN-N`

示例: `58948498-0312-1`, `65125770-0023-1`, `0121115652-0010-3`

组成:
- 第一段: 订单号 (8-10 位数字)
- 第二段: posting 序号 (4 位数字)
- 第三段: posting 内商品序号 (1 位数字，从 1 开始)

**匹配键**: 取前两段 `NNNNNNNNN-NNNN` 作为 posting 匹配键，用于将没有 SKU 的收费行（如 Acquiring）按 posting 归属到 SKU。

### 5.2 两段式 (posting 引用)

格式: `71750703-1001`

当第三段无意义或省略时出现。仍可作 posting 匹配。

### 5.3 纯数字 (活动/供应订单号)

格式: 长数字串，如供应商订单号出现在 CrossDock NON_ITEM 行的 `posting_number` 列中。这类不是 posting 号，需要走 CrossDock 三步链路解析。

### 5.4 posting_number 提取规则

从 `/by-day` CSV 中筛选 posting_number 的条件:
- `type_id = "0"` 且 `category = "POSTING"` → 提取为待查目的地列表
- 去重后批次查询 `/v2/posting/fbo/get` (同时 ≤20 并发)

---

## 6. 白俄判定逻辑

### 6.1 白俄城市集合

```python
BELARUS_CITIES = {
    'МИНСК','ГОМЕЛЬ','БРЕСТ','ВИТЕБСК','ГРОДНО','МОГИЛЕВ','МОГИЛЁВ',
    'БАРАНОВИЧИ','ОШМЯНЫ','НОВОПОЛОЦК','БОРИСОВ','МОЗЫРЬ','РЕЧИЦА',
    'БОБРУЙСК','КРУПКИ','ДЗЕРЖИНСК','ОРША','ЛИДА','СОЛИГОРСК','ПОЛОЦК',
    'ЖЛОБИН','СВЕТЛОГОРСК','ПИНСК','СЛУЦК','МОЛОДЕЧНО','ЖОДИНО','КОБРИН',
}
```

### 6.2 判定优先级

1. **city 字段直接匹配** — `analytics_data.city` 转为大写后查 `BELARUS_CITIES`
2. **FBO PVZ 空 city 兜底** — 当 `city` 为空且 schema=FBO 时，取 `warehouse_name` 的第一个下划线前缀，转为大写后查集合。例如 `МИНСК_МПСЦ` → `МИНСК` ∈ 白俄
3. **FBS PVZ 空 city 兜底** — 当 `city` 为空且 schema=FBS 时，用 `delivery_method.name` 做子串匹配。例如 `"Доставка в ПВЗ (Минск)"` 包含 `минск` → 白俄

### 6.3 判定结果缓存

结果写入 `data/order_destination_v2.json`，格式:

```json
{
  "58948498-0312-1": {
    "delivery_schema": "FBO",
    "city": "Москва",
    "is_belarus": false,
    "warehouse": "ПЕТРОВСКОЕ_РФЦ"
  },
  "20725003-0450-2": {
    "delivery_schema": "FBO",
    "city": "Тюмень",
    "is_belarus": false,
    "warehouse": "МИНСК_МПСЦ"
  }
}
```

增量更新：已缓存的不重复查询。

---

## 7. 费用类型码表

本项目使用的核心 type_id：

| type_id | 名称 (en) | 俄语描述 | 含义 |
|---|---|---|---|
| **0** | SaleRevenue | (合成，非 API 枚举) | 销售收入(正)/退货冲正(负) |
| 1 | Acquiring | Эквайринг | 支付手续费 |
| 9 | ClientReturn | Обработка возвратов | 退货处理 |
| 12 | CrossDock | Кросс-докинг | 越库费 |
| 16 | Drop-Off | Обработка отправления Drop-off | Drop-off 处理 |
| 29 | LastMileCourier | Доставка до места выдачи | 末端配送 |
| 32 | Logistic | Логистика | 正向物流 |
| 41 | PPC | Оплата за клик | 按点击付费广告 |
| 45 | PickUpPointReturnAcceptance | Приём возврата в ПВЗ | PVZ 退货接收 |
| 54 | Promotion | Продвижение с оплатой за заказ | 按订单付费推广 |
| 59 | ReturnFlowLogistic | Обратная логистика | 逆向物流 |
| 60 | PartialReturn | Частичный возврат | 部分退货 |
| 61 | Cancellation | Отмена | 取消 |
| 69 | SaleCommission | Комиссия за продажу | 平台佣金 |
| 94 | DefectFineShipmentDelayRate | Штраф за дефекты / задержку | 残次/延迟罚款 |
| 98 | DeliveryToHandoverPlaceByOzon | Доставка до места передачи Ozon | 到交接点配送 |

**退货相关 type_id 集合**: `{59, 45, 9, 60, 61}` — 用于在 `/by-day` 中检测混合 posting（既有正 SaleRevenue 又有退货费），触发 `/postings` 反查补全退货冲正。

完整码表见 `data/ozon_accrual_types.json`（100+ 类型）。

---

## 8. 已知陷阱与注意事项

### 8.1 API 锚点差异

| 端点 | 日期参数格式 |
|---|---|
| `/statistics/json` | `dateFrom` / `dateTo` (YYYY-MM-DD) |
| `/statistic/products/generate` | `from` / `to` (RFC 3339: `2026-04-28T00:00:00+03:00`) |
| `/v1/finance/accrual/by-day` | `date` (YYYY-MM-DD) |

**混用 dateFrom/dateTo 和 from/to 会导致 400 错误或空报告。**

### 8.2 异步报告限制

- **同时 1 个**: Performance API 每个账户同时只能运行 1 个异步报告。提交前请确保上一个已完成。
- 建议先 `/statistics/json`（PC），再 `/statistic/products/generate`（Promotion），串行执行。

### 8.3 campaign_objects 是快照

`GET /api/client/campaign/{id}/objects` 返回当前绑定，不反映历史。活动历史上投放过但已移除的 SKU 不会出现。本项目使用 `/statistics/json` 获取**历史实际投放的 SKU + 花费**。

### 8.4 批量 ZIP 日期失效

报告列表 `/api/client/statistics/list` 返回的批量 ZIP 链接存在日期段失效 bug。生产代码以单次 `/statistics/json` + `/statistic/products/generate` 替代批量导出。

### 8.5 Positive/Negative SaleRevenue 混合 posting

同一个 posting 可能在同一天既有正的 SaleRevenue（销售入账），又有负的 SaleRevenue（退货冲正），同时还有退货费（ReturnFlowLogistic 等）。

此时需要在 `/by-day` 之后，对混合 posting 调用 `/v1/finance/accrual/postings` 反查，补全负 SaleRevenue 行。

`/postings` 请求格式:

```json
{
  "posting_numbers": ["65125770-0023-1", "0159305297-0177"]
}
```

返回含 `seller_price.amount < 0` 的行即为退货冲正，补入 CSV。

### 8.6 CrossDock posting_number 语义差异

NON_ITEM 行的 `posting_number` 字段在 CrossDock 中实际是供应订单号，不是 posting 号。不能用来查询 `/v2/posting/fbo/get`。CrossDock 需要走三步链路（见 3.5）。

### 8.7 白俄仓库名前缀误导

俄罗城市也有以白俄城市名开头的仓库（如 `МИНСК_МПСЦ` 覆盖俄罗斯城市）。因此 `warehouse_name` 前缀匹配**仅在 city 为空时**作为兜底，city 字段优先。

### 8.8 /by-day 的 date 参数为 UTC

按 UTC 日的计费。俄罗斯 MSK (UTC+3) 与 UTC 有 3 小时时差，跨越日期边界时需要注意数据归属。

### 8.9 并发控制

- Seller API: 50 req/s per Client ID
- Performance API: 100,000 req/day
- 查询目的地: 20 线程并发 (FBO + FBS fallback)
- 批次间隔: PPC JSON 批次间 2 秒，避免 429

---

## 9. 典型调用顺序

### 完整流程: 周报生成

```
1. 载入费用类型码表
   POST /v1/finance/accrual/types (-> data/ozon_accrual_types.json 缓存)

2. 按日拉取计费 (7天)
   for day in week:
       POST /v1/finance/accrual/by-day {"date": "YYYY-MM-DD"}
       -> 归一化三种类别 -> 累积

3. 补全退货冲正
   从归一化行中检测混合 posting
   -> POST /v1/finance/accrual/postings (批量 50)
   -> 补入负 SaleRevenue 行

4. 查询目的地
   从 type_id=0, category=POSTING 提取 posting_number
   -> 20 线程:
        POST /v2/posting/fbo/get (FBO 优先)
        -> 404 → POST /v3/posting/fbs/get (FBS fallback)
   -> 白俄判定 -> data/order_destination_v2.json

5. 拉取 PPC 广告费
   POST /api/client/token -> Bearer token
   POST /api/client/statistics/json (每批≤10)
   -> 轮询 -> 下载 JSON -> per-SKU 归属

6. 拉取 Promotion 推广费
   POST /api/client/statistic/products/generate (RFC 3339)
   -> 轮询 -> 下载 CSV -> 解析 per-SKU

7. 处理 CrossDock
   从归一化行中取 type_name=CrossDock
   -> POST /v3/supply-order/list -> get -> bundle
   -> 按数量比例分摊到 SKU

8. Phase 1 SKU 利润归集
   销售收入 + 佣金 + 物流 + 支付 + 打包 + 退货 + 仓储 + 越库
   -> XLSX 报告 (Phase) + MD 摘要
```

### 简化调用: 仅财务

```
1. types (缓存)
2. by-day × N 天 -> CSV
3. postings 反查 (如有混合)
```

### 简化调用: 仅广告

```
1. token
2. statistics/json -> PPC per-SKU
3. statistic/products/generate -> Promotion per-SKU
```

---

## 附录: 环境变量

| 变量 | 用途 | API |
|---|---|---|
| `OZON_CLIENT_ID` | Seller API Client-Id | Seller |
| `OZON_API_KEY` | Seller API 密钥 | Seller |
| `OZON_PERF_CLIENT_ID` | Performance API client_id | Performance |
| `OZON_PERF_SECRET` | Performance API client_secret | Performance |

配置文件路径: `~/.hermes/.env` (key=value 格式，支持引号)。

---

*最后更新: 2026-05-13 | 涵盖 Ozon Seller API v2.1 + Ozon Performance API v2.0*
