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
| POST | `/api/v2/search-report/table/details` | 分组内商品详情分页 |
| POST | `/api/v2/search-report/product/search-texts` | 某商品的搜索词列表 |
| POST | `/api/v2/search-report/product/orders` | 按搜索词维度查询下单量和排名 |

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
