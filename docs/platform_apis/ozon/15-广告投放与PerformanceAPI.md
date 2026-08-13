# 15 广告投放与 Performance API

> **模块说明**：Ozon Performance API 用于对接广告后台，覆盖广告授权、广告活动和商品投放管理、CPC/CPO 出价、统计报表、外部流量分析。

> **API 端点**：`https://api-performance.ozon.ru`
> **认证方式**：先通过 `client_id` + `client_secret` 获取 Bearer token，后续请求使用 `Authorization: Bearer <access_token>`。

共 **49** 个接口：1 个授权接口 + 48 个业务接口。

---

## API 列表

### 授权

| # | 接口名称 | HTTP 方法 |
|---|---------|----------|
| 1 | [获取访问令牌](#1-获取访问令牌) | `POST /api/client/token` |

### 广告活动与对象

| # | 接口名称 | HTTP 方法 |
|---|---------|----------|
| 2 | [广告活动列表](#2-广告活动列表) | `GET /api/client/campaign` |
| 3 | [广告活动中的推广对象](#3-广告活动中的推广对象) | `GET /api/client/campaign/{campaignId}/objects` |
| 4 | [推广工具出价限制](#4-推广工具出价限制) | `GET /api/client/limits/list` |
| 5 | [按 SKU 查询商品最低出价](#5-按-sku-查询商品最低出价) | `POST /api/client/min/sku` |
| 6 | [带奖励商品列表](#6-带奖励商品列表) | `GET /api/client/products_with_bonuses` |

### 统计报表

| # | 接口名称 | HTTP 方法 |
|---|---------|----------|
| 7 | [广告活动统计](#7-广告活动统计) | `POST /api/client/statistics` |
| 8 | [视频横幅展示统计](#8-视频横幅展示统计) | `POST /api/client/statistics/video` |
| 9 | [订单归因报告](#9-订单归因报告) | `POST /api/client/statistics/attribution` |
| 10 | [报告状态](#10-报告状态) | `GET /api/client/statistics/{UUID}` |
| 11 | [界面生成的报告列表](#11-界面生成的报告列表) | `GET /api/client/statistics/list` |
| 12 | [API 生成的报告列表](#12-api-生成的报告列表) | `GET /api/client/statistics/externallist` |
| 13 | [下载报告](#13-下载报告) | `GET /api/client/statistics/report` |
| 14 | [媒体广告活动统计](#14-媒体广告活动统计) | `GET /api/client/statistics/campaign/media` |
| 15 | [CPC 广告活动统计](#15-cpc-广告活动统计) | `GET /api/client/statistics/campaign/product` |
| 16 | [广告活动费用统计](#16-广告活动费用统计) | `GET /api/client/statistics/expense` |
| 17 | [广告活动日统计](#17-广告活动日统计) | `GET /api/client/statistics/daily` |
| 18 | [CPO 订单报告-选定商品](#18-cpo-订单报告-选定商品) | `POST /api/client/statistic/orders/generate` |
| 19 | [CPO 商品报告-选定商品](#19-cpo-商品报告-选定商品) | `POST /api/client/statistic/products/generate` |
| 20 | [CPO 订单报告-全部商品](#20-cpo-订单报告-全部商品) | `GET /api/client/statistics/all_sku_promo/orders/generate` |
| 21 | [CPO 商品报告-全部商品](#21-cpo-商品报告-全部商品) | `GET /api/client/statistics/all_sku_promo/products/generate` |
| 22 | [搜索词报告](#22-搜索词报告) | `POST /api/client/statistics/phrases` |
| 23 | [CPC 商品 SKU 统计](#23-cpc-商品-sku-统计) | `POST /api/client/statistics/products/sku` |

### CPC：按点击付费

| # | 接口名称 | HTTP 方法 |
|---|---------|----------|
| 24 | [创建 CPC 商品广告活动](#24-创建-cpc-商品广告活动) | `POST /api/client/campaign/cpc/v2/product` |
| 25 | [计算广告活动最低预算](#25-计算广告活动最低预算) | `POST /external/api/dynamic_budget` |
| 26 | [激活广告活动](#26-激活广告活动) | `POST /api/client/campaign/{campaignId}/activate` |
| 27 | [停用广告活动](#27-停用广告活动) | `POST /api/client/campaign/{campaignId}/deactivate` |
| 28 | [更新广告活动参数](#28-更新广告活动参数) | `PATCH /api/client/campaign/{campaignId}` |

### CPC 商品管理

| # | 接口名称 | HTTP 方法 |
|---|---------|----------|
| 29 | [向 CPC 广告活动添加商品](#29-向-cpc-广告活动添加商品) | `POST /api/client/campaign/{campaignId}/products` |
| 30 | [更新 CPC 商品出价](#30-更新-cpc-商品出价) | `PUT /api/client/campaign/{campaignId}/products` |
| 31 | [CPC 广告活动商品列表](#31-cpc-广告活动商品列表) | `GET /api/client/campaign/{campaignId}/v2/products` |
| 32 | [从 CPC 广告活动删除商品](#32-从-cpc-广告活动删除商品) | `POST /api/client/campaign/{campaignId}/products/delete` |
| 33 | [商品竞争出价](#33-商品竞争出价) | `GET /api/client/campaign/{campaignId}/products/bids/competitive` |

### CPO：按订单付费

| # | 接口名称 | HTTP 方法 |
|---|---------|----------|
| 34 | [CPO 推广商品列表](#34-cpo-推广商品列表) | `POST /api/client/campaign/search_promo/v2/products` |
| 35 | [CPO 推荐出价](#35-cpo-推荐出价) | `POST /api/client/search_promo/bids/recommendation` |
| 36 | [设置 CPO 商品出价](#36-设置-cpo-商品出价) | `POST /api/client/campaign/search_promo/v2/bids/set` |
| 37 | [CPO 固定最低出价](#37-cpo-固定最低出价) | `POST /api/client/search_promo/get_cpo_min_bids` |
| 38 | [启用单品 CPO 推广](#38-启用单品-cpo-推广) | `POST /api/client/search_promo/product/enable` |
| 39 | [停用单品 CPO 推广](#39-停用单品-cpo-推广) | `POST /api/client/search_promo/product/disable` |
| 40 | [从 CPO 推广中删除商品](#40-从-cpo-推广中删除商品) | `POST /api/client/campaign/search_promo/v2/bids/delete` |
| 41 | [启用全部商品 CPO 推广](#41-启用全部商品-cpo-推广) | `GET /api/client/campaign/all_sku_promo/activate` |
| 42 | [停用全部商品 CPO 推广](#42-停用全部商品-cpo-推广) | `GET /api/client/campaign/all_sku_promo/deactivate` |
| 43 | [设置全部商品 CPO 出价](#43-设置全部商品-cpo-出价) | `GET /api/client/campaign/all_sku_promo/set_bid` |
| 44 | [启用 Carrots 活动商品推广](#44-启用-carrots-活动商品推广) | `POST /api/client/campaign/search_promo/carrots/enable` |
| 45 | [停用 Carrots 活动商品推广](#45-停用-carrots-活动商品推广) | `POST /api/client/campaign/search_promo/carrots/disable` |

### 外部流量分析

| # | 接口名称 | HTTP 方法 |
|---|---------|----------|
| 46 | [生成外部流量分析报告](#46-生成外部流量分析报告) | `POST /api/client/vendors/statistics` |
| 47 | [外部流量分析报告列表](#47-外部流量分析报告列表) | `GET /api/client/vendors/statistics/list` |
| 48 | [按 UUID 查询外部流量报告](#48-按-uuid-查询外部流量报告) | `GET /api/client/vendors/statistics/{UUID}` |
| 49 | [外部广告活动组织标记](#49-外部广告活动组织标记) | `GET /api/client/organisation/vendor_tag` |

---

## 核心流程

### Performance API 授权

```
创建/选择 Performance API 服务账号 → 获取 client_id/client_secret
                                   → POST /api/client/token
                                   → 使用 Bearer token 调业务接口
```

token 有过期时间，过期后重新调用授权接口获取新 token。

### 统计报表

```
提交统计报告请求 → 返回 UUID → 轮询 /api/client/statistics/{UUID}
                              → 生成完成后调用 /api/client/statistics/report 下载
```

统计导出限制：

| 限制项 | 限制值 |
|--------|--------|
| 单次导出天数 | 62 天 |
| 单个报告活动数 | 10 个 |
| 单账号并发导出数 | 1 个 |
| 单账号 24 小时导出数 | 2000 个 |
| 单组织并发导出数 | 5 个 |
| 单组织 24 小时导出数 | 2000 个 |

接口总请求限制：每天 100000 次。统计导出按广告活动计数，一个广告活动算一次导出；一个请求里包含多个广告活动时，按多个导出计。

---

## 通用约定

| 项目 | 说明 |
|------|------|
| Host | `https://api-performance.ozon.ru` |
| 认证头 | `Authorization: Bearer <access_token>` |
| 请求体 | `POST` / `PUT` / `PATCH` 通常使用 JSON Body |
| 报告标识 | 统计报告通常返回 `UUID`，用状态接口轮询 |
| 日期范围 | 统计报告最大 62 天 |
| 广告活动批量 | 统计报告最多 10 个活动 |

注意：Performance API 的 `client_id` / `client_secret` 来自广告后台 Performance API 服务账号，不是 Seller API 请求头里的 `Client-Id` / `Api-Key`。

---

## 1. 获取访问令牌

```
POST /api/client/token
```

通过 Performance API 的 `client_id` 和 `client_secret` 获取访问令牌。

### 请求参数

| 参数名 | 类型 | 必填 | 说明 |
|--------|------|:--:|------|
| `client_id` | string | ✅ | Performance API 服务账号 ID |
| `client_secret` | string | ✅ | Performance API 服务账号密钥 |
| `grant_type` | string | ✅ | 固定传 `client_credentials` |

### 响应字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `access_token` | string | Bearer token |
| `expires_in` | integer | token 有效期，单位秒 |
| `token_type` | string | 通常为 `Bearer` |

### 请求示例

```http
POST /api/client/token HTTP/1.1
Host: api-performance.ozon.ru
Content-Type: application/json
Accept: application/json

{
  "client_id": "XYZ@advertising.performance.ozon.ru",
  "client_secret": "secret",
  "grant_type": "client_credentials"
}
```

---

## 2. 广告活动列表

```
GET /api/client/campaign
```

查询广告账号下的广告活动列表。用于拿到 `campaignId`，再查询活动对象、管理活动状态或拉取统计。

---

## 3. 广告活动中的推广对象

```
GET /api/client/campaign/{campaignId}/objects
```

查询指定广告活动中正在推广或已配置的对象。

---

## 4. 推广工具出价限制

```
GET /api/client/limits/list
```

查询各类推广工具的出价限制，用于前端或同步任务校验出价范围。

---

## 5. 按 SKU 查询商品最低出价

```
POST /api/client/min/sku
```

按 SKU 查询商品最低出价。

---

## 6. 带奖励商品列表

```
GET /api/client/products_with_bonuses
```

查询带奖励或奖励加成的商品列表。

---

## 7. 广告活动统计

```
POST /api/client/statistics
```

提交广告活动统计报告生成请求。返回报告 `UUID` 后，通过报告状态接口轮询生成结果。

---

## 8. 视频横幅展示统计

```
POST /api/client/statistics/video
```

提交视频横幅广告展示统计报告生成请求。

---

## 9. 订单归因报告

```
POST /api/client/statistics/attribution
```

提交订单归因报告生成请求，用于分析广告对订单的归因效果。

---

## 10. 报告状态

```
GET /api/client/statistics/{UUID}
```

根据 `UUID` 查询统计报告生成状态。报告完成后再调用下载报告接口获取文件。

---

## 11. 界面生成的报告列表

```
GET /api/client/statistics/list
```

查询通过 Ozon 广告后台界面生成的统计报告列表。

---

## 12. API 生成的报告列表

```
GET /api/client/statistics/externallist
```

查询通过 Performance API 生成的统计报告列表。

---

## 13. 下载报告

```
GET /api/client/statistics/report
```

下载已生成的统计报告。通常需要传入报告 `UUID` 或报告文件标识，具体以 Ozon 返回字段为准。

---

## 14. 媒体广告活动统计

```
GET /api/client/statistics/campaign/media
```

查询媒体广告活动统计。

---

## 15. CPC 广告活动统计

```
GET /api/client/statistics/campaign/product
```

查询按点击付费的商品广告活动统计。

---

## 16. 广告活动费用统计

```
GET /api/client/statistics/expense
```

查询广告活动费用统计。

---

## 17. 广告活动日统计

```
GET /api/client/statistics/daily
```

查询广告活动按天聚合的统计。

---

## 18. CPO 订单报告-选定商品

```
POST /api/client/statistic/orders/generate
```

生成按订单付费推广中选定商品的订单报告。

---

## 19. CPO 商品报告-选定商品

```
POST /api/client/statistic/products/generate
```

生成按订单付费推广中选定商品的商品报告。

---

## 20. CPO 订单报告-全部商品

```
GET /api/client/statistics/all_sku_promo/orders/generate
```

生成全部商品按订单付费推广的订单报告。

---

## 21. CPO 商品报告-全部商品

```
GET /api/client/statistics/all_sku_promo/products/generate
```

生成全部商品按订单付费推广的商品报告。

---

## 22. 搜索词报告

```
POST /api/client/statistics/phrases
```

生成广告搜索词报告。

---

## 23. CPC 商品 SKU 统计

```
POST /api/client/statistics/products/sku
```

查询或生成按点击付费广告中商品 SKU 维度统计。

---

## 24. 创建 CPC 商品广告活动

```
POST /api/client/campaign/cpc/v2/product
```

创建按点击付费的商品广告活动。

---

## 25. 计算广告活动最低预算

```
POST /external/api/dynamic_budget
```

根据活动参数计算广告活动最低预算。

---

## 26. 激活广告活动

```
POST /api/client/campaign/{campaignId}/activate
```

激活指定广告活动。

---

## 27. 停用广告活动

```
POST /api/client/campaign/{campaignId}/deactivate
```

停用指定广告活动。

---

## 28. 更新广告活动参数

```
PATCH /api/client/campaign/{campaignId}
```

更新指定广告活动参数。

---

## 29. 向 CPC 广告活动添加商品

```
POST /api/client/campaign/{campaignId}/products
```

向指定 CPC 广告活动添加商品。

---

## 30. 更新 CPC 商品出价

```
PUT /api/client/campaign/{campaignId}/products
```

更新指定 CPC 广告活动中商品出价。

---

## 31. CPC 广告活动商品列表

```
GET /api/client/campaign/{campaignId}/v2/products
```

查询指定 CPC 广告活动中的商品列表。

---

## 32. 从 CPC 广告活动删除商品

```
POST /api/client/campaign/{campaignId}/products/delete
```

从指定 CPC 广告活动删除商品。

---

## 33. 商品竞争出价

```
GET /api/client/campaign/{campaignId}/products/bids/competitive
```

查询指定 CPC 广告活动中商品的竞争出价。

---

## 34. CPO 推广商品列表

```
POST /api/client/campaign/search_promo/v2/products
```

查询按订单付费推广中的商品列表。

---

## 35. CPO 推荐出价

```
POST /api/client/search_promo/bids/recommendation
```

查询按订单付费推广的推荐出价。

---

## 36. 设置 CPO 商品出价

```
POST /api/client/campaign/search_promo/v2/bids/set
```

设置按订单付费推广商品出价。

---

## 37. CPO 固定最低出价

```
POST /api/client/search_promo/get_cpo_min_bids
```

获取按订单付费推广商品的固定最低出价。

---

## 38. 启用单品 CPO 推广

```
POST /api/client/search_promo/product/enable
```

启用指定商品的按订单付费推广。

---

## 39. 停用单品 CPO 推广

```
POST /api/client/search_promo/product/disable
```

停用指定商品的按订单付费推广。

---

## 40. 从 CPO 推广中删除商品

```
POST /api/client/campaign/search_promo/v2/bids/delete
```

从按订单付费推广中删除商品。

---

## 41. 启用全部商品 CPO 推广

```
GET /api/client/campaign/all_sku_promo/activate
```

启用全部商品的按订单付费推广。

---

## 42. 停用全部商品 CPO 推广

```
GET /api/client/campaign/all_sku_promo/deactivate
```

停用全部商品的按订单付费推广。

---

## 43. 设置全部商品 CPO 出价

```
GET /api/client/campaign/all_sku_promo/set_bid
```

设置全部商品按订单付费推广的出价。

---

## 44. 启用 Carrots 活动商品推广

```
POST /api/client/campaign/search_promo/carrots/enable
```

启用 Carrots 活动中的商品推广。

---

## 45. 停用 Carrots 活动商品推广

```
POST /api/client/campaign/search_promo/carrots/disable
```

停用 Carrots 活动中的商品推广。

---

## 46. 生成外部流量分析报告

```
POST /api/client/vendors/statistics
```

生成外部流量广告活动分析报告。

---

## 47. 外部流量分析报告列表

```
GET /api/client/vendors/statistics/list
```

查询已请求的外部流量分析报告列表。

---

## 48. 按 UUID 查询外部流量报告

```
GET /api/client/vendors/statistics/{UUID}
```

根据 `UUID` 查询外部流量分析报告信息。

---

## 49. 外部广告活动组织标记

```
GET /api/client/organisation/vendor_tag
```

获取组织用于外部广告活动的标记。
