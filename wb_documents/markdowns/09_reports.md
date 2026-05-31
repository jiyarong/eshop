# 统计报表 API（Reports）

**Base URL**: `https://statistics-api.wildberries.ru`  
**Token 类别**: Статистика（统计）  

> 部分旧版接口标记为 `Deprecated`，建议使用新版异步报告接口。

---

## 一、基础实时报表（旧版，部分 Deprecated）

| 方法 | 路径 | 说明 | 状态 |
|------|------|------|------|
| GET | `/api/v1/supplier/stocks` | 仓库库存报表 | ⚠️ Deprecated |
| GET | `/api/v1/supplier/orders` | 订单报表（每30分钟更新，保存90天） | 有效 |
| GET | `/api/v1/supplier/sales` | 销售&退货报表（每30分钟更新） | 有效 |

**订单报表字段（部分）**:
```json
{
  "gNumber": "xxx",          // 订单号（同一买家订单的商品共用）
  "date": "2024-01-01T10:00:00Z",
  "lastChangeDate": "...",
  "supplierArticle": "MY-SKU",
  "techSize": "XL",
  "barcode": "4607133781434",
  "totalPrice": 1999,         // 原价（RUB）
  "discountPercent": 30,      // 折扣 %
  "warehouseName": "Коледино",
  "oblast": "Москва",         // 地区
  "incomeID": 0,
  "odid": 987654321,          // 唯一订单 ID（= srid）
  "nmId": 12345678,
  "subject": "Футболки",
  "category": "Одежда",
  "brand": "MyBrand",
  "isCancel": false,
  "cancelDate": "",
  "orderType": "Клиентский",
  "sticker": "xxx",
  "srid": "xxx"               // 推荐用于订单唯一标识
}
```

---

## 二、仓库库存报告（异步，3步骤）

| 步骤 | 方法 | 路径 | 说明 |
|------|------|------|------|
| 1 | POST | `/api/v1/warehouse_remains` | 创建库存报告任务 |
| 2 | GET | `/api/v1/warehouse_remains/tasks/{task_id}/status` | 查询任务状态 |
| 3 | GET | `/api/v1/warehouse_remains/tasks/{task_id}/download` | 下载报告（ZIP/Excel） |

---

## 三、消费扣款报告

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/analytics/excise-report` | 烟草/酒类消费税报告 |
| GET | `/api/analytics/v1/measurement-penalties` | 包裹尺寸申报不实扣款 |
| GET | `/api/analytics/v1/warehouse-measurements` | 仓库实测尺寸 |
| GET | `/api/analytics/v1/deductions` | 错误商品替换扣款 |
| GET | `/api/v1/analytics/antifraud-details` | 自买自卖（刷单）扣款 |
| GET | `/api/v1/analytics/goods-labeling` | 商品标签报告 |

---

## 四、接收报告（异步，3步骤）

| 步骤 | 方法 | 路径 | 说明 |
|------|------|------|------|
| 1 | POST | `/api/v1/acceptance_report` | 创建 WB 仓库入库验收报告 |
| 2 | GET | `/api/v1/acceptance_report/tasks/{task_id}/status` | 查询状态 |
| 3 | GET | `/api/v1/acceptance_report/tasks/{task_id}/download` | 下载 |

---

## 五、付费存储报告（异步，3步骤）

| 步骤 | 方法 | 路径 | 说明 |
|------|------|------|------|
| 1 | POST | `/api/v1/paid_storage` | 创建付费存储费用报告 |
| 2 | GET | `/api/v1/paid_storage/tasks/{task_id}/status` | 查询状态 |
| 3 | GET | `/api/v1/paid_storage/tasks/{task_id}/download` | 下载 |

---

## 六、区域销售 & 品牌报告

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/analytics/region-sale` | 各省/市销售报告 |
| GET | `/api/v1/analytics/brand-share/brands` | 卖家品牌列表 |
| GET | `/api/v1/analytics/brand-share/parent-subjects` | 品牌所在父分类 |
| POST | `/api/v1/analytics/brand-share` | 品牌销售占比报告 |

---

## 七、违规商品报告

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/analytics/banned-products/blocked` | 被屏蔽的商品卡片 |
| GET | `/api/v1/analytics/banned-products/shadowed` | 从目录中隐藏的商品 |
| POST | `/api/v1/analytics/goods-return` | 退货报告 |
