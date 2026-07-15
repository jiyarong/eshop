# Inventory And Procurement SQL Skill

用于回答库存、平台库存快照、账面库存、采购批次、到货、供应商、采购单、在途库存相关问题。

## 适用问题

- 当前平台库存、按店铺/平台/履约类型/仓库拆分库存。
- 账面库存、采购到货、在途批次。
- SKU 批次、采购单、供应商查询。
- 库存周转、缺货风险、平台库存与账面库存差异排查。

## 库存表

### `ec_sku_inventory_levels`

平台库存快照表，当前库存和历史快照都在此表。

- `id`：库存记录 ID。
- `sku_code`：内部 SKU 编码。
- `platform`：平台，`wb`、`ozon`。
- `store_id`：内部店铺 ID，可为空。
- `store_name`：店铺名快照。
- `account_id`：平台原始账号 ID；WB 对应 `raw_wb_seller_accounts.id`，Ozon 对应 `raw_ozon_seller_accounts.id`。
- `fulfillment_type`：履约/库存类型，常见 `fbo`、`fbw`、`fbs`、`inbound`。
- `quantity`：库存数量。
- `warehouse_breakdown`：仓库拆分 JSON 数组。
- `metadata`：平台同步附加信息。
- `is_latest`：是否当前最新快照。
- `synced_at`：平台库存同步时间。
- `created_at`、`updated_at`。

关系与口径：

- `ec_sku_inventory_levels.sku_code = ec_skus.sku_code`。
- `ec_sku_inventory_levels.store_id = ec_stores.id`，可为空。
- 查询当前平台库存必须加 `is_latest = true`。
- 库存页面 GET 请求只读；不要触发平台库存同步。
- `fulfillment_type IN ('fbo','fbw')` 常表示平台仓现货；`inbound` 表示平台入库/在途；`fbs` 表示卖家侧库存。

## 批次与账面库存

### `ec_sku_batches`

SKU 采购/到货/账面库存批次表。

- `id`：批次 ID。
- `batch_code`：批次编码，唯一，通常大写。
- `sku_code`：内部 SKU 编码。
- `status`：批次状态，`draft`、`ordered`、`in_transit`、`received`、`closed`。
- `batch_type`：批次类型，Rails enum 整数：`normal=1`、`wb_fbw_offset=2`、`untrackable_defective=3`、`other=4`。
- `purchase_date`：采购日期。
- `expected_arrival_on`：预计到货日。
- `received_on`：实际到货日。
- `purchased_quantity`：采购数量。
- `received_quantity`：到货数量。
- `purchase_unit_price_cny`：采购单价，人民币。
- `defect_offset_note`：缺陷/抵扣说明。
- `memo`：备注。
- `created_at`、`updated_at`。

关系与口径：

- `ec_sku_batches.sku_code = ec_skus.sku_code`。
- 账面已到货通常统计 `status IN ('received','closed')`。
- 正常采购到货数量通常只统计 `batch_type = 1`。
- 非 `normal` 批次通常作为库存调整或特殊抵扣，查询时应单独说明。
- 批次成本可关联采购单明细和费用分摊。

## 采购表

### `ec_purchase_orders`

采购单表。

- `id`：采购单 ID。
- `order_no`：采购单号，唯一。
- `supplier_id`：供应商 ID。
- `ordered_on`：下单日期。
- `status`：状态，默认 `draft`。
- `currency`：币种，默认 `CNY`。
- `memo`：备注。
- `created_at`、`updated_at`。

关系：

- `ec_purchase_orders.supplier_id = ec_suppliers.id`。
- `ec_purchase_order_items.purchase_order_id = ec_purchase_orders.id`。

### `ec_purchase_order_items`

采购单明细表。

- `id`：明细 ID。
- `purchase_order_id`：采购单 ID。
- `sku_batch_id`：SKU 批次 ID。
- `sku_code`：内部 SKU 编码。
- `quantity`：采购数量。
- `unit_price_cny`：采购单价。
- `memo`：备注。
- `created_at`、`updated_at`。

关系：

- `ec_purchase_order_items.purchase_order_id = ec_purchase_orders.id`。
- `ec_purchase_order_items.sku_batch_id = ec_sku_batches.id`。
- `ec_purchase_order_items.sku_code = ec_skus.sku_code`。

### `ec_suppliers`

供应商表。

- `id`：供应商 ID。
- `name`：供应商名。
- `contact_name`、`phone`、`wechat`、`email`：联系人信息。
- `address`：地址。
- `is_active`：是否启用。
- `memo`：备注。
- `created_at`、`updated_at`。

## 平台入库/供货原始表

- WB 供货单：`raw_wb_supplies`，关键字段 `account_id`、`wb_supply_id`、`name`、`is_done`、`supply_created_at`、`supply_date`、`closed_at`、`status_id`。
- WB 供货商品：`raw_wb_supply_items`，关键字段 `account_id`、`wb_supply_id`、`nm_id`、`quantity`、`accepted_qty`。
- Ozon 供货单：`raw_ozon_supply_orders`，关键字段 `account_id`、`supply_order_id`、`status`、`items`、`timeslot`、`synced_at`。

## 查询策略

- 当前平台库存优先查 `ec_sku_inventory_levels`，并加 `is_latest = true`。
- 账面库存、采购到货优先查 `ec_sku_batches`。
- 在途采购可看 `ec_sku_batches.status IN ('ordered','in_transit')`。
- 平台入库/供货排查才查 `raw_wb_supply_items`、`raw_wb_supplies`、`raw_ozon_supply_orders`。
- 库存与销量结合时，销量归属必须加载 `orders_sales` Skill。
