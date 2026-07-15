# Ozon Localization SQL Skill

用于回答 Ozon 发货集群、目的集群、跨集群销售、本地化销售占比、SKU 本地化率相关问题。该 Skill 只描述业务表、字段关系和统计口径，不涉及具体应用接口。

## 适用问题

- Ozon 销量从哪些发货集群流向哪些目的集群。
- Ozon 本地销售和跨集群销售占比。
- 哪些 SKU 本地化率高或低。
- 某个 Ozon 店铺、某个 SKU、某种履约方式的本地化销售表现。
- FBO / FBS 在集群流向或本地化率上的差异。

## 数据来源

本地化销售分析优先使用标准化业务表，不直接查 Ozon 原始 posting 表：

### `ec_order_items`

订单明细和销量数量来源。

- `id`：订单明细 ID。
- `order_id`：订单头 ID。
- `fulfillment_id`：履约记录 ID。
- `store_id`：内部店铺 ID。
- `platform`：平台；本 Skill 固定过滤 `ozon`。
- `platform_sku_id`：Ozon SKU ID，用于关联 `ec_sku_products.platform_sku_id`。
- `offer_id`：平台 offer，仅展示和排查，不用于销量归属。
- `product_name_source`：订单里的平台商品名。
- `quantity`：销量数量。
- `unit_price`、`payout`、`commission_amount`、`discount_amount`：金额字段，非本地化核心指标。
- `currency_code`：币种。
- `sku_code`：冗余展示字段，不用于归属内部 SKU。

### `ec_orders`

订单时间、状态和订单去重来源。

- `id`：订单 ID。
- `store_id`：内部店铺 ID。
- `platform`：平台。
- `order_status`：订单状态。
- `ordered_at`：下单时间，本地化销售日期筛选优先使用。
- `external_order_id`、`external_order_number`：平台订单标识。
- `source_status`、`source_substatus`：平台原始状态。
- `synced_at`：同步时间。

### `ec_order_fulfillments`

Ozon 集群和履约方式来源。

- `id`：履约 ID。
- `order_id`：订单 ID。
- `store_id`：店铺 ID。
- `platform`：平台。
- `fulfillment_type`：履约方式，常见 `fbo`、`fbs`。
- `cluster_from`：发货集群。
- `cluster_to`：目的集群。
- `warehouse_name`、`warehouse_external_id`：仓库信息。
- `delivery_method_name`：配送方式名。
- `status`、`source_status`、`source_substatus`：履约状态。
- `shipped_at`、`delivered_at`、`cancelled_at`：履约时间。

### `ec_sku_products`

Ozon 平台商品绑定和内部 SKU 归属来源。

- `id`：绑定 ID。
- `sku_code`：内部 SKU 编码。
- `store_id`：内部店铺 ID。
- `platform`：平台；本 Skill 使用 `ozon`。
- `product_id`：Ozon 商品 ID。
- `platform_sku_id`：Ozon SKU ID，订单明细归属 SKU 的关键字段。
- `offer_id`：Ozon offer，仅展示和排查。
- `product_name`：平台商品名。

### `ec_skus`

内部 SKU 基础资料。

- `sku_code`：内部 SKU 编码。
- `product_name`：内部商品名。
- `product_name_ru`：俄文商品名。
- `is_active`：是否启用。
- `deleted_at`：软删除时间；业务查询默认排除软删除。

## 表关系

基础关联：

- `ec_order_items.order_id = ec_orders.id`
- `ec_order_items.fulfillment_id = ec_order_fulfillments.id`
- `ec_order_items.store_id = ec_stores.id`
- `ec_sku_products.sku_code = ec_skus.sku_code`

Ozon 订单明细归属内部 SKU 的关联条件：

- `ec_sku_products.store_id = ec_order_items.store_id`
- `ec_sku_products.platform = ec_order_items.platform`
- `ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id`

不要用 `ec_order_items.sku_code` 归属 SKU。不要用 `offer_id` 归属销量。

## 基础过滤

- 只看 Ozon：`ec_order_items.platform = 'ozon'`。
- 日期范围：使用用户时区计算日期边界，过滤 `ec_orders.ordered_at`。
- 必须有集群数据：排除 `ec_order_fulfillments.cluster_from IS NULL` 和 `ec_order_fulfillments.cluster_to IS NULL`。
- 店铺过滤：用 `ec_order_items.store_id` 或 `ec_orders.store_id`，两者应一致。
- SKU 过滤：用 `ec_sku_products.sku_code`。
- 履约过滤：用 `ec_order_fulfillments.fulfillment_type`，常见 `fbo`、`fbs`。
- 订单状态过滤：用 `ec_orders.order_status`；不指定时可包含全部状态，指定时需明确口径。
- 模糊搜索可匹配：
  - `ec_sku_products.sku_code`
  - `ec_skus.product_name`
  - `ec_sku_products.product_name`
  - `ec_order_items.product_name_source`

## 指标口径

- 总销量：`SUM(ec_order_items.quantity)`。
- 本地销量：发货集群等于目的集群时的销量，即 `cluster_from = cluster_to`。
- 跨集群销量：总销量减本地销量，或 `cluster_from <> cluster_to` 的销量。
- 本地化率：`本地销量 / 总销量`。总销量为 0 时返回空值。
- 订单数：`COUNT(DISTINCT ec_orders.id)`。
- SKU 数：`COUNT(DISTINCT ec_sku_products.sku_code)`。
- 本地销售定义：`ec_order_fulfillments.cluster_from = ec_order_fulfillments.cluster_to`。
- 跨集群销售定义：`ec_order_fulfillments.cluster_from <> ec_order_fulfillments.cluster_to`。

## 集群分布矩阵

用于回答“从哪个集群发到哪个集群”“跨集群流向如何分布”等问题。

分组字段：

- 行维度：`ec_order_fulfillments.cluster_from`
- 列维度：`ec_order_fulfillments.cluster_to`

核心字段：

- `cluster_from`：发货集群。
- `cluster_to`：目的集群。
- `quantity`：该流向销量。
- `local`：`cluster_from = cluster_to`。

汇总口径：

- 行汇总：按 `cluster_from` 汇总销量，代表各发货集群贡献。
- 列汇总：按 `cluster_to` 汇总销量，代表各目的集群需求。
- 默认排序通常按销量降序。

## SKU 本地化列表

用于回答“哪些 SKU 本地化率低”“哪些 SKU 跨集群销量高”等问题。

分组字段：

- `ec_sku_products.sku_code`

核心字段：

- `sku_code`：内部 SKU 编码。
- `product_name`：商品名，优先 `ec_skus.product_name`，其次 `ec_sku_products.product_name`，再其次 `ec_order_items.product_name_source`。
- `total_quantity`：总销量。
- `local_quantity`：本地销量。
- `non_local_quantity`：跨集群销量。
- `localization_rate`：本地化率。
- `order_count`：去重订单数。
- `fulfillment_types`：涉及的履约类型集合。
- `local_cluster_count`：本地销售涉及的发货集群数量。
- `non_local_cluster_count`：跨集群销售涉及的目的集群数量。

常见排序：

- 总销量降序，用于找高销量 SKU。
- 本地化率升序或跨集群销量降序，用于找本地化较差或跨区履约压力大的 SKU。
- 本地化率降序，用于找本地销售表现好的 SKU。
- SKU 编码升序，用于稳定分页。

## 查询策略

- 用户问“哪些 Ozon SKU 本地化差/跨区销售多/本地化率低”，使用 SKU 本地化列表口径。
- 用户问“从哪些集群发到哪些集群/跨集群矩阵/地区流向”，使用集群分布矩阵口径。
- 用户问某个店铺或某个 SKU，优先加 `store_id` 或 `sku_code` 过滤。
- 用户问 FBO/FBS 差异，使用 `fulfillment_type` 过滤或按履约类型分组。
- 用户问“本地化率”时，必须同时返回或说明分子、本地销量、分母、总销量。
- 当结果缺少数据时，优先检查 `ec_order_fulfillments.cluster_from`、`cluster_to` 是否为空，以及 Ozon SKU 是否有 `ec_sku_products.platform_sku_id` 绑定。
