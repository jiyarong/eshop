# 营销推广 API（Promotion）

**Base URL**: `https://advert-api.wildberries.ru`  
**Token 类别**: Реклама（广告）

---

## 广告活动类型

| 类型 | 说明 |
|------|------|
| **搜索广告**（Поиск） | 在搜索结果中展示商品，按搜索词出价 |
| **自动广告**（Автоматическая） | WB 自动选择展示位置 |
| **媒体广告**（Медиа） | 横幅/视频等富媒体广告 |
| **PromotionId（品牌专区）** | - |

---

## 一、广告活动管理

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/adv/v1/promotion/count` | 获取各状态广告活动数量 |
| GET | `/api/advert/v2/adverts` | 获取广告活动详情列表（忽略 id 参数，始终返回全部活动） |
| GET | `/api/advert/v1/bids/min` | 获取商品最低出价 |
| POST | `/adv/v2/seacat/save-ad` | 创建广告活动 |
| GET | `/adv/v1/supplier/subjects` | 获取可用于广告的分类 |
| GET | `/adv/v2/supplier/nms` | 获取可用于广告的商品 |
| DELETE | `/adv/v0/delete` | 删除广告活动 |
| GET/POST | `/adv/v0/rename` | 重命名广告活动 |
| GET | `/adv/v0/start` | 启动广告活动 |
| GET | `/adv/v0/pause` | 暂停广告活动 |
| GET | `/adv/v0/stop` | 停止广告活动 |

**`/adv/v1/promotion/count` 响应结构**（campaign 列表）:
```json
{
  "adverts": [
    {
      "type": 9,
      "status": 9,
      "advert_list": [
        { "advertId": 12345, "changeTime": "2024-01-15T10:00:00Z" }
      ]
    }
  ]
}
```

**`/api/advert/v2/adverts` 响应结构**（campaign 详情，含 SKU 绑定）:
```json
{
  "adverts": [
    {
      "id": 12345,
      "bid_type": "unified",
      "currency": "RUB",
      "status": 9,
      "settings": {
        "name": "моя кампания",
        "payment_type": "cpm",
        "placements": { "search": true, "recommendations": true }
      },
      "nm_settings": [
        {
          "nm_id": 305715163,
          "subject": { "id": 1594, "name": "швабры" },
          "bids_kopecks": { "search": 12500, "recommendations": 12500 }
        }
      ],
      "timestamps": {
        "created": "2025-01-23T05:37:30+03:00",
        "started": "2025-02-18T14:53:08+03:00",
        "deleted": "2025-02-18T14:53:22+03:00",
        "updated": "2026-03-12T19:38:32+03:00"
      }
    }
  ]
}
```

> **注意**：
> - `status` 含义：7=завершена（已结束）、9=активна（运行中）、11=на паузе（暂停）
> - `nm_settings[].bids_kopecks` 单位为**戈比**（÷100 = 卢布）
> - `id` 查询参数被 API 忽略，始终返回该账号所有广告活动

---

## 二、出价与定向

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/adv/v0/auction/placements` | 修改手动出价广告的位置 |
| POST | `/api/advert/v1/bids` | 修改广告出价 |
| POST | `/adv/v0/auction/nms` | 修改广告活动中的商品列表 |
| POST | `/api/advert/v0/bids/recommendations` | 获取推荐出价 |
| GET | `/adv/v0/normquery/get-bids` | 获取搜索词出价列表 |
| POST | `/adv/v0/normquery/bids` | 设置搜索词出价 |
| DELETE | `/adv/v0/normquery/bids` | 删除搜索词出价 |
| GET | `/adv/v0/normquery/get-minus` | 获取否定词（屏蔽词）列表 |
| POST | `/adv/v0/normquery/set-minus` | 设置/删除否定词 |
| GET | `/adv/v0/normquery/list` | 获取激活/未激活的搜索词列表 |

---

## 三、预算与财务

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/adv/v1/balance` | 获取广告账户余额 |
| GET | `/adv/v1/budget` | 获取广告活动预算 |
| POST | `/adv/v1/budget/deposit` | 向广告活动充值 |
| GET | `/adv/v1/upd` | 获取消耗历史 |
| GET | `/adv/v1/payments` | 获取账户充值历史 |

---

## 四、媒体广告

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/adv/v1/count` | 媒体活动数量 |
| GET | `/adv/v1/adverts` | 媒体活动列表 |
| GET | `/adv/v1/advert` | 媒体活动详情 |

---

## 五、广告统计

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/adv/v3/fullstats` | 广告活动全量统计（展示、点击、花费、订单） |
| GET | `/adv/v1/stats` | 媒体广告统计 |
| POST | `/adv/v0/normquery/stats` | 搜索词统计 |
| GET | `/adv/v1/normquery/stats` | 按天搜索词统计 |

**统计字段**:
```json
{
  "advertId": 12345,
  "days": [
    {
      "date": "2024-01-15",
      "views": 10000,
      "clicks": 500,
      "ctr": 5.0,
      "cpc": 20.0,
      "sum": 10000.0,
      "atbs": 50,     // 加购次数
      "orders": 30,
      "cr": 6.0,
      "shks": 28,
      "sum_price": 140000
    }
  ]
}
```

---

## 六、促销活动（Календарь акций）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/calendar/promotions` | 获取促销活动列表 |
| POST | `/api/v1/calendar/promotions/details` | 获取促销活动详情 |
| POST | `/api/v1/calendar/promotions/nomenclatures` | 获取可参与促销的商品 |
| POST | `/api/v1/calendar/promotions/upload` | 将商品加入促销 |
