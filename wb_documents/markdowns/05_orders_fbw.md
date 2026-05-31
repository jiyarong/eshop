# FBW 供货 API（WB 仓库履约）

**Base URL**: `https://supplies-api.wildberries.ru`  
**Token 类别**: Маркетплейс

---

## FBW 说明

卖家将商品提前运入 WB 仓库，由 WB 负责存储、包装和配送。卖家只需通过供货 API 创建入仓计划。

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/acceptance/options` | 获取入仓选项（哪些仓库可入仓、入仓类型） |
| GET | `/api/v1/warehouses` | 获取可用 WB 仓库列表 |
| GET | `/api/v1/transit-tariffs` | 获取转运路线及运费 |
| GET | `/api/v1/supplies` | 获取供货单列表（分页） |
| GET | `/api/v1/supplies/{ID}` | 获取供货单详情 |
| GET | `/api/v1/supplies/{ID}/goods` | 获取供货单中的商品列表 |
| POST | `/api/v1/supplies/{ID}/package` | 提交供货单包装信息 |

---

## 供货单字段

```json
{
  "id": "WB-GI-XXXXXXXX",
  "status": "draft",        // draft, processing, accepted, rejected
  "createdAt": "2024-01-01T10:00:00Z",
  "warehouseId": 123,
  "type": "fbw",
  "goods": [
    {
      "nmID": 12345678,
      "vendorCode": "MY-SKU",
      "quantity": 50
    }
  ]
}
```

## FBW 与 FBS 关键区别

| 维度 | FBS | FBW |
|------|-----|-----|
| 发货频率 | 按订单频繁发货 | 批量入仓（每次可多件） |
| 库存位置 | 卖家自己仓库 | WB 仓库 |
| 发货速度 | 受限于卖家物流 | WB 保证快速配送 |
| 库存更新 | 实时调用 API 更新 | 入仓后 WB 系统自动管理 |
| 入仓计划 | 无需 | 需要提前创建供货单 |
