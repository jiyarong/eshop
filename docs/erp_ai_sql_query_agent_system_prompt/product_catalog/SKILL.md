# Product Catalog SQL Skill

用于回答商品、SPU、SKU、店铺、类目、平台商品绑定、负责人概览、当前经营状态相关问题。职责人员绑定明细优先结合 `responsible_user_assignments` Skill；用户角色和当前用户权限判断结合 `user_roles_permissions` Skill。

## 适用问题

- SKU / SPU 列表、筛选、SPU 启停状态、SKU 软删除状态。
- SKU 与平台商品绑定关系。
- 店铺列表、平台账号映射、店铺状态。
- SKU 类目、平台类目、主商品类目。
- SKU 当前营销等级、阶段、质量等级、负责人概览。
- SKU 开发人员、平台商品运营人员的详细绑定关系；复杂职责查询应加载 `responsible_user_assignments` Skill。
- 当前用户是否是开发人员或运营人员；应加载 `user_roles_permissions` Skill，通过 `user_roles -> roles` 和 `roles.code IN ('product_dev', 'operator')` 判断。

## 表字段

### `ec_stores`

内部店铺主表。

- `id`：内部店铺主键。
- `platform`：平台，常见 `wb`、`ozon`、`amazon`。
- `store_name`：店铺展示名。
- `company_type`：主体类型，常见 `general`、`small`。
- `registration_country`：注册国家，常见 `belarus`、`russia`。
- `is_active`：是否启用。
- `wb_raw_account_id`：WB 原始账号 ID，对应 `raw_wb_seller_accounts.id`。
- `ozon_raw_account_id`：Ozon 原始账号 ID，对应 `raw_ozon_seller_accounts.id`。
- `memo`：备注。
- `created_at`、`updated_at`：内部记录时间。
- 敏感字段：`wb_api_token`、`ozon_api_key`、`ozon_client_id`、`ozon_performance_client_id`、`ozon_performance_client_secret`，不要查询。

### `ec_master_skus`

内部 SPU / 主商品表。

- `id`：SPU 主键。
- `master_sku_code`：SPU 编码，唯一，通常大写。
- `product_name`：中文/内部商品名。
- `product_name_ru`：俄文商品名。
- `ec_category_id`：通用类目 ID。
- `is_active`：是否启用。
- `memo`：备注。
- `created_at`、`updated_at`。

关系：

- `ec_master_skus.ec_category_id = ec_categories.id`。
- 一个 SPU 可关联多个 SKU：`ec_skus.master_sku_id = ec_master_skus.id`。

### `ec_skus`

内部 SKU 主表。

- `id`：SKU 主键。
- `sku_code`：内部 SKU 编码，唯一，核心业务键。
- `master_sku_id`：所属 SPU。
- `sku_category_id`：内部 SKU 类目。
- `product_name`：内部商品名。
- `product_name_ru`：俄文商品名。
- `color`、`size`、`model`、`spec`：规格属性。
- `features`：特性说明。
- `weight_kg`、`volume_l`：重量和体积。
- `owner_name`：SKU 主表上的文本负责人字段；开发人员绑定以 `ec_sku_developer_assignments` 为准。
- `quality_grade`：质量等级。
- `deleted_at`：软删除时间；业务查询默认加 `deleted_at IS NULL`。
- `memo`、`created_at`、`updated_at`。

关系：

- `ec_skus.master_sku_id = ec_master_skus.id`。
- `ec_skus.sku_category_id = ec_sku_categories.id`。
- `sku_code` 连接 `ec_sku_products`、`ec_sku_batches`、`ec_sku_inventory_levels`、`ec_sku_costs`、`ec_sku_dimensions`、`ec_sku_platform_costs`、`ec_sku_predicted_costs`。

### `ec_sku_products`

内部 SKU 与平台商品硬绑定表。

- `id`：绑定主键。
- `sku_code`：内部 SKU 编码。
- `store_id`：内部店铺 ID。
- `platform`：平台，来自店铺平台。
- `product_id`：平台商品 ID。Ozon 通常为 `ozon_product_id`；WB 为 `nm_id`。
- `platform_sku_id`：平台 SKU ID。Ozon 订单归属使用该字段；WB 订单归属通常不使用该字段。
- `offer_id`：平台 offer / article，仅展示和排查，不参与订单统计归属。
- `product_name`：平台商品名快照。
- `created_at`、`updated_at`。

关系：

- `ec_sku_products.sku_code = ec_skus.sku_code`。
- `ec_sku_products.store_id = ec_stores.id`。
- 唯一约束：`store_id + product_id`。
- SKU 店铺绑定索引：`sku_code + store_id`。

### `ec_sku_product_operators`

平台商品运营负责人绑定；详细查询模板见 `responsible_user_assignments` Skill。

- `sku_product_id`：平台商品绑定 ID。
- `user_id`：用户 ID。
- `role`：当前仅使用 `operator`；不要用 `role = 'developer'` 查询开发人员。

关系：

- `ec_sku_product_operators.sku_product_id = ec_sku_products.id`。
- `ec_sku_product_operators.user_id = users.id`。
- 唯一约束：`sku_product_id + user_id`。

### `ec_sku_developer_assignments`

内部 SKU 开发负责人绑定；详细查询模板见 `responsible_user_assignments` Skill。

- `sku_code`：内部 SKU code。
- `user_id`：用户 ID。

关系：

- `ec_sku_developer_assignments.sku_code = ec_skus.sku_code`。
- `ec_sku_developer_assignments.user_id = users.id`。
- 唯一约束：`sku_code + user_id`。

### `ec_categories`

通用/平台类目树，常用于 SPU 类目。

- `id`、`parent_id`：类目树。
- `source`、`source_type`、`source_id`：来源平台和来源 ID。
- `origin_language`、`origin_name`：原始语言和原始名称。
- `name_cn`、`name_en`、`name_ru`：翻译名称。
- `synced_at`、`translated_at`、`translation_error`。

### `ec_sku_categories`

内部 SKU 类目树。

- `id`、`parent_id`：类目树。
- `code`：内部类目编码，唯一。
- `name`：类目名。
- `position`：排序。
- `is_active`：是否启用。
- `memo`。

### `ec_sku_marketing_states`

SKU 当前/历史经营状态。

- `sku_id`：内部 SKU ID。
- `grade`：营销等级，取值 `S`、`A`、`B`、`C`。
- `stage`：营销阶段，取值 `new`、`grw`、`mat`、`clr`。
- `effective_at`：生效时间。
- `ended_at`：结束时间；当前状态为 `ended_at IS NULL`。
- `changed_by_id`：变更人用户 ID。
- `note`：备注。

关系：

- `ec_sku_marketing_states.sku_id = ec_skus.id`。
- `ec_sku_marketing_states.changed_by_id = users.id`。

## 归属规则

- SKU 相关业务优先以 `ec_skus.sku_code` 为内部口径。
- 平台商品相关业务必须通过 `ec_sku_products` 识别平台商品与内部 SKU 的绑定。
- 开发人员是 SKU 级职责，使用 `ec_sku_developer_assignments.sku_code = ec_skus.sku_code`。
- 运营人员是平台商品级职责，使用 `ec_sku_product_operators.sku_product_id = ec_sku_products.id` 且 `role = 'operator'`。
- 不要从 `ec_sku_product_operators.role = 'developer'` 推导开发人员；旧口径已废弃。
- 订单销量类查询不能用 `ec_order_items.sku_code` 归属 SKU；应加载 `orders_sales` Skill。
- 查询店铺时不要读取任何平台 token、api key、client secret 字段。
