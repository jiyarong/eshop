# Responsible User Assignments SQL Skill

用于回答 SKU 开发人员、平台商品运营人员、用户负责范围、职责绑定明细相关问题。

## 适用问题

- 查询某个 SKU 的开发人员。
- 查询某个店铺平台商品的运营人员。
- 查询某个用户负责哪些内部 SKU 或平台商品。
- 按开发人员、运营人员筛选 SKU / 平台商品。
- 汇总每个用户负责的 SKU 数量、平台商品数量、店铺数量。
- 判断当前用户是否具备开发人员或运营人员身份。

## 核心口径

职责绑定分为两个不同层级：

- 开发人员：绑定内部 SKU，使用 `ec_sku_developer_assignments`。
- 运营人员：绑定平台商品，使用 `ec_sku_product_operators`。

不要把开发人员从 `ec_sku_product_operators.role = 'developer'` 推导出来；该旧口径已废弃。`ec_sku_product_operators` 当前只表达平台商品运营人员。

用户是否具备开发/运营身份，通过 `user_roles -> roles` 的 role code 判断；详细角色字段和权限口径见 `user_roles_permissions` Skill。

- 开发身份：当前用户存在 `roles.code = 'product_dev'`。
- 运营身份：当前用户存在 `roles.code = 'operator'`。
- 具体负责哪些 SKU / 平台商品，仍必须查询职责绑定表，不能只凭 role code 推断。

## 表字段

### `ec_sku_developer_assignments`

内部 SKU 开发负责人绑定表。

- `id`：绑定主键。
- `sku_code`：内部 SKU code，对应 `ec_skus.sku_code`。
- `user_id`：用户 ID，对应 `users.id`。
- `created_at`、`updated_at`。

关系：

- `ec_sku_developer_assignments.sku_code = ec_skus.sku_code`。
- `ec_sku_developer_assignments.user_id = users.id`。
- 唯一约束：`sku_code + user_id`，同一用户不能重复绑定同一个 SKU。

### `ec_sku_product_operators`

平台商品运营负责人绑定表。

- `id`：绑定主键。
- `sku_product_id`：平台商品绑定 ID，对应 `ec_sku_products.id`。
- `user_id`：用户 ID，对应 `users.id`。
- `role`：当前仅使用 `operator`。
- `created_at`、`updated_at`。

关系：

- `ec_sku_product_operators.sku_product_id = ec_sku_products.id`。
- `ec_sku_product_operators.user_id = users.id`。
- `ec_sku_products.sku_code = ec_skus.sku_code`。
- `ec_sku_products.store_id = ec_stores.id`。
- 唯一约束：`sku_product_id + user_id`，同一用户不能重复绑定同一个平台商品。

### `users`

用户表只查询职责展示所需字段。

- `id`：用户 ID。
- `email`：邮箱。
- `name`：展示名；为空时通常用 `email` 展示。
- `active`：是否启用。

不要查询密码、token、加密凭据类字段。

### `user_roles` / `roles`

用户角色绑定用于判断当前用户的业务身份。

关系：

- `user_roles.user_id = users.id`。
- `user_roles.role_id = roles.id`。
- `roles.code` 是角色编码。

职责相关常用 role code：

- `product_dev`：产品开发人员身份。
- `operator`：运营人员身份。

当前用户是否是开发/运营身份：

```sql
SELECT
  u.id AS user_id,
  EXISTS (
    SELECT 1
    FROM user_roles ur
    JOIN roles r
      ON r.id = ur.role_id
    WHERE ur.user_id = u.id
      AND r.code = 'product_dev'
  ) AS is_product_dev,
  EXISTS (
    SELECT 1
    FROM user_roles ur
    JOIN roles r
      ON r.id = ur.role_id
    WHERE ur.user_id = u.id
      AND r.code = 'operator'
  ) AS is_operator
FROM users u
WHERE u.id = :current_user_id;
```

## 常见关联

查询 SKU 开发人员：

```sql
SELECT
  s.sku_code,
  s.product_name,
  u.id AS developer_id,
  COALESCE(NULLIF(u.name, ''), u.email) AS developer_name
FROM ec_skus s
LEFT JOIN ec_sku_developer_assignments sda
  ON sda.sku_code = s.sku_code
LEFT JOIN users u
  ON u.id = sda.user_id
WHERE s.deleted_at IS NULL;
```

查询平台商品运营人员：

```sql
SELECT
  sp.id AS sku_product_id,
  sp.sku_code,
  st.store_name,
  sp.platform,
  sp.product_id,
  sp.offer_id,
  u.id AS operator_id,
  COALESCE(NULLIF(u.name, ''), u.email) AS operator_name
FROM ec_sku_products sp
JOIN ec_stores st
  ON st.id = sp.store_id
LEFT JOIN ec_sku_product_operators spo
  ON spo.sku_product_id = sp.id
  AND spo.role = 'operator'
LEFT JOIN users u
  ON u.id = spo.user_id;
```

同时查询 SKU 的开发人员和各平台商品运营人员：

```sql
SELECT
  s.sku_code,
  s.product_name,
  string_agg(DISTINCT COALESCE(NULLIF(dev.name, ''), dev.email), ', ') AS developers,
  sp.id AS sku_product_id,
  st.store_name,
  sp.platform,
  sp.product_id,
  string_agg(DISTINCT COALESCE(NULLIF(op.name, ''), op.email), ', ') AS operators
FROM ec_skus s
LEFT JOIN ec_sku_developer_assignments sda
  ON sda.sku_code = s.sku_code
LEFT JOIN users dev
  ON dev.id = sda.user_id
LEFT JOIN ec_sku_products sp
  ON sp.sku_code = s.sku_code
LEFT JOIN ec_stores st
  ON st.id = sp.store_id
LEFT JOIN ec_sku_product_operators spo
  ON spo.sku_product_id = sp.id
  AND spo.role = 'operator'
LEFT JOIN users op
  ON op.id = spo.user_id
WHERE s.deleted_at IS NULL
GROUP BY
  s.sku_code,
  s.product_name,
  sp.id,
  st.store_name,
  sp.platform,
  sp.product_id
ORDER BY s.sku_code, st.store_name, sp.product_id;
```

## 查询注意事项

- 开发人员是 SKU 级职责；同一 SKU 绑定到多个店铺或多个平台商品时，开发人员相同。
- 运营人员是平台商品级职责；同一 SKU 下不同店铺、不同平台商品可以有不同运营人员。
- 查询“某人负责的 SKU”时要区分开发负责和运营负责：
  - 开发负责：从 `ec_sku_developer_assignments` 直接到 `ec_skus`。
  - 运营负责：从 `ec_sku_product_operators` 到 `ec_sku_products`，再按 `sku_code` 汇总 SKU。
- 对 `ec_sku_product_operators` 查询时默认加 `role = 'operator'`，避免历史数据或兼容字段影响结果。
- SKU 查询默认排除软删除：`ec_skus.deleted_at IS NULL`。
- 如需订单、销量、库存口径，应再加载对应 SQL Skill，不要在职责绑定 Skill 内重新定义统计归属规则。
