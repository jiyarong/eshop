# 财务报表 API（Financial Reports）

**Base URL**: `https://finance-api.wildberries.ru`  
**Token 类别**: Финансы（财务）  
**限流**: Personal/Service 1 req/min；Basic 1 req/24h（极严格，需缓存结果）

---

## 一、账户余额

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/account/balance` | 获取账户余额（当前余额 + 可提现余额） |

**响应**:
```json
{
  "currency": "RUB",
  "current": 10196.21,      // 当前余额
  "for_withdraw": 6395.80   // 可提现金额
}
```

---

## 二、销售实现报告（Отчёты реализации）

对账核心接口。数据从 2025年1月1日 开始提供。

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/finance/v1/sales-reports/list` | 按时间段获取报告列表 |
| POST | `/api/finance/v1/sales-reports/detailed/{reportId}` | 按报告 ID 获取明细 |
| POST | `/api/finance/v1/sales-reports/detailed` | 按时间段获取明细 |
| GET | `/api/v5/supplier/reportDetailByPeriod` | 旧版报表（Deprecated） |

请求参数（POST body）：
```json
{
  "dateFrom": "2024-01-01",
  "dateTo": "2024-01-31"
}
```

**报告明细字段（部分）**:
```json
{
  "realizationreport_id": 12345,    // 报告 ID
  "date_from": "2024-01-01",
  "date_to": "2024-01-07",
  "create_dt": "2024-01-08",
  "suppliercontract_code": null,
  "nm_id": 12345678,
  "brand_name": "MyBrand",
  "sa_name": "MY-SKU",             // 卖家 SKU
  "ts_name": "XL",                 // 尺码
  "barcode": "4607133781434",
  "doc_type_name": "Продажа",      // Продажа/Возврат
  "quantity": 1,
  "retail_price": 1999,            // 含折扣价格
  "retail_amount": 1999,
  "sale_percent": 30,
  "commission_percent": 15.5,      // WB 佣金比例
  "ppvz_for_pay": 1424.79,         // 实际打款给卖家金额
  "delivery_rub": 100,             // 物流费
  "penalty": 0,                    // 罚款
  "additional_payment": 0,         // 额外付款
  "srid": "xxx"
}
```

---

## 三、支付处理费用报告（Acquiring）

> 仅限俄罗斯卖家

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/finance/v1/acquiring/list` | 获取支付手续费报告列表 |
| POST | `/api/finance/v1/acquiring/detailed/{reportId}` | 按报告 ID 获取明细 |
| POST | `/api/finance/v1/acquiring/detailed` | 按时间段获取明细 |

---

## 四、文档管理

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/documents/categories` | 获取文档分类（合同、发票、证书等） |
| POST | `/api/v1/documents/list` | 获取文档列表（按分类、时间段筛选） |
| GET | `/api/v1/documents/download` | 下载单个文档 |
| POST | `/api/v1/documents/download/all` | 批量下载文档（ZIP） |
