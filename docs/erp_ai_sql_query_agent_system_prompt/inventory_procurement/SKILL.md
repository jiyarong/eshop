# Inventory Procurement SQL Skill

用于回答库存列表、库存搜索、账面库存、FBS 库存、平台在库、平台在途、周转天数、补货和库存详情页相关问题。

## 使用原则

普通库存问题优先按库存报表列表页 `/reports/inventory` 的口径回答。目标是像网页列表一样快，不要为一个列表问题直接展开详情页所有店铺、退货、送仓、仓库 JSON 明细。

- 用户问“库存列表”“查某个 SKU 库存”“库存小于/大于多少”“周转天数筛选”时，走列表口径。
- 用户明确问某个 SKU 的店铺拆分、销售/退货分布、平台仓库明细、批次明细时，才走详情页口径。
- 用户只说“库存”“可用库存”“还有多少”且口径不明确时，先问清楚：账面库存、报表 FBS 库存、平台在库、平台在途，还是平台快照里的 FBS。
- 用户只说“补货”“需要补多少”“补到多少天周转”时，先问清楚是补平台库 FBO/FBW，还是补账面库存/报表 FBS 库存。
- 一次最多返回 500 个对象；列表查询必须分页或显式 `LIMIT`。

## 最重要的库存口径

### 账面库存

账面库存是内部总账口径，字段名通常是 `book_stock` 或页面文案“账面可用库存”。

公式：

- `book_stock = received_quantity - sales_quantity + return_quantity`
- `received_quantity` 来自已到货/已关闭批次的 `received_quantity`。
- `sales_quantity` 来自订单归属后的销量，排除取消订单，退货订单按 0 销量。
- `return_quantity` 来自 WB/Ozon 退货原始表归属后的数量。

### 报表 FBS 库存

库存报表列表和详情顶部里的“FBS库存”不是平台快照里的 `fulfillment_type = 'fbs'`。

报表 FBS 库存是页面字段 `available_stock` / `overseas_available_stock`，表示扣掉平台仓和平台在途后，内部还可用于 FBS/海外发货的库存。

公式：

- `report_fbs_stock = available_stock = book_stock - platform_stock - platform_inbound_stock`
- 这里的 `platform_stock` 是平台仓现货：`fulfillment_type IN ('fbo','fbw')`。
- 这里的 `platform_inbound_stock` 是平台在途/入库：`fulfillment_type = 'inbound'`。
- 不要把报表 FBS 库存写成 `ec_sku_inventory_levels.fulfillment_type = 'fbs'` 的数量。

### 平台快照 FBS

`ec_sku_inventory_levels.fulfillment_type = 'fbs'` 是平台库存快照里的 FBS 类型库存，只在用户明确问“平台 FBS 快照”“平台侧 FBS 库存”“卖家自仓可发快照”时使用。

当用户只说“FBS库存”，在库存报表上下文中默认指报表 FBS 库存，即 `available_stock`。如果上下文不清楚，必须追问。

## 库存列表页口径

库存列表入口：`GET /reports/inventory`。

列表先确定 SKU 范围，再只对当前页 SKU 计算展示行：

- 基础范围：`ec_skus`，按 `sku_code` 排序。
- SKU 搜索：`LOWER(ec_skus.sku_code) LIKE '%keyword%'`。
- 分页：每页 10 条；SQL 查询最多返回 500 条。
- 如果没有周转筛选，不要为了列表页先扫描所有 SKU 的订单和退货明细。

列表展示字段：

- `sku_code`：`ec_skus.sku_code`。
- `product_name`、`product_name_ru`：`ec_skus`。
- `marketing_grade`、`marketing_stage`：当前营销状态，仅用于展示。
- `incoming_quantity`：`ec_sku_batches.status IN ('draft','ordered','in_transit') AND batch_type = 'normal'` 的 `purchased_quantity`。
- `book_stock`：账面库存。
- `platform_inbound_stock`：最新平台库存中 `fulfillment_type = 'inbound'` 的 `quantity`。
- `platform_stock`：最新平台库存中 `fulfillment_type IN ('fbo','fbw')` 的 `quantity`。
- `available_stock`：报表 FBS 库存，公式为 `book_stock - platform_stock - platform_inbound_stock`。
- `daily_sales_velocity`：最近 7/15/30 天加权日销。
- `turnover_days`：`book_stock / daily_sales_velocity`。
- `turnover_days_with_procurement`：`(book_stock + incoming_quantity) / daily_sales_velocity`。
- 内包装尺寸和体积来自 `ec_sku_dimensions`；需要尺寸字段或体积计算时加载 `sku_dimensions` Skill。

## 列表快速查询策略

普通列表类问题优先使用聚合子查询，不要逐 SKU 查询详情。

推荐顺序：

1. 先确定候选 SKU：按 SKU 搜索、排序、分页或限制数量。
2. 对候选 SKU 聚合批次、平台库存、订单销量、退货数量。
3. 计算列表字段并返回。
4. 只有用户明确要求详情时，再查店铺拆分、平台仓库 JSON、送仓明细。

列表查询需要的聚合：

- 批次到货：`ec_sku_batches`，`status IN ('received','closed')`，按 `sku_code` 汇总 `received_quantity`。
- 在途采购：`ec_sku_batches`，`status IN ('draft','ordered','in_transit') AND batch_type = 'normal'`，按 `sku_code` 汇总 `purchased_quantity`。
- 平台仓现货：`ec_sku_inventory_levels`，`is_latest = true AND fulfillment_type IN ('fbo','fbw')`。
- 平台在途：`ec_sku_inventory_levels`，`is_latest = true AND fulfillment_type = 'inbound'`。
- 订单销量：`ec_orders` + `ec_order_items` + `ec_sku_products`，通过 SKU 绑定归属，排除取消订单，退货订单按 0。
- 退货数量：WB/Ozon 退货原始表必须通过店铺账号 + SKU 绑定归属；不要只用 `offer_id`、`ozon_sku`、`nm_id` 全局匹配。
- ⚠️ Ozon 退货聚合时，必须额外排除关联已取消订单的记录；否则会把已取消订单的退货重复算进账面库存。详见“退货归属 -> Ozon”。

列表查询不需要：

- `raw_wb_supply_items`、`raw_wb_supplies`、`raw_ozon_supply_orders`，除非用户问平台送仓/供货数量。
- `warehouse_breakdown` JSON，除非用户问平台仓库拆分。
- 店铺级订单状态分布，除非用户问库存详情页销售分布。
- 平台快照 `fulfillment_type = 'fbs'`，除非用户明确问平台侧 FBS 快照。

## 周转天数筛选

库存列表支持四个筛选参数：

- `turnover_days_min`：周转天数 `>=`。
- `turnover_days_max`：周转天数 `<=`。
- `procurement_turnover_days_min`：周转天数(含采购) `>=`。
- `procurement_turnover_days_max`：周转天数(含采购) `<=`。

周转指标：

- `daily_sales_velocity = (sales_7 / 7) * 0.5 + (sales_15 / 15) * 0.3 + (sales_30 / 30) * 0.2`。
- `turnover_days = book_stock / daily_sales_velocity`。
- `turnover_days_with_procurement = (book_stock + incoming_quantity) / daily_sales_velocity`。
- 日销小于等于 0 时，两个周转指标为空。

筛选匹配：

- 多个上下限条件之间是 AND。
- 某个上下限为空时，该方向不限制。
- 用户筛选某个周转指标时，如果该指标为空，则该 SKU 不匹配。
- 负数周转天数默认不匹配非负下限；只有用户明确给出负数下限时，才允许负数参与匹配。

## SKU 与订单归属

库存销量和日销必须通过 `ec_sku_products` 归属 SKU，不要用 `ec_order_items.sku_code` 兜底。

订单归属条件：

- `ec_sku_products.store_id = ec_order_items.store_id`。
- `ec_sku_products.platform = ec_order_items.platform`。
- Ozon：`ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id`。
- WB：`ec_sku_products.product_id = ec_order_items.platform_sku_id`。
- 排除取消订单：`ec_orders.order_status != 'cancelled'`。
- `returned` 订单销量按 0。

## 退货归属

退货只用于计算 `return_quantity` 和账面库存。普通列表查询只需要按 SKU 汇总，不需要返回退货明细。

WB：

- 表：`raw_wb_goods_returns`。
- 通过 `raw_wb_goods_returns.account_id = ec_stores.wb_raw_account_id` 找 WB 店铺。
- 通过 `ec_sku_products.store_id = ec_stores.id AND ec_sku_products.platform = 'wb' AND raw_wb_goods_returns.nm_id::text = ec_sku_products.product_id` 归属 SKU。
- 每行按 1 件退货计数。
- 不要只按 `nm_id` 全局匹配；同一个内部 SKU 可能绑定多个 WB 店铺和多个 `product_id`。

Ozon：

- ⚠️ Ozon 退货和 WB 不同，聚合时必须排除关联已取消订单的记录。这是库存报表后台口径的一部分，不是可选优化。
- 表：`raw_ozon_returns`。
- 通过 `raw_ozon_returns.account_id = ec_stores.ozon_raw_account_id` 找 Ozon 店铺。
- 通过 `ec_sku_products.store_id = ec_stores.id AND ec_sku_products.platform = 'ozon'` 限定同一店铺，再用 `raw_ozon_returns.offer_id = ec_sku_products.offer_id OR raw_ozon_returns.ozon_sku::text = ec_sku_products.platform_sku_id` 归属 SKU。
- `quantity` 为空时按 1。
- 如果能匹配到已取消订单，则该退货不计入库存退货数量。
- 不要只按 `offer_id` 或 `ozon_sku` 全局匹配；Ozon 的 `offer_id` 可能在多个账号/店铺重复，必须先限定 `account_id -> ec_stores -> ec_sku_products.store_id`。
- 取消单排除条件要和后台一致：同一 Ozon 店铺下存在 `ec_orders.order_status = 'cancelled'`，且 `external_order_number` 等于 `posting_number` 或 `order_number`，或 `external_order_id = raw_ozon_returns.order_id::text`，则该退货不计入。

## 补货问题

补货必须先确认目标：

- 补平台库：目标是平台仓现货，WB 看 FBW，Ozon 看 FBO；关注 `platform_stock`、`platform_inbound_stock` 和平台仓周转。
- 补账面库存或报表 FBS 库存：目标是内部可用库存；关注 `book_stock`、`available_stock`、`incoming_quantity`、`turnover_days_with_procurement`。

两者是不同事件：

- 补平台库是把已有或将有库存送到平台仓。
- 补账面库存是内部库存总量不足，需要采购、到货或调整。

用户没有说清楚时，不要直接计算补货量。

## 详情页补充

只有用户明确要详情时，才使用这些更重的查询。

详情页入口：`GET /reports/inventory/:sku_code`，核心服务是 `Ec::InventoryPageDetailQuery`，基础汇总来自 `Ec::SkuInventoryOverview`。

详情页包含：

- 在途批次：`ec_sku_batches.status IN ('draft','ordered','in_transit')`。
- 账面批次：`ec_sku_batches.status IN ('received','closed')`。
- 销售分布：订单按店铺和状态桶聚合，状态桶是 `pending`、`processing`、`shipped -> shipping`、`delivered -> signed`。
- 退货分布：WB/Ozon 退货按店铺聚合。
- 平台库存店铺拆分：`ec_sku_inventory_levels.is_latest = true`，按平台、店铺、账号聚合 `fbo/fbw`、`inbound`、平台快照 `fbs`。
- FBO/FBW 仓库拆分：展开 `warehouse_breakdown` JSON。
- 平台送仓数量：只在排查送仓时查 `raw_wb_supply_items`、`raw_wb_supplies`、`raw_ozon_supply_orders`；它们不进入 `book_stock` 公式。

## 主要表

- `ec_skus`：SKU 主表，列表基础范围。
- `ec_sku_costs`：成本参数。
- `ec_sku_dimensions`：内外包装尺寸、内外箱重量、外箱装件数；库存列表体积估算默认使用内径体积。
- `ec_sku_batches`：账面到货、调整、在途采购。
- `ec_sku_inventory_levels`：平台库存快照，当前库存必须加 `is_latest = true`。
- `ec_orders`、`ec_order_items`、`ec_sku_products`：销量、日销、周转。
- `raw_wb_goods_returns`、`raw_ozon_returns`：退货数量。
- `raw_wb_supply_items`、`raw_wb_supplies`、`raw_ozon_supply_orders`：仅用于送仓数量排查，不是列表默认来源。
