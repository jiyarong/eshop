# Wildberries Marketing and Promotions API 整理版

> 来源文件：`marketing.html.md`  
> 本文档整理 Wildberries Marketing and Promotions 相关 API 的核心功能、请求方式、请求参数、响应信息与示例。  
> 鉴权方式统一为 `HeaderApiKey`，除特别说明外，请在请求头中携带 API Token。

## 1. 基础信息

### 1.1 主要域名

| 业务 | Base URL |
|---|---|
| 广告/推广 Campaign、Finance、Search Cluster、Statistics | `https://advert-api.wildberries.ru` |
| 媒体广告 Media | `https://advert-media-api.wildberries.ru` |
| 促销日历 Promotions Calendar | `https://dp-calendar-api.wildberries.ru` |
| 商品推荐 Recommendations | `https://content-api.wildberries.ru` |

### 1.2 Token 分类

| 模块 | Token 分类 |
|---|---|
| Campaigns / Campaigns Creation / Campaigns Management / Search Clusters / Finances / Statistics | Promotion |
| Promotions Calendar | Prices and Discounts |
| Recommendations | Content；仅支持 Personal / Service Token；需要 Advanced/Premium Jam 订阅或 Plan Builder 对应选项 |

### 1.3 同步与生效说明

- 数据库同步约每 3 分钟一次。
- 广告活动状态变化约每 1 分钟生效。
- 出价变更约每 30 秒生效。

### 1.4 常见枚举

#### Campaign Status

| 值 | 含义 |
|---:|---|
| `-1` | 已删除，删除流程通常 3–10 分钟完成 |
| `4` | 准备启动 |
| `7` | 已完成 |
| `8` | 已拒绝 |
| `9` | 活动中 |
| `11` | 已暂停 |

#### Payment Type

| 值 | 含义 |
|---|---|
| `cpm` | Cost Per Mille，按千次展示付费 |
| `cpc` | Cost Per Click，按点击付费 |

#### Bid Type

| 值 | 含义 |
|---|---|
| `manual` | 自定义出价 |
| `unified` | 标准出价 |

---

## 2. API 总览

| 模块 | 方法 | Endpoint | 功能 |
|---|---|---|---|
| Campaigns | GET | `/adv/v1/promotion/count` | 获取广告活动按类型和状态分组的列表 |
| Campaigns | GET | `/api/advert/v2/adverts` | 获取广告活动详情 |
| Campaigns Creation | POST | `/api/advert/v1/bids/min` | 获取商品最低出价 |
| Campaigns Creation | POST | `/adv/v2/seacat/save-ad` | 创建广告活动 |
| Campaigns Creation | GET | `/adv/v1/supplier/subjects` | 获取可投放子类目 |
| Campaigns Creation | POST | `/adv/v2/supplier/nms` | 获取可投放商品 |
| Campaigns Management | GET | `/adv/v0/delete` | 删除广告活动 |
| Campaigns Management | POST | `/adv/v0/rename` | 重命名广告活动 |
| Campaigns Management | GET | `/adv/v0/start` | 启动广告活动 |
| Campaigns Management | GET | `/adv/v0/pause` | 暂停广告活动 |
| Campaigns Management | GET | `/adv/v0/stop` | 结束广告活动 |
| Campaigns Management | PUT | `/adv/v0/auction/placements` | 修改自定义出价活动展示位置 |
| Campaigns Management | PATCH | `/api/advert/v1/bids` | 修改广告活动商品出价 |
| Campaigns Management | PATCH | `/adv/v0/auction/nms` | 添加/移除广告活动商品 |
| Campaigns Management | GET | `/api/advert/v0/bids/recommendations` | 获取商品与搜索簇推荐出价 |
| Search Clusters | POST | `/adv/v0/normquery/get-bids` | 查询搜索簇出价 |
| Search Clusters | POST | `/adv/v0/normquery/bids` | 设置搜索簇出价 |
| Search Clusters | DELETE | `/adv/v0/normquery/bids` | 删除搜索簇出价 |
| Search Clusters | POST | `/adv/v0/normquery/get-minus` | 查询广告活动否定搜索词 |
| Search Clusters | POST | `/adv/v0/normquery/set-minus` | 设置或删除否定搜索词 |
| Search Clusters | POST | `/adv/v0/normquery/list` | 查询活跃/非活跃搜索簇 |
| Finances | GET | `/adv/v1/balance` | 获取账户余额、净额、奖金 |
| Finances | GET | `/adv/v1/budget` | 获取广告活动预算 |
| Finances | POST | `/adv/v1/budget/deposit` | 充值广告活动预算 |
| Finances | GET | `/adv/v1/upd` | 获取费用历史 |
| Finances | GET | `/adv/v1/payments` | 获取账户充值历史 |
| Media | GET | `/adv/v1/count` | 获取媒体广告活动数量 |
| Media | GET | `/adv/v1/adverts` | 获取媒体广告活动列表 |
| Media | GET | `/adv/v1/advert` | 获取媒体广告活动详情 |
| Statistics | POST | `/adv/v0/normquery/stats` | 搜索簇统计 |
| Statistics | GET | `/adv/v3/fullstats` | 广告活动整体统计 |
| Statistics | POST | `/adv/v1/stats` | 媒体广告统计 |
| Statistics | POST | `/adv/v1/normquery/stats` | 按日搜索簇统计 |
| Promotions Calendar | GET | `/api/v1/calendar/promotions` | 获取促销活动列表 |
| Promotions Calendar | GET | `/api/v1/calendar/promotions/details` | 获取促销活动详情 |
| Promotions Calendar | GET | `/api/v1/calendar/promotions/nomenclatures` | 获取可参与促销商品 |
| Promotions Calendar | POST | `/api/v1/calendar/promotions/upload` | 添加商品到促销活动 |
| Recommendations | POST | `/api/content/v1/recommendations/list` | 获取商品推荐列表 |
| Recommendations | POST | `/api/content/v1/recommendations/set` | 设置商品推荐 |

---

# 3. Campaigns 广告活动查询

## 3.1 获取广告活动列表

**GET** `https://advert-api.wildberries.ru/adv/v1/promotion/count`

### 功能

获取广告活动列表，并按广告类型与状态分组，同时返回最近变更时间。

### 请求参数

无。

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 401 | 未授权 |
| 429 | 请求过多 |

### 200 响应字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `adverts` | array | 分组后的广告活动信息 |
| `adverts[].type` | integer | 广告活动类型 |
| `adverts[].status` | integer | 广告活动状态 |
| `adverts[].count` | integer | 当前分组数量 |
| `adverts[].advert_list` | array | 广告活动列表 |
| `adverts[].advert_list[].advertId` | integer | 广告活动 ID |
| `adverts[].advert_list[].changeTime` | string/date-time | 最近变更时间 |
| `all` | integer | 总数量 |

### 示例

```json
{
  "adverts": [
    {
      "type": 9,
      "status": 8,
      "count": 3,
      "advert_list": [
        {"advertId": 6485174, "changeTime": "2023-05-10T12:12:52.676254+03:00"}
      ]
    }
  ],
  "all": 3
}
```

## 3.2 获取广告活动详情

**GET** `https://advert-api.wildberries.ru/api/advert/v2/adverts`

### 功能

根据广告活动 ID、状态、付款类型获取标准出价或自定义出价广告活动详情。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `ids` | string | 否 | 广告活动 ID，逗号分隔，最多 50 个。例：`12345,23456` |
| `statuses` | string | 否 | 状态，逗号分隔。可用值：`-1`,`4`,`7`,`8`,`9`,`11` |
| `payment_type` | string | 否 | `cpm` 或 `cpc` |

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 429 | 请求过多 |

### 200 响应核心字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `adverts` | array | 广告活动列表 |
| `adverts[].id` | integer | 广告活动 ID |
| `adverts[].bid_type` | string | 出价类型：`manual` / `unified` |
| `adverts[].status` | integer | 广告活动状态 |
| `adverts[].settings.name` | string | 广告活动名称 |
| `adverts[].settings.payment_type` | string | 付款方式：`cpm` / `cpc` |
| `adverts[].settings.placements.search` | boolean | 是否投放搜索 |
| `adverts[].settings.placements.recommendations` | boolean | 是否投放推荐 |
| `adverts[].nm_settings` | array | 商品出价设置 |
| `adverts[].nm_settings[].nm_id` | integer | WB 商品 ID |
| `adverts[].nm_settings[].bids_kopecks.search` | integer | 搜索出价，单位 kopecks |
| `adverts[].nm_settings[].bids_kopecks.recommendations` | integer | 推荐出价，单位 kopecks |
| `adverts[].timestamps` | object | 创建、启动、更新、删除时间 |

---

# 4. Campaigns Creation 广告活动创建

## 4.1 获取商品最低出价

**POST** `https://advert-api.wildberries.ru/api/advert/v1/bids/min`

### 功能

根据付款类型和投放位置，获取指定商品的最低出价，单位为 kopecks。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `advert_id` | integer/int64 | 是 | 广告活动 ID |
| `nm_ids` | integer[] | 是 | WB 商品 ID 列表，1–100 个 |
| `payment_type` | string | 是 | `cpm` 或 `cpc` |
| `placement_types` | string[] | 是 | `combined`、`search`、`recommendation` |

### 请求示例

```json
{
  "advert_id": 98765432,
  "nm_ids": [12345678, 87654321],
  "payment_type": "cpm",
  "placement_types": ["combined", "search", "recommendation"]
}
```

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 429 | 请求过多 |

### 200 示例

```json
{
  "bids": [
    {
      "nm_id": 12345678,
      "bids": [
        {"type": "combined", "value": 155},
        {"type": "search", "value": 250},
        {"type": "recommendation", "value": 250}
      ]
    }
  ]
}
```

## 4.2 创建广告活动

**POST** `https://advert-api.wildberries.ru/adv/v2/seacat/save-ad`

### 功能

创建广告活动，支持：

- 搜索和/或推荐位的自定义出价广告活动。
- 搜索与推荐位同时投放的标准出价广告活动。

### Body 参数

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `name` | string | 是 | - | 广告活动名称 |
| `nms` | integer[] | 否 | - | 商品 ID 列表，最多 50 个 |
| `bid_type` | string | 否 | `manual` | `manual` 自定义出价；`unified` 标准出价 |
| `payment_type` | string | 否 | `cpm` | `cpm` 或 `cpc`；创建 `cpc` 活动时会自动设置最低出价 |
| `placement_types` | string[] | 否 | `["search"]` | 仅自定义出价活动使用；可选 `search`、`recommendations` |

### 请求示例

```json
{
  "name": "Телефоны",
  "nms": [146168367, 200425104],
  "bid_type": "manual",
  "placement_types": ["search", "recommendations"]
}
```

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功，返回广告活动 ID |
| 400 | 请求错误 |
| 401 | 未授权 |
| 429 | 请求过多 |

### 200 示例

```json
1234567
```

## 4.3 获取可投放子类目

**GET** `https://advert-api.wildberries.ru/adv/v1/supplier/subjects`

### 功能

返回可用于广告活动投放的商品子类目。

### Query 参数

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `payment_type` | string | 否 | `cpm` | `cpm` 或 `cpc` |

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 401 | 未授权 |
| 404 | 未找到 |
| 429 | 请求过多 |

### 200 示例

```json
[
  {"name": "3D очки", "id": 2560, "count": 1899}
]
```

## 4.4 获取可投放商品

**POST** `https://advert-api.wildberries.ru/adv/v2/supplier/nms`

### 功能

根据子类目 ID 获取可用于广告活动投放的商品。

### Body 参数

请求体为子类目 ID 数组：

```json
[123, 456, 765, 321]
```

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 429 | 请求过多 |

### 200 示例

```json
[
  {"title": "Плед", "nm": 146168367, "subjectId": 765}
]
```

---

# 5. Campaigns Management 广告活动管理

## 5.1 删除广告活动

**GET** `https://advert-api.wildberries.ru/adv/v0/delete`

### 功能

删除状态为 `4`（准备启动）的广告活动。删除后会短暂处于 `-1` 状态，通常 3–10 分钟内彻底删除。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | integer | 是 | 广告活动 ID |

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 429 | 请求过多 |

## 5.2 重命名广告活动

**POST** `https://advert-api.wildberries.ru/adv/v0/rename`

### 功能

修改广告活动名称。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `advertId` | integer | 是 | 广告活动 ID |
| `name` | string | 是 | 新名称，最长 100 字符 |

### 请求示例

```json
{"advertId": 2233344, "name": "newname"}
```

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 422 | 参数处理错误 |
| 429 | 请求过多 |

## 5.3 启动广告活动

**GET** `https://advert-api.wildberries.ru/adv/v0/start`

### 功能

启动状态为 `4`（准备启动）或 `11`（已暂停）的广告活动。启动前需确保广告预算充足。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | integer | 是 | 广告活动 ID |

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 422 | 状态未改变，例如预算不足或状态不允许 |
| 429 | 请求过多 |

## 5.4 暂停广告活动

**GET** `https://advert-api.wildberries.ru/adv/v0/pause`

### 功能

暂停状态为 `9`（活动中）的广告活动。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | integer | 是 | 广告活动 ID |

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 422 | 状态未改变 |
| 429 | 请求过多 |

## 5.5 结束广告活动

**GET** `https://advert-api.wildberries.ru/adv/v0/stop`

### 功能

结束状态为 `4`、`9`、`11` 的广告活动。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | integer | 是 | 广告活动 ID |

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 422 | 状态未改变 |
| 429 | 请求过多 |

## 5.6 修改自定义出价活动的投放位置

**PUT** `https://advert-api.wildberries.ru/adv/v0/auction/placements`

### 功能

修改自定义出价且付款模式为 `cpm` 的广告活动投放位置。适用于状态 `4`、`9`、`11`。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `placements` | object[] | 是 | 投放位置配置，最多 50 条 |
| `placements[].advert_id` | integer | 是 | 广告活动 ID |
| `placements[].placements.search` | boolean | 是 | 是否开启搜索投放 |
| `placements[].placements.recommendations` | boolean | 是 | 是否开启推荐投放 |

### 请求示例

```json
{
  "placements": [
    {
      "advert_id": 12345,
      "placements": {
        "search": true,
        "recommendations": true
      }
    }
  ]
}
```

### 响应

| 状态码 | 含义 |
|---:|---|
| 204 | 成功，无响应体 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 429 | 请求过多 |

## 5.7 修改广告活动商品出价

**PATCH** `https://advert-api.wildberries.ru/api/advert/v1/bids`

### 功能

修改广告活动中商品的出价，支持：

- 标准出价广告活动。
- 自定义出价广告活动。
- `cpc` 按点击付费广告活动。

适用于状态 `4`、`9`、`11`。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `bids` | object[] | 是 | 出价配置，最多 50 个广告活动 |
| `bids[].advert_id` | integer | 是 | 广告活动 ID |
| `bids[].nm_bids` | object[] | 是 | 商品出价列表 |
| `bids[].nm_bids[].nm_id` | integer | 是 | WB 商品 ID |
| `bids[].nm_bids[].bid_kopecks` | integer | 是 | 出价，单位 kopecks |
| `bids[].nm_bids[].placement` | string | 是 | `combined`、`search`、`recommendations` |

> `combined` 用于标准出价活动；`search` / `recommendations` 用于自定义出价活动。

### 请求示例

```json
{
  "bids": [
    {
      "advert_id": 12345,
      "nm_bids": [
        {"nm_id": 13335157, "bid_kopecks": 250, "placement": "recommendations"}
      ]
    }
  ]
}
```

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 429 | 请求过多 |

## 5.8 添加或移除广告活动商品

**PATCH** `https://advert-api.wildberries.ru/adv/v0/auction/nms`

### 功能

向广告活动添加或移除商品。适用于状态 `4`、`9`、`11`。新增商品会自动设置当前最低出价。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `nms` | object[] | 是 | 商品变更列表，最多 20 条 |
| `nms[].advert_id` | integer | 是 | 广告活动 ID |
| `nms[].nms.add` | integer[] | 否 | 需要添加的商品 ID |
| `nms[].nms.delete` | integer[] | 否 | 需要移除的商品 ID |

### 请求示例

```json
{
  "nms": [
    {
      "advert_id": 12345,
      "nms": {
        "add": [11111111, 44444444],
        "delete": [55555555]
      }
    }
  ]
}
```

### 响应示例

```json
{
  "nms": [
    {
      "advert_id": 12345,
      "nms": {
        "added": [11111111, 44444444],
        "deleted": [55555555]
      }
    }
  ]
}
```

## 5.9 获取商品与搜索簇推荐出价

**GET** `https://advert-api.wildberries.ru/api/advert/v0/bids/recommendations`

### 功能

获取广告活动中商品和搜索簇的推荐出价。仅适用于 `cpm` 广告活动。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `nmId` | integer/int64 | 是 | WB 商品 ID |
| `advertId` | integer/int64 | 是 | 广告活动 ID |

### 响应核心字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `advertId` | integer | 广告活动 ID |
| `nmId` | integer | WB 商品 ID |
| `base.competitiveBid.bidKopecks` | integer | 竞争推荐出价 |
| `base.leadersBid.bidKopecks` | integer | 领先推荐出价 |
| `normQueries` | array | 搜索簇推荐出价 |
| `normQueries[].normQuery` | string | 搜索簇名称 |
| `normQueries[].reachMax.bidKopecks` | integer | 最大覆盖推荐出价 |
| `normQueries[].reachMedium.bidKopecks` | integer | 中等覆盖推荐出价 |
| `normQueries[].reachMin.bidKopecks` | integer | 最小覆盖推荐出价 |

---

# 6. Search Clusters 搜索簇

## 6.1 查询搜索簇出价

**POST** `https://advert-api.wildberries.ru/adv/v0/normquery/get-bids`

### 功能

根据广告活动 ID 和 WB 商品 ID 查询搜索簇出价。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `items` | object[] | 是 | 查询项，最多 100 条 |
| `items[].advert_id` | integer | 是 | 广告活动 ID |
| `items[].nm_id` | integer | 是 | WB 商品 ID |

### 请求示例

```json
{
  "items": [
    {"advert_id": 1825035, "nm_id": 983512347}
  ]
}
```

### 响应示例

```json
{
  "bids": [
    {"advert_id": 1825035, "nm_id": 983512347, "norm_query": "Фраза 1", "bid": 700}
  ]
}
```

## 6.2 设置搜索簇出价

**POST** `https://advert-api.wildberries.ru/adv/v0/normquery/bids`

### 功能

设置搜索簇出价。仅适用于自定义出价、`cpm` 付款模式的广告活动。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `bids` | object[] | 是 | 出价配置，最多 100 条 |
| `bids[].advert_id` | integer | 是 | 广告活动 ID |
| `bids[].nm_id` | integer | 是 | WB 商品 ID |
| `bids[].norm_query` | string | 是 | 搜索簇名称 |
| `bids[].bid` | integer | 是 | 出价，单位 kopecks |

### 请求示例

```json
{
  "bids": [
    {"advert_id": 1825035, "nm_id": 983512347, "norm_query": "Фраза 1", "bid": 1000}
  ]
}
```

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 403 | 无访问权限 |
| 429 | 请求过多 |

## 6.3 删除搜索簇出价

**DELETE** `https://advert-api.wildberries.ru/adv/v0/normquery/bids`

### 功能

删除搜索簇出价。仅适用于自定义出价、`cpm` 付款模式的广告活动。

### Body 参数

与设置搜索簇出价相同：

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `bids` | object[] | 是 | 待删除出价配置，最多 100 条 |
| `bids[].advert_id` | integer | 是 | 广告活动 ID |
| `bids[].nm_id` | integer | 是 | WB 商品 ID |
| `bids[].norm_query` | string | 是 | 搜索簇名称 |
| `bids[].bid` | integer | 是 | 出价 |

## 6.4 查询广告活动否定搜索词

**POST** `https://advert-api.wildberries.ru/adv/v0/normquery/get-minus`

### 功能

根据广告活动 ID 和 WB 商品 ID 查询否定搜索词。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `items` | object[] | 是 | 查询项，最多 100 条 |
| `items[].advert_id` | integer | 是 | 广告活动 ID |
| `items[].nm_id` | integer | 是 | WB 商品 ID |

### 响应示例

```json
{
  "items": [
    {
      "advert_id": 1825035,
      "nm_id": 983512347,
      "norm_queries": ["Фраза 1"]
    }
  ]
}
```

## 6.5 设置或删除否定搜索词

**POST** `https://advert-api.wildberries.ru/adv/v0/normquery/set-minus`

### 功能

设置或删除广告活动的否定搜索词，适用于标准出价与自定义出价广告活动。发送空数组会删除全部否定搜索词。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `advert_id` | integer | 是 | 广告活动 ID |
| `nm_id` | integer | 是 | WB 商品 ID |
| `norm_queries` | string[] | 是 | 否定搜索词，最多 1000 个；空数组表示清空 |

### 请求示例

```json
{
  "advert_id": 1825035,
  "nm_id": 983512347,
  "norm_queries": ["Фраза 1"]
}
```

## 6.6 查询活跃/非活跃搜索簇

**POST** `https://advert-api.wildberries.ru/adv/v0/normquery/list`

### 功能

返回至少有 100 次浏览的活跃与非活跃搜索簇。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `items` | object[] | 是 | 查询项，最多 100 条 |
| `items[].advertId` | integer | 是 | 广告活动 ID |
| `items[].nmId` | integer | 是 | WB 商品 ID |

### 响应示例

```json
{
  "items": [
    {
      "advertId": 123456789,
      "nmId": 987654321,
      "normQueries": {
        "active": null,
        "excluded": ["поло мужское", "футболка поло"]
      }
    }
  ]
}
```

---

# 7. Finances 财务

## 7.1 获取账户余额

**GET** `https://advert-api.wildberries.ru/adv/v1/balance`

### 功能

获取卖家的净额、余额、奖金和返现信息。

### 请求参数

无。

### 响应示例

```json
{
  "balance": 11083,
  "net": 0,
  "bonus": 15187,
  "cashbacks": [
    {"sum": 10672, "percent": 50, "expiration_date": "2026-04-17T10:46:02.176174Z"}
  ]
}
```

## 7.2 获取广告活动预算

**GET** `https://advert-api.wildberries.ru/adv/v1/budget`

### 功能

获取指定广告活动预算。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | integer | 是 | 广告活动 ID |

### 响应示例

```json
{"cash": 0, "netting": 0, "total": 500}
```

## 7.3 充值广告活动预算

**POST** `https://advert-api.wildberries.ru/adv/v1/budget/deposit`

### 功能

为广告活动充值预算。充值后如需启动广告活动，可调用 `/adv/v0/start`。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | integer | 是 | 广告活动 ID |

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `sum` | integer | 是 | 充值金额 |
| `cashback_sum` | integer/null | 否 | 使用推广奖金支付的金额 |
| `cashback_percent` | integer/null | 视情况 | 使用返现时需传，取自余额接口的 `percent` |
| `type` | integer | 是 | 充值来源：`0` 账户；`1` 余额；`3` 奖金 |
| `return` | boolean | 否 | `true` 返回更新后预算；`false` 或不传则不返回预算 |

### 请求示例

```json
{
  "sum": 5000,
  "cashback_sum": 1000,
  "cashback_percent": 50,
  "type": 1,
  "return": true
}
```

### 响应示例

```json
{"total": 7289}
```

## 7.4 获取费用历史

**GET** `https://advert-api.wildberries.ru/adv/v1/upd`

### 功能

获取广告费用历史。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `from` | string/date | 是 | 开始日期，例：`2023-07-31` |
| `to` | string/date | 是 | 结束日期，最小 1 天，最大 31 天 |

### 响应示例

```json
[
  {
    "updNum": 0,
    "updTime": "2023-07-31T12:12:54.060536+03:00",
    "updSum": 24,
    "advertId": 3355881,
    "campName": "лук лучок",
    "advertType": 6,
    "paymentType": "Баланс",
    "advertStatus": 9
  }
]
```

## 7.5 获取账户充值历史

**GET** `https://advert-api.wildberries.ru/adv/v1/payments`

### 功能

获取账户充值历史。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `from` | string/date | 否 | 开始日期 |
| `to` | string/date | 否 | 结束日期，最小 1 天，最大 31 天 |

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 204 | 无交易历史 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 429 | 请求过多 |

---

# 8. Media 媒体广告

## 8.1 获取媒体广告活动数量

**GET** `https://advert-media-api.wildberries.ru/adv/v1/count`

### 功能

获取卖家的媒体广告活动数量。

### 响应示例

```json
{"all": 6, "adverts": {"type": 2, "status": 7, "count": 2}}
```

## 8.2 获取媒体广告活动列表

**GET** `https://advert-media-api.wildberries.ru/adv/v1/adverts`

### 功能

获取卖家的媒体广告活动列表。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `status` | integer | 否 | 媒体广告状态 |
| `type` | integer | 否 | 媒体广告类型：`1` 每日；`2` 按浏览 |
| `limit` | integer | 否 | 返回数量 |
| `offset` | integer | 否 | 偏移量 |
| `order` | string | 否 | 排序字段：`create` 或 `id` |
| `direction` | string | 否 | 排序方向：`desc` 或 `asc` |

### Media Status

| 值 | 含义 |
|---:|---|
| 1 | 模板 |
| 2 | 审核中 |
| 3 | 已拒绝，可重新提交审核 |
| 4 | 准备启动 |
| 5 | 已计划 |
| 6 | 运行中 |
| 7 | 已完成 |
| 8 | 已拒绝 |
| 9 | 卖家暂停 |
| 10 | 因每日限制暂停 |
| 11 | 暂停 |

## 8.3 获取媒体广告活动详情

**GET** `https://advert-media-api.wildberries.ru/adv/v1/advert`

### 功能

获取指定媒体广告活动详情。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | integer | 是 | 媒体广告活动 ID |

### 响应核心字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `advertId` | integer | 媒体广告活动 ID |
| `name` | string | 名称 |
| `brand` | string | 品牌 |
| `type` | integer | 类型 |
| `status` | integer | 状态 |
| `createTime` | string/date-time | 创建时间 |
| `extended` | object | 扩展信息，如预算、费用、暂停原因等 |
| `items` | array | 投放项信息 |

---

# 9. Statistics 统计

## 9.1 搜索簇统计

**POST** `https://advert-api.wildberries.ru/adv/v0/normquery/stats`

### 功能

查询指定周期内搜索簇统计。仅适用于 `cpm` 付款模式广告活动。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `from` | string/date | 是 | 开始日期 |
| `to` | string/date | 是 | 结束日期 |
| `items` | object[] | 是 | 查询项，最多 100 条 |
| `items[].advert_id` | integer | 是 | 广告活动 ID |
| `items[].nm_id` | integer | 是 | WB 商品 ID |

### 响应统计字段

| 字段 | 说明 |
|---|---|
| `views` | 浏览数 |
| `clicks` | 点击数 |
| `ctr` | 点击率 |
| `cpc` | 平均点击成本 |
| `cpm` | 千次展示成本 |
| `atbs` | 加购数 |
| `orders` | 订单数 |
| `avg_pos` | 平均位置 |

## 9.2 广告活动整体统计

**GET** `https://advert-api.wildberries.ru/adv/v3/fullstats`

### 功能

生成广告活动统计，适用于任意广告活动类型。单次请求最大周期 31 天，适用于状态 `7`、`9`、`11`。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `ids` | string | 是 | 广告活动 ID，逗号分隔，最多 50 个 |
| `beginDate` | string/date | 是 | 开始日期 |
| `endDate` | string/date | 是 | 结束日期 |

### 响应核心字段

| 字段 | 说明 |
|---|---|
| `advertId` | 广告活动 ID |
| `views` | 浏览数 |
| `clicks` | 点击数 |
| `ctr` | 点击率 |
| `cpc` | 点击成本 |
| `cr` | 转化率 |
| `atbs` | 加购数 |
| `orders` | 订单数 |
| `sum` | 花费 |
| `days` | 按天统计 |
| `apps` | 按应用/渠道统计 |
| `nms` | 按商品统计 |

## 9.3 媒体广告统计

**POST** `https://advert-media-api.wildberries.ru/adv/v1/stats`

### 功能

获取 WB Media 媒体广告统计。

### Body 参数

请求体为数组，1–100 个元素。支持按日期、区间、广告活动 ID 等方式查询。常用结构：

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | integer | 是 | 媒体广告活动 ID |
| `dates` | string/date[] | 是 | 需要查询的日期列表 |

### 请求示例

```json
[
  {"id": 8960367, "dates": ["2023-10-07", "2023-10-06"]},
  {"id": 9876543, "dates": ["2023-10-07", "2023-12-06"]}
]
```

## 9.4 按日搜索簇统计

**POST** `https://advert-api.wildberries.ru/adv/v1/normquery/stats`

### 功能

按天返回搜索簇统计，包括浏览、点击、加购、订单、CTR、CPC、CPM 等。支持 `cpm` 和 `cpc` 付款模式广告活动。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `from` | string/date | 是 | 开始日期 |
| `to` | string/date | 是 | 结束日期 |
| `items` | object[] | 是 | 查询项，最多 100 条 |
| `items[].advertId` | integer | 是 | 广告活动 ID |
| `items[].nmId` | integer | 是 | WB 商品 ID |

### 请求示例

```json
{
  "from": "2026-01-01",
  "to": "2026-01-30",
  "items": [
    {"advertId": 123456789, "nmId": 987654321}
  ]
}
```

---

# 10. Promotions Calendar 促销日历

> 使用 Prices and Discounts 分类 Token。  
> 该模块接口统一限流通常为：6 秒 10 次请求，间隔 600ms，Burst 5。

## 10.1 获取促销活动列表

**GET** `https://dp-calendar-api.wildberries.ru/api/v1/calendar/promotions`

### 功能

获取促销活动列表及开始/结束时间。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `startDateTime` | string/date-time | 是 | 开始时间，格式 `YYYY-MM-DDTHH:MM:SSZ` |
| `endDateTime` | string/date-time | 是 | 结束时间，格式 `YYYY-MM-DDTHH:MM:SSZ` |
| `allPromo` | boolean | 是 | `false` 仅可参与促销；`true` 全部促销 |
| `limit` | integer/uint | 否 | 返回数量，1–1000 |
| `offset` | integer/uint | 否 | 偏移量，>= 0 |

### 响应示例

```json
{
  "data": {
    "promotions": [
      {
        "id": 123,
        "name": "скидки",
        "startDateTime": "2023-06-05T21:00:00Z",
        "endDateTime": "2023-06-05T21:00:00Z",
        "type": "regular"
      }
    ]
  }
}
```

## 10.2 获取促销活动详情

**GET** `https://dp-calendar-api.wildberries.ru/api/v1/calendar/promotions/details`

### 功能

获取指定促销活动的详细信息。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `promotionIDs` | integer[] | 是 | 促销活动 ID，1–100 个，唯一；格式：`promotionIDs=1&promotionIDs=3` |

### 响应核心字段

| 字段 | 说明 |
|---|---|
| `data.promotions[].id` | 促销 ID |
| `data.promotions[].name` | 促销名称 |
| `data.promotions[].description` | 描述 |
| `data.promotions[].advantages` | 优势/权益 |
| `data.promotions[].startDateTime` | 开始时间 |
| `data.promotions[].endDateTime` | 结束时间 |
| `data.promotions[].type` | 促销类型，如 `auto` |
| `data.promotions[].participationPercentage` | 参与比例 |
| `data.promotions[].ranging` | 排名/加权规则 |

## 10.3 获取可参与促销的商品列表

**GET** `https://dp-calendar-api.wildberries.ru/api/v1/calendar/promotions/nomenclatures`

### 功能

获取适合参与指定促销活动的商品列表。不适用于自动促销。

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `promotionID` | integer | 是 | 促销活动 ID |
| `inAction` | boolean | 是 | 是否已参与促销：`true` 是；`false` 否 |
| `limit` | integer/uint | 否 | 返回数量，1–1000 |
| `offset` | integer/uint | 否 | 偏移量，>= 0 |

### 响应示例

```json
{
  "data": {
    "nomenclatures": [
      {
        "id": 162579635,
        "inAction": true,
        "price": 1500,
        "currencyCode": "RUB",
        "planPrice": 1000,
        "discount": 15,
        "planDiscount": 34
      }
    ]
  }
}
```

## 10.4 添加商品到促销活动

**POST** `https://dp-calendar-api.wildberries.ru/api/v1/calendar/promotions/upload`

### 功能

创建促销商品上传任务。上传状态需通过 Prices and Discounts 模块的任务历史接口查询。不适用于自动促销。

### Body 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `data` | object | 是 | 请求数据 |
| `data.promotionID` | integer | 是 | 促销活动 ID |
| `data.uploadNow` | boolean | 是 | 是否立即上传 |
| `data.nomenclatures` | integer[] | 是 | 商品 ID 列表 |

### 请求示例

```json
{
  "data": {
    "promotionID": 1,
    "uploadNow": true,
    "nomenclatures": [75632091, 31322455, 642080796]
  }
}
```

### 响应示例

```json
{
  "data": {
    "alreadyExists": false,
    "uploadID": 11
  }
}
```

---

# 11. Recommendations 商品推荐

> 使用 Content 分类 Token。  
> 方法仅支持 Personal / Service Token。  
> 需要 Advanced/Premium Jam 订阅，或 Plan Builder 中的 Seller Recommendations in listings 选项。  
> 限流：1 分钟 100 次请求，间隔 600ms，Burst 5。

## 11.1 获取商品推荐列表

**POST** `https://content-api.wildberries.ru/api/content/v1/recommendations/list`

### 功能

获取商品推荐列表。

### Body 参数

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `brandNames` | string[] | 否 | - | 品牌，最多 30 个 |
| `limit` | integer | 否 | 20 | 返回数量，0–5000 |
| `next` | integer | 否 | 0 | 游标，上一次响应中的最后一个 `nmId` |
| `search` | string | 否 | - | 搜索；按 `nmId` 完全匹配，或按 `vendorCode` 部分匹配；最长 72 字符 |
| `subjectIds` | integer[] | 否 | - | 类目 ID，最多 30 个 |

### 请求示例

```json
{
  "brandNames": ["Comma"],
  "limit": 20,
  "next": 123,
  "search": "410",
  "subjectIds": [123, 5231]
}
```

### 响应核心字段

| 字段 | 说明 |
|---|---|
| `data[].nmId` | 商品 ID |
| `data[].imtId` | 商品组/卡片 ID |
| `data[].vendorCode` | 卖家货号 |
| `data[].brandName` | 品牌 |
| `data[].title` | 商品标题 |
| `data[].subjectName` | 类目名称 |
| `data[].pic` | 主图 |
| `data[].recomCount` | 推荐商品数量 |
| `data[].recomPics` | 推荐商品图片 |
| `data[].recomNms` | 推荐商品 ID 列表 |
| `next` | 下一页游标 |

## 11.2 设置商品推荐

**POST** `https://content-api.wildberries.ru/api/content/v1/recommendations/set`

### 功能

更新、添加或删除商品推荐。

### Body 参数

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `recList` | object[] | 是 | - | 商品推荐列表，1–5000 条 |
| `recList[].nmId` | integer | 是 | - | 主商品 ID |
| `recList[].recommendations` | object[] | 是 | - | 推荐商品列表 |
| `recList[].recommendations[].recomNm` | integer | 是 | - | 推荐商品 ID |
| `recList[].recommendations[].sort` | integer | 是 | - | 排序值 |
| `replace` | boolean | 否 | `false` | `false` 添加到当前推荐；`true` 用新推荐替换当前推荐 |

### 请求示例

```json
{
  "recList": [
    {
      "nmId": 5870243,
      "recommendations": [
        {"recomNm": 5870244, "sort": 1}
      ]
    }
  ],
  "replace": true
}
```

### 响应

| 状态码 | 含义 |
|---:|---|
| 200 | 成功 |
| 208 | 已报告/重复处理 |
| 400 | 请求错误 |
| 401 | 未授权 |
| 429 | 请求过多 |

### 响应示例

```json
{
  "isError": true,
  "errors": [
    {
      "mainNm": "5870243",
      "recomNm": "5870244",
      "message": "The item has no photo"
    }
  ]
}
```

---

# 12. 通用响应状态码说明

| 状态码 | 说明 |
|---:|---|
| 200 | 请求成功 |
| 204 | 请求成功但无内容，或未找到对应记录 |
| 208 | 已报告/重复处理 |
| 400 | 请求参数错误 |
| 401 | 未授权，请检查 Token |
| 402 | Payment required，通常与权限/付费条件有关 |
| 403 | 无访问权限 |
| 404 | 未找到 |
| 422 | 参数处理错误或状态无法变更 |
| 429 | 请求过多，触发限流 |

# 13. 使用建议

1. 所有金额/出价字段如 `bid_kopecks`、`bidKopecks` 通常以 kopecks 为单位。
2. 修改活动状态、出价、预算后，不要立即强依赖查询结果，建议按官方同步周期做重试或延迟查询。
3. 创建活动前建议先调用：
   - `/adv/v1/supplier/subjects` 获取可用子类目；
   - `/adv/v2/supplier/nms` 获取可投放商品；
   - `/api/advert/v1/bids/min` 获取最低出价。
4. 启动活动前建议先调用 `/adv/v1/budget` 检查预算，预算不足时调用 `/adv/v1/budget/deposit` 充值。
5. 搜索簇出价接口仅适用于自定义出价且 `cpm` 模式的广告活动。
6. Promotions Calendar 与 Recommendations 分属不同 Token 分类，不能混用 Promotion Token。
