# Ozon Performance API — 广告数据接口

## 概述

Performance API 是独立于 Seller API 的广告专用接口，用于获取广告活动统计、花费、订单等数据。

- **Base URL**: `https://api-performance.ozon.ru`
- **认证方式**: OAuth2 Bearer Token（30分钟有效期）
- **凭证申请**: 发邮件至 `performance@ozon.ru`，或账号设置 → API Keys → Performance API

---

## 认证

### POST /api/client/token

获取访问令牌。

**Request Body:**
```json
{
  "client_id": "string",
  "client_secret": "string",
  "grant_type": "client_credentials"
}
```

**Response:**
```json
{
  "access_token": "eyJhbG...",
  "token_type": "Bearer",
  "expires_in": 1800
}
```

后续所有请求在 Header 中携带：`Authorization: Bearer {access_token}`

---

## 活动管理

### GET /api/client/campaign

获取广告活动列表。

**Query Params:**
| 参数 | 类型 | 说明 |
|------|------|------|
| state | string | 过滤状态：`CAMPAIGN_STATE_RUNNING` / `CAMPAIGN_STATE_INACTIVE` / `CAMPAIGN_STATE_ARCHIVED` |

**Response 关键字段:**
```json
{
  "list": [
    {
      "id": "26639001",
      "title": "KJ-228-WT-目标费用10%",
      "state": "CAMPAIGN_STATE_RUNNING",
      "advObjectType": "SKU",           // SKU（商品推广）或 SEARCH_PROMO（搜索推广）
      "fromDate": "2026-05-08",
      "toDate": "",
      "dailyBudget": "0",
      "weeklyBudget": "2000000000",
      "budgetType": "PRODUCT_CAMPAIGN_BUDGET_TYPE_WEEKLY",
      "PaymentType": "CPC",             // CPC 按点击 / CPO 按订单
      "placement": ["PLACEMENT_SEARCH_AND_CATEGORY"],
      "productCampaignMode": "PRODUCT_CAMPAIGN_MODE_AUTO",
      "createdAt": "2026-05-08T02:40:42Z",
      "updatedAt": "2026-05-08T02:40:42Z"
    }
  ]
}
```

**已知活动类型分布（实测账号）:**
- `SKU`（商品推广）: 74 个
- `SEARCH_PROMO`（搜索推广）: 1 个

---

### GET /api/client/campaign/{campaignId}/objects

获取活动内的商品 SKU ID 列表。

**Response:**
```json
{
  "list": [
    { "id": "3583443109" }   // Ozon SKU ID
  ]
}
```

---

## 统计数据

### GET /api/client/statistics/daily ⭐ 推荐

**同步接口**，直接返回 CSV，无需轮询。适合按日/按周定时同步。

**Query Params:**
| 参数 | 类型 | 说明 |
|------|------|------|
| campaigns | string | 活动 ID，逗号分隔，可传多个 |
| dateFrom | string | 开始日期 `YYYY-MM-DD` |
| dateTo | string | 结束日期 `YYYY-MM-DD` |

**Response（CSV 格式，分号分隔）:**
```
ID;Название;Дата;Показы;Клики;Расход, ₽;Заказы, шт.;Заказы, ₽
13987713;Продвижение в поиске;2026-04-27;5466;125;9055,00;18;90550,00
```

| 列名 | 中文 | 说明 |
|------|------|------|
| ID | 活动ID | campaign id |
| Название | 活动名称 | |
| Дата | 日期 | |
| Показы | 曝光量 | |
| Клики | 点击量 | |
| Расход, ₽ | 广告花费（卢布） | 核心字段 |
| Заказы, шт. | 广告带来的订单数 | |
| Заказы, ₽ | 广告带来的订单金额 | |

**注意**: 金额使用逗号作为小数点（俄式格式），解析时需替换为 `.`。

---

### POST /api/client/statistics（异步，不推荐日常使用）

异步生成报告，需轮询状态后下载。

**流程**: 提交请求 → 获得 UUID → 轮询 `/api/client/statistics/{UUID}` → 状态为 `OK` 后下载

**限制**:
- 每次最多 10 个活动
- 每天最多 1000 次下载
- 并发队列上限 3 个任务

---

## 与 Seller API 的关系

| | Seller API | Performance API |
|--|-----------|----------------|
| 域名 | `api-seller.ozon.ru` | `api-performance.ozon.ru` |
| 认证 | `Client-Id` + `Api-Key` (Header) | OAuth2 Bearer Token |
| 凭证来源 | 账号设置直接生成 | 需申请，一个店铺对应一套凭证 |
| 凭证存储 | `raw_ozon_seller_accounts.api_key` | `raw_ozon_seller_accounts.performance_client_id/secret` |

---

## 已知限制

- `statistics/daily` 接口无 SKU 维度，只有**活动维度**的花费
- 要关联到具体 SKU，需通过 `/api/client/campaign/{id}/objects` 拿到活动内的 SKU，再按活动花费摊销
- `SEARCH_PROMO` 类型活动包含多个商品，花费无法精确拆分到单个 SKU
