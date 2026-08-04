---
name: supply-order-query
description: Query WB and Ozon supply-order records through the ERP AI business API with store, SPU/SKU, operator, status, and pagination filters.
---

# Supply Order Query API Skill

用于回答 WB、Ozon 送仓单、送仓商品、送仓状态、预约仓库、实际仓库、送仓数量和验收数量相关问题。

## 强制调用业务 API

送仓记录查询统一调用 `POST /ai/supply_order_reports.json`。该接口复用送仓记录页面的查询和 SKU 归属逻辑，不要用 SQL 手动复刻列表。

```http
POST /ai/supply_order_reports.json
Authorization: Bearer <user_api_key>
Content-Type: application/json

{
  "store_ref": "wb:2",
  "sku_codes": ["SKU001"],
  "operator_id": 18,
  "statuses": ["4", "5"],
  "page": 1
}
```

## 店铺选择

`store_ref` 必填，格式是 `wb:<raw_wb_seller_accounts.id>` 或 `ozon:<raw_ozon_seller_accounts.id>`。一次请求只查询一个平台账号。

用户只给店铺名时，先通过只读 SQL 搜索启用店铺，并让结果唯一后再调用业务 API：

```sql
SELECT 'wb:' || rsa.id AS store_ref, rsa.name AS store_name
FROM raw_wb_seller_accounts rsa
WHERE rsa.is_active = true AND rsa.name ILIKE '%店铺关键词%'
UNION ALL
SELECT 'ozon:' || rsa.id AS store_ref, rsa.company_name AS store_name
FROM raw_ozon_seller_accounts rsa
WHERE rsa.is_active = true AND rsa.company_name ILIKE '%店铺关键词%'
ORDER BY store_name
```

不要查询账号 token、API key、client secret 等凭据。多个店铺匹配时先请用户选择，不要猜测。

## 请求参数

- `store_ref`：必填的平台账号引用。
- `master_sku_ids` / `master_sku_id`：SPU ID，多选或单值；API 展开为所属 SKU。
- `sku_codes` / `sku_code`：内部 SKU code，多选或单值，按标准化后的精确 code 筛选。
- `operator_id`：平台商品当前绑定的运营人员用户 ID。
- `statuses`：平台原始送仓状态，多选；必须使用所选平台的状态值。
- `page` / `jump_page`：页码；`jump_page` 优先。ERP AI 接口每页固定 100 条。

SPU/SKU 和运营人员筛选基于所选店铺的平台商品绑定。没有 SKU 或运营筛选时，未绑定内部 SKU 的平台商品仍会显示，且 `sku_code`、`product_name` 为空；启用 SKU 或运营筛选后，未绑定商品不会命中。

## 状态枚举

WB `statuses` 使用数字 ID 的字符串形式：

- `1`：not_planned
- `2`：planned
- `3`：unloading_allowed
- `4`：accepting
- `5`：accepted
- `6`：unloaded_at_gate

Ozon `statuses` 使用以下字符串：

- `DATA_FILLING`
- `READY_TO_SUPPLY`
- `ACCEPTED_AT_SUPPLY_WAREHOUSE`
- `IN_TRANSIT`
- `ACCEPTANCE_AT_STORAGE_WAREHOUSE`
- `REPORTS_CONFIRMATION_AWAITING`
- `REPORT_REJECTED`
- `COMPLETED`
- `REJECTED_AT_SUPPLY_WAREHOUSE`
- `CANCELLED`
- `OVERDUE`

切换平台后必须重新选择状态，不要把一个平台的状态传给另一个平台。

## 响应结构

```json
{
  "success": true,
  "data": {
    "meta": {
      "platform": "wb",
      "store_ref": "wb:2",
      "store_name": "Store name",
      "columns": ["supply_id", "status", "platform_item_id", "sku_code"]
    },
    "rows": [],
    "pagination": {
      "page": 1,
      "per_page": 100,
      "total_count": 0,
      "total_pages": 1
    }
  },
  "message": "ok"
}
```

结果按送仓创建时间从新到旧排列，并按“送仓单 × 商品”铺开。同一送仓单包含多个商品时会返回多行。根据 `pagination.total_pages` 继续请求后续页。

## 平台字段

公共核心字段包括 `supply_id`、`status`、`platform_item_id`、`sku_code`、`product_name`、`quantity`、`created_at`、`synced_at`。

WB 还可能返回：

- `preorder_id`、`accepted_quantity`、`remaining_quantity`
- `warehouse_name`、`actual_warehouse_name`、`transit_warehouse_name`
- `scheduled_at`、`actual_at`
- `packaging`、`pallet`
- `acceptance_cost`、`paid_acceptance_coefficient`、`storage_coefficient`、`delivery_coefficient`
- `supplier_assign_name`、`reject_reason`
- `supply_quantity`、`supply_accepted_quantity`、`ready_for_sale_quantity`、`unloading_quantity`、`depersonalized_quantity`、`can_show_quantity`

WB 包装类型：`0` 为 without_boxes；`1`、`2` 为 boxes；`5` 为 mono_pallet；`6` 为 super_safe；`7` 为 piece_pallet。`pallet=true` 时按 piece_pallet 理解，优先于包装类型 ID。

Ozon 还可能返回：

- `order_number`
- `timeslot`
- `origin_warehouse`
- `destination_warehouses`
- `state_updated_at`

`destination_warehouses` 是当前送仓单已保存的目的仓列表，可能不是某一商品的独立目的仓分配。

## 数据边界

- WB 平台商品通过所选账号对应店铺下的 `ec_sku_products.product_id = raw_wb_supply_items.nm_id` 归属内部 SKU。
- Ozon 平台商品通过所选账号对应店铺下的 `ec_sku_products.platform_sku_id = raw_ozon_supply_orders.items` 中的 SKU 归属内部 SKU。
- 归属必须同时限定平台和店铺账号，不能跨店铺兜底，也不要用商品名猜 SKU。
- 字段为空表示平台未返回或本系统未保存。不要推断缺失的仓库、目的地、时间、数量或商品归属。
- 本接口只读已同步数据，不触发 WB/Ozon 平台同步或历史补数。
