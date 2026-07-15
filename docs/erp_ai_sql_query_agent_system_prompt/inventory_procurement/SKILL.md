# Inventory And Batch SQL Skill

用于回答库存报表、库存详情页、平台库存快照、账面库存、在途批次、库存周转、退货和平台送仓数量相关问题。

## 适用问题

- 当前平台库存、按店铺/平台/履约类型/仓库拆分库存。
- 账面库存、在途批次、到货批次、特殊调整批次。
- 库存详情页顶部汇总、在途批次、账面库存、销售/退货分布、平台库存、仓库拆分的计算过程。
- 平台库存与账面库存差异、缺货风险、周转天数排查。

当前 Skill 不覆盖未启用的采购模块；库存报表查询以库存快照、SKU 批次、订单、退货和平台送仓原始表为准。

## 核心表

### `ec_sku_inventory_levels`

平台库存快照表，当前库存和历史快照都在此表。

- `id`：库存记录 ID。
- `sku_code`：内部 SKU 编码。
- `platform`：平台，`wb`、`ozon`。
- `store_id`：内部店铺 ID，可为空。
- `store_name`：店铺名快照。
- `account_id`：平台原始账号 ID；WB 对应 `raw_wb_seller_accounts.id`，Ozon 对应 `raw_ozon_seller_accounts.id`。
- `fulfillment_type`：库存类型，常见 `fbo`、`fbw`、`fbs`、`inbound`。
- `quantity`：库存数量。
- `warehouse_breakdown`：仓库拆分 JSON 数组，常见字段 `warehouse_name`、`quantity`、`promised`、`reserved`。
- `metadata`：平台同步附加信息。
- `is_latest`：是否当前最新快照。
- `synced_at`：平台库存同步时间。
- `created_at`、`updated_at`。

关系与口径：

- `ec_sku_inventory_levels.sku_code = ec_skus.sku_code`。
- `ec_sku_inventory_levels.store_id = ec_stores.id`，可为空。
- 当前平台库存必须加 `is_latest = true`。
- 库存页面 GET 请求只读，不触发平台库存同步。
- `fbo`、`fbw` 表示平台仓现货；`inbound` 表示平台入库/在途；`fbs` 表示卖家侧库存。

### `ec_sku_batches`

SKU 批次表，是库存详情页账面库存、在途批次和特殊调整的主要来源。

- `id`：批次 ID。
- `batch_code`：批次编码，唯一，通常大写。
- `sku_code`：内部 SKU 编码。
- `status`：批次状态，`draft`、`ordered`、`in_transit`、`received`、`closed`。
- `batch_type`：批次类型，Rails enum 整数：`normal=1`、`wb_fbw_offset=2`、`untrackable_defective=3`、`other=4`。
- `purchase_date`：采购日期。
- `expected_arrival_on`：预计到货日。
- `received_on`：实际到货日。
- `purchased_quantity`：批次数量；在途页用它展示待到货数量。
- `received_quantity`：到货/调整数量；账面库存公式用它。
- `purchase_unit_price_cny`：批次单价，人民币。
- `defect_offset_note`：缺陷/抵扣说明。
- `memo`：备注。
- `created_at`、`updated_at`。

关系与口径：

- `ec_sku_batches.sku_code = ec_skus.sku_code`。
- 在途批次：`status IN ('draft','ordered','in_transit')`。
- 账面批次：`status IN ('received','closed')`。
- 正常到货数量：账面批次中 `batch_type = 'normal'` 的 `received_quantity`。
- 特殊调整数量：账面批次中非 `normal` 的 `received_quantity`，例如 `wb_fbw_offset`、`untrackable_defective`、`other`。
- 批次可为负数调整，查询时不要简单过滤掉负数。

### `ec_orders`、`ec_order_items`、`ec_sku_products`

库存详情页中的销量、销售状态分布、日销和周转使用订单归属链路。

- `ec_order_items.order_id = ec_orders.id`。
- `ec_order_items.store_id = ec_stores.id`。
- `ec_sku_products.store_id = ec_order_items.store_id`。
- `ec_sku_products.platform = ec_order_items.platform`。
- Ozon：`ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id`。
- WB：`ec_sku_products.product_id = ec_order_items.platform_sku_id`。
- 必须使用 `ec_sku_products.sku_code` 归属内部 SKU，不要用 `ec_order_items.sku_code` 兜底。
- 取消订单不计入库存销量：`ec_orders.order_status != 'cancelled'`。

库存详情页订单状态展示桶：

- `pending` -> `pending`。
- `processing` -> `processing`。
- `shipped` -> `shipping`。
- `delivered` -> `signed`。
- `returned` 不进入销售状态展示桶，且销量归集时按 0 处理。

### 退货原始表

#### `raw_wb_goods_returns`

- `account_id`：WB 原始账号。
- `nm_id`：WB 商品 ID，对应 `ec_sku_products.product_id`。
- `shk_id`：唯一键。
- `status`、`return_type`、`reason`：退货状态和原因。
- `order_dt`、`completed_dt`、`ready_to_return_dt`、`expired_dt`：退货相关时间。
- `synced_at`：同步时间。

WB 退货归属：

- `raw_wb_goods_returns.account_id = ec_stores.wb_raw_account_id`。
- `ec_stores.platform = 'wb'`。
- `raw_wb_goods_returns.nm_id::text = ec_sku_products.product_id`。
- 每行按 1 件退货计数。

#### `raw_ozon_returns`

- `account_id`：Ozon 原始账号。
- `return_id`：退货 ID。
- `posting_number`、`order_number`、`order_id`：订单/发货单识别字段。
- `ozon_sku`、`offer_id`：商品识别字段。
- `quantity`：退货数量，空时按 1。
- `return_schema`、`return_type`、`return_reason_name`：退货类型和原因。
- `return_date`、`final_moment`、`synced_at`：退货时间。

Ozon 退货归属：

- `raw_ozon_returns.account_id = ec_stores.ozon_raw_account_id`。
- `ec_stores.platform = 'ozon'`。
- 匹配 SKU 时使用 `raw_ozon_returns.offer_id = ec_sku_products.offer_id` 或 `raw_ozon_returns.ozon_sku::text = ec_sku_products.platform_sku_id`。
- 如果能匹配到已取消订单，则该退货不计入库存退货数量。

### 平台送仓/供货原始表

这些表用于库存详情页店铺行里的 `supply_quantity`，用于排查平台送仓总量；当前账面库存公式不把它们作为入库来源。

- WB 供货单：`raw_wb_supplies`，字段 `account_id`、`wb_supply_id`、`preorder_id`、`name`、`is_done`、`supply_created_at`、`supply_date`、`closed_at`、`status_id`。
- WB 供货商品：`raw_wb_supply_items`，字段 `account_id`、`wb_supply_id`、`nm_id`、`quantity`、`accepted_qty`。
- Ozon 供货单：`raw_ozon_supply_orders`，字段 `account_id`、`supply_order_id`、`status`、`items`、`timeslot`、`synced_at`。

送仓数量口径：

- WB：按 SKU 绑定的 WB `product_id` / `nm_id` 查 `raw_wb_supply_items`，汇总 `accepted_qty`。
- Ozon：按账号读取 `raw_ozon_supply_orders.status = 'COMPLETED'`，从 `items` JSON 中取绑定的 `platform_sku_id` 数量并求和。

## 库存详情页计算过程

详情页入口：`GET /reports/inventory/:sku_code`，核心查询服务为 `Ec::InventoryPageDetailQuery`，基础汇总来自 `Ec::SkuInventoryOverview`。

### 顶部汇总卡片

- `pending_stock` / `incoming_quantity`：`ec_sku_batches.status IN ('draft','ordered','in_transit')` 的 `purchased_quantity` 求和。详情页这个值来自在途批次列表。
- `book_available_stock` / `book_stock`：`received_quantity - sales_quantity + return_quantity`。
- `platform_stock`：当前平台仓现货，`ec_sku_inventory_levels.is_latest = true` 且 `fulfillment_type IN ('fbo','fbw')` 的 `quantity` 求和。
- `overseas_available_stock` / `available_stock`：`book_stock - fbo_fbw_stock - platform_inbound_stock`。
- `daily_sales_velocity`：最近 7/15/30 天销量的加权日销。
- `turnover_days`：`book_stock / daily_sales_velocity`，日销为 0 时为空。
- `turnover_days_with_procurement`：`(book_stock + procurement_quantity) / daily_sales_velocity`，其中 `procurement_quantity` 是 `status IN ('draft','ordered','in_transit') AND batch_type = 'normal'` 的 `purchased_quantity`。

### 账面库存基础汇总

`Ec::SkuInventoryOverview#summary` 使用以下口径：

- `purchase_quantity`：账面批次中 `batch_type = 'normal'` 的 `received_quantity` 求和。
- `adjustment_quantity`：账面批次中非 `normal` 的 `received_quantity` 求和。
- `received_quantity = purchase_quantity + adjustment_quantity`。
- `sales_quantity`：订单归属到该 SKU 后，排除取消订单；`returned` 订单按 0 销量处理，其余状态按 `ec_order_items.quantity` 求和。
- `return_quantity`：WB/Ozon 退货原始表归属到该 SKU 后求和。
- `platform_stock`：所有最新平台库存 `quantity` 求和，包含 `fbo`、`fbw`、`fbs`、`inbound`。
- `platform_inbound_stock`：最新平台库存中 `fulfillment_type = 'inbound'` 的 `quantity` 求和。
- `fbo_fbw_stock`：最新平台库存中 `fulfillment_type IN ('fbo','fbw')` 的 `quantity` 求和。
- `book_stock = received_quantity - sales_quantity + return_quantity`。
- `available_stock = book_stock - fbo_fbw_stock - platform_inbound_stock`。

### 在途批次 Tab

列表来源：

- 表：`ec_sku_batches`。
- 条件：`sku_code = 当前 SKU` 且 `status IN ('draft','ordered','in_transit')`。
- 排序：`draft`、`ordered`、`in_transit` 优先级排序，再按 `expected_arrival_on`、`batch_code`。

展示字段：

- `batch_code`。
- `status`。
- `expected_arrival_on`。
- `purchased_quantity`。
- `memo`。

### 账面库存 Tab

顶部小卡：

- `purchase_quantity`：账面正常批次已到货数量。
- `wb_net_sales`：WB 店铺行 `sales_quantity` 求和。
- `ozon_net_sales`：Ozon 店铺行 `sales_quantity` 求和。

批次列表：

- 表：`ec_sku_batches`。
- 条件：`sku_code = 当前 SKU` 且 `status IN ('received','closed')`。
- 排序：`received_on DESC, batch_code DESC`。
- 分页：每页 10 条。
- 展示字段：`batch_code`、`batch_type`、`defect_offset_note`、`received_quantity`。

销售分布：

- 来源：订单归属后的店铺行 `store_rows`。
- 只显示 `platform IN ('wb','ozon')` 且状态数量合计大于 0 的店铺。
- 列固定为 `pending`、`processing`、`shipping`、`signed`。
- 汇总行是所有展示行同列求和。

退货分布：

- 来源：退货原始表归属后的店铺行 `store_rows.return_quantity`。
- 只显示退货数量大于 0 的店铺。
- 汇总行是所有展示行 `return_count` 求和。

账面公式：

- 基础公式：`purchase_quantity - wb_net_sales - ozon_net_sales + wb_returns + ozon_returns + adjustments = book_stock`。
- `wb_returns`、`ozon_returns` 分别来自退货原始表归属结果。
- `adjustments` 来自账面批次中非 `normal` 的 `received_quantity`；正数显示为加项，负数显示为减项。
- 常见调整项：`wb_fbw_offset`、`untrackable_defective`、`other_adjustment`。

### 平台库存 Tab

顶部小卡：

- `ozon_fbo`：最新库存中 `platform = 'ozon' AND fulfillment_type = 'fbo'` 的 `quantity` 求和。
- `ozon_inbound`：最新库存中 `platform = 'ozon' AND fulfillment_type = 'inbound'` 的 `quantity` 求和。
- `wb_fbo`：最新库存中 `platform = 'wb' AND fulfillment_type = 'fbw'` 的 `quantity` 求和；页面文案按 FBO/FBW 统称展示。
- `wb_inbound`：最新库存中 `platform = 'wb' AND fulfillment_type = 'inbound'` 的 `quantity` 求和。

店铺拆分：

- 来源：`ec_sku_inventory_levels.is_latest = true`。
- 分组键：`platform`、`store_name`、`store_id`、`account_id`。
- `fbo`：组内 `fulfillment_type IN ('fbo','fbw')` 的 `quantity` 求和。
- `inbound`：组内 `fulfillment_type = 'inbound'` 的 `quantity` 求和。
- `fbs`：组内 `fulfillment_type = 'fbs'` 的 `quantity` 求和。
- 汇总行分别对 `fbo`、`inbound`、`fbs` 求和。

平台库存公式：

- `available_stock = book_stock - fbo_fbw_stock - platform_inbound_stock`。
- 页面公式展示为：`book_inventory - platform_inventory_total - platform_inbound = overseas_available_stock`。
- 这里的 `platform_inventory_total` 只指 `fbo_fbw_stock`，不包括 FBS。

FBO/FBW 仓库拆分：

- 来源：最新库存中 `fulfillment_type IN ('fbo','fbw')` 的 `warehouse_breakdown` JSON。
- 每个 JSON 元素展开为一行。
- 展示字段：店铺、履约类型、仓库名、`quantity`、`promised`、`reserved`、`synced_at`。
- 只显示有仓库名，且 `quantity/promised/reserved` 至少一个为正的行。

## 日销与周转

`daily_sales_velocity` 来自 `Ec::InventoryVelocityMetricsQuery`：

- 统计窗口：最近 7 天、15 天、30 天，日期边界按当前用户时区计算。
- 销量来源：`ec_orders` + `ec_order_items`，通过 `ec_sku_products` 归属 SKU。
- 排除取消订单：`ec_orders.order_status != 'cancelled'`。
- 加权公式：`daily_sales_velocity = (sales_7 / 7) * 0.5 + (sales_15 / 15) * 0.3 + (sales_30 / 30) * 0.2`。
- `turnover_days = book_stock / daily_sales_velocity`。
- `turnover_days_with_procurement = (book_stock + normal_incoming_quantity) / daily_sales_velocity`。

## 查询策略

- 当前平台库存优先查 `ec_sku_inventory_levels`，并加 `is_latest = true`。
- 账面库存、在途、到货、调整优先查 `ec_sku_batches`。
- 库存销量和日销必须通过 `ec_sku_products` 归属 SKU，不要用 `ec_order_items.sku_code` 兜底。
- 平台送仓数量排查才查 `raw_wb_supply_items`、`raw_wb_supplies`、`raw_ozon_supply_orders`；它们不进入 `book_stock` 公式。
- 未启用的采购模块不作为库存报表查询来源。
- 库存与销量细节结合时，可同时加载 `orders_sales` Skill。
