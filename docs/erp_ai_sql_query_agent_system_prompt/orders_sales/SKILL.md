# Orders And Sales SQL Skill

用于回答订单、销量、退款/退货销量、履约、地区、店铺销售表现、SKU 销量归属相关问题。

## 适用问题

- 按 SKU、SPU、店铺、平台、日期统计销量。
- 查询订单状态、履约状态、发货/送达时间。
- 对比 Ozon/WB 销量表现。
- 查询退货订单数量、净销量、订单金额、佣金、折扣、平台 payout。
- 按城市、地区、国家分析订单。

## 标准化订单表

### `ec_orders`

订单头表，一条记录代表一个平台订单或平台归集后的订单主体。

- `id`：内部订单 ID。
- `platform`：平台，`wb`、`ozon`、`amazon`。
- `store_id`：内部店铺 ID。
- `order_key`：内部唯一订单键，唯一粒度为 `platform + store_id + order_key`。
- `external_order_id`：平台订单 ID。
- `external_order_number`：平台订单号 / posting number 等展示编号。
- `order_status`：内部订单状态，常见 `pending`、`processing`、`shipped`、`delivered`、`cancelled`、`returned`、`unknown`。
- `source_status`、`source_substatus`：平台原始状态。
- `ordered_at`：下单时间，订单统计优先使用。
- `in_process_at`：进入处理时间。
- `completed_at`：完成时间。
- `cancelled_at`：取消时间。
- `buyer_country`、`buyer_region`、`buyer_city`：买家地区。
- `payment_method_source`：平台支付方式来源字段。
- `is_legal_entity`：是否法人买家。
- `source_payload`：原始归集 payload。
- `synced_at`：同步时间。
- `created_at`、`updated_at`：内部记录时间。

关系：

- `ec_orders.store_id = ec_stores.id`。
- `ec_order_items.order_id = ec_orders.id`。
- `ec_order_fulfillments.order_id = ec_orders.id`。
- `ec_order_source_links.order_id = ec_orders.id`。

### `ec_order_items`

订单明细表，一条记录代表订单中的一个平台商品明细。

- `id`：订单明细 ID。
- `order_id`：订单头 ID。
- `fulfillment_id`：履约记录 ID，可为空。
- `store_id`：内部店铺 ID。
- `platform`：平台。
- `external_item_id`：平台明细 ID。
- `platform_sku_id`：平台 SKU ID。Ozon 对应 Ozon SKU；WB 统计归属时这里存 WB `nm_id` 字符串。
- `offer_id`：平台 offer / article，仅展示和排查。
- `product_name_source`：平台商品名快照。
- `quantity`：数量，默认 1。
- `unit_price`：成交单价。
- `old_unit_price`：原价。
- `discount_amount`、`discount_percent`：折扣。
- `commission_amount`、`commission_percent`：佣金。
- `payout`：平台结算/应付金额字段。
- `currency_code`：币种。
- `sku_code`：冗余展示字段，不可用于统计归属。
- `item_payload`：原始明细 payload。
- `synced_at`、`created_at`、`updated_at`。

关系：

- `ec_order_items.order_id = ec_orders.id`。
- `ec_order_items.store_id = ec_stores.id`。
- `ec_order_items.fulfillment_id = ec_order_fulfillments.id`。

### `ec_order_fulfillments`

履约/包裹/发货表。

- `id`：履约 ID。
- `order_id`：订单 ID。
- `store_id`：店铺 ID。
- `platform`：平台。
- `fulfillment_key`：内部唯一履约键，唯一粒度为 `platform + store_id + fulfillment_key`。
- `external_fulfillment_id`：平台履约/包裹 ID。
- `fulfillment_type`：履约类型，常见 `fbo`、`fbs`、`fbw`、`unknown`。
- `status`：内部履约状态。
- `source_status`、`source_substatus`：平台原始状态。
- `delivery_method_name`：配送方式名。
- `delivery_type_source`：平台配送类型来源字段。
- `warehouse_name`、`warehouse_external_id`：仓库信息。
- `cluster_from`、`cluster_to`：Ozon 区域/集群字段，可用于本地化分析。
- `tracking_number`：物流单号。
- `shipped_at`、`delivered_at`、`cancelled_at`：履约时间。
- `raw_source_type`、`raw_source_id`：原始表来源。
- `synced_at`、`created_at`、`updated_at`。

### `ec_order_source_links`

标准化订单与原始记录的追踪关系。

- `order_id`：标准化订单 ID。
- `fulfillment_id`：标准化履约 ID，可为空。
- `item_id`：标准化明细 ID，可为空。
- `platform`：平台。
- `source_type`、`source_id`：原始表类型和主键。
- `source_key`：原始业务键。
- `source_role`：来源角色，默认 `primary`。
- `synced_at`。

## SKU 销量归属规则

订单、销量、库存销量等统计必须使用 `ec_sku_products` 归属内部 SKU，不能用 `ec_order_items.sku_code` 作为兜底。

归属条件：

- `ec_sku_products.store_id = ec_order_items.store_id`
- `ec_sku_products.platform = ec_order_items.platform`
- Ozon：`ec_order_items.platform = 'ozon'` 且 `ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id`
- WB：`ec_order_items.platform = 'wb'` 且 `ec_sku_products.product_id = ec_order_items.platform_sku_id`

不要使用 `offer_id` 参与订单归属，除非用户明确要求排查 offer 维度。

## 统计口径

- 销量：通常排除 `ec_orders.order_status = 'cancelled'`。
- 退货数量：当前报表里常按 `ec_orders.order_status = 'returned'` 的明细数量计入退货。
- 净销量：通常为非 returned 订单数量减 returned 订单数量，具体口径要向用户说明。
- 订单日期：优先使用 `ec_orders.ordered_at`。
- 店铺维度：`ec_order_items.store_id = ec_stores.id` 或 `ec_orders.store_id = ec_stores.id`，两者应一致。
- 平台维度：优先用 `ec_order_items.platform` 统计明细，订单头 `ec_orders.platform` 可用于过滤订单。
- 履约维度：通过 `ec_order_items.fulfillment_id` 关联 `ec_order_fulfillments.id`。

## 常见关联

- `ec_order_items.order_id = ec_orders.id`
- `ec_order_items.store_id = ec_stores.id`
- `ec_order_items.fulfillment_id = ec_order_fulfillments.id`
- `ec_order_fulfillments.order_id = ec_orders.id`
- `ec_sku_products.store_id = ec_order_items.store_id`
- `ec_sku_products.platform = ec_order_items.platform`
