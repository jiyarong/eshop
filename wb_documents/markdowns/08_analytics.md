# 数据分析 API（Analytics）

**Base URL**: `https://seller-analytics-api.wildberries.ru`  
**Token 类别**: Аналитика（分析）

---

## 一、销售漏斗（Воронка продаж）

数据每1小时更新，展示商品从曝光到下单的全链路数据。

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/analytics/v3/sales-funnel/products` | 商品统计（对比当期与上期） |
| POST | `/api/analytics/v3/sales-funnel/products/history` | 商品按天/周统计（最多7天） |
| POST | `/api/analytics/v3/sales-funnel/grouped/history` | 商品分组按天统计 |

**响应字段**:
```json
{
  "data": {
    "products": [
      {
        "nmID": 12345678,
        "vendorCode": "MY-SKU",
        "brandName": "MyBrand",
        "category": "Футболки",
        "openCard": 10000,     // 商品详情页浏览量
        "addToCart": 500,      // 加购次数
        "orders": 200,         // 下单次数
        "ordersSum": 400000,   // 下单金额（分）
        "buyouts": 180,        // 完成支付次数
        "buyoutsSum": 360000,
        "cancelCount": 20,
        "cancelSum": 40000,
        "avgOrdersCountPerDay": 6.7,
        "conversionToCart": 5.0,   // 转加购率 %
        "cartToOrder": 40.0        // 加购转下单率 %
      }
    ]
  }
}
```

---

## 二、搜索词报告（Поисковые запросы）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v2/search-report/report` | 搜索报告主页数据 |
| POST | `/api/v2/search-report/table/groups` | 搜索词分组分页 |
| POST | `/api/v2/search-report/table/details` | 分组内商品详情分组分页 |
| POST | `/api/v2/search-report/product/search-texts` | 某商品的搜索词列表（已验证可用） |
| POST | `/api/v2/search-report/product/orders` | 按搜索词维度查询下单量和排名（参数格式待确认，测试时持续400） |

### `/api/v2/search-report/product/search-texts` 请求参数（已验证）

**注意**：此接口使用 `:seller_analytics` 服务键，即 `seller-analytics-api.wildberries.ru`。

```json
{
  "nmIds": [12345678],          // 必填，Array，商品 nmId 列表（每次最多 10 个）
  "currentPeriod": {
    "start": "2026-06-01",      // ISO8601 日期
    "end":   "2026-06-07"
  },
  "topOrderBy": "orders",       // 必填，排序基准字段（"orders" | "openCard" 等）
  "orderBy": {
    "field": "orders",
    "mode":  "desc"
  },
  "limit":  100,                // 每页条数，最大 100
  "offset": 0                   // 分页偏移
}
```

**响应结构**：
```json
{
  "data": {
    "items": [
      {
        "text":           "поисковый запрос",   // 搜索词
        "nmId":           12345678,
        "vendorCode":     "MY-SKU",
        "subjectName":    "Электрочайники",
        "brandName":      "MyBrand",
        "name":           "Чайник MyBrand 1.7л",
        "rating":         4.8,
        "feedbackRating": 4.7,
        "price": { "minPrice": 1200.0, "maxPrice": 1500.0 },
        "avgPosition":    { "current": 8.3 },
        "medianPosition": { "current": 7.0 },   // 中位排名（比均值更稳定）
        "frequency":      { "current": 15000 }, // 周搜索量
        "weekFrequency":  12000,
        "openCard":       { "current": 320,  "percentile": 72 },
        "addToCart":      { "current": 48,   "percentile": 68 },
        "openToCart":     { "current": 0.15, "percentile": 65 }, // 点击→加购转化率
        "cartToOrder":    { "current": 0.42, "percentile": 70 }, // 加购→下单转化率
        "orders":         { "current": 20,   "percentile": 71 },
        "visibility":     { "current": 85 }  // 在该词搜索结果中的可见度 %
      }
    ]
  }
}
```

**实现注意事项**：
- 每次最多传 10 个 nmId，多个商品需循环分批（`each_slice(10)`）
- `offset` 分页：`break if items.size < limit`
- `medianPosition` 是综合 SEO 排名的推荐基准；用 `openCard` 加权平均可得到单品综合排名
- 综合 SEO 排名公式：`Σ(medianPosition_i × openCard_i) / Σ(openCard_i)`
- 无需特殊订阅（普通账号即可访问）

---

## 三、库存历史报告（История остатков）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/analytics/v1/stocks-report/wb-warehouses` | WB 各仓库实时库存 |
| POST | `/api/v2/stocks-report/products/groups` | 库存分组数据 |
| POST | `/api/v2/stocks-report/products/products` | 按商品维度库存数据 |
| POST | `/api/v2/stocks-report/products/sizes` | 按尺码维度库存数据 |
| POST | `/api/v2/stocks-report/offices` | 按仓库维度库存数据 |

---

## 四、分析师 CSV 报告（异步下载）

三步骤：创建任务 → 查询状态 → 下载文件

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v2/nm-report/downloads` | 创建报告下载任务 |
| GET | `/api/v2/nm-report/downloads` | 获取报告任务列表 |
| POST | `/api/v2/nm-report/downloads/retry` | 重新生成报告 |
| GET | `/api/v2/nm-report/downloads/file/{downloadId}` | 下载报告文件 |
