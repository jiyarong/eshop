# User Roles Permissions SQL Skill

用于回答用户角色、当前用户权限、业务身份判断、可分配人员候选范围相关问题。

## 适用问题

- 查询某个用户拥有哪些角色。
- 判断当前用户是否是开发人员或运营人员。
- 按角色筛选用户，例如 `product_dev`、`operator`。
- 查询 active 用户和角色列表。
- 需要将用户职责绑定与用户角色权限结合分析时。

## 核心口径

用户角色通过 `user_roles -> roles` 判断：

- `user_roles.user_id = users.id`
- `user_roles.role_id = roles.id`
- `roles.code` 是业务角色编码。

当前用户是否具备开发/运营身份，按是否存在对应 role code 判断：

- 开发人员：存在 `roles.code = 'product_dev'`。
- 运营人员：存在 `roles.code = 'operator'`。

注意：SQL 查询里只能按 `roles.code` 判断业务身份。Rails 里的 `User#can?` / `Role#permissions` 是应用层权限逻辑，不应在 SQL 里自行推导成字段。

## 表字段

### `users`

用户主表。

- `id`：用户 ID。
- `email`：邮箱。
- `name`：展示名；为空时通常用 `email` 展示。
- `active`：是否启用。
- `time_zone`：用户展示时区。
- `created_at`、`updated_at`。
- 登录审计字段：`sign_in_count`、`current_sign_in_at`、`last_sign_in_at`、`current_sign_in_ip`、`last_sign_in_ip`。

不要查询或展示：

- `encrypted_password`
- remember/reset token 相关字段
- API token、access token、加密凭据字段

### `roles`

角色主表。

- `id`：角色 ID。
- `code`：角色编码，唯一。
- `name`：角色展示名。
- `description`：角色说明。
- `position`：排序。
- `created_at`、`updated_at`。

常见 role code：

- `super_admin`：超级管理员。
- `manager`：经营负责人。
- `sku_manager`：SKU / 商品管理员。
- `purchaser`：采购员。
- `warehouse_staff`：仓库 / 库存人员。
- `finance`：财务。
- `operator`：运营人员。
- `auditor`：只读 / 审计。
- `product_dev`：产品开发人员；用于业务身份判断时按 `roles.code` 识别。

### `user_roles`

用户与角色的多对多绑定表。

- `id`：绑定主键。
- `user_id`：用户 ID。
- `role_id`：角色 ID。
- `created_at`、`updated_at`。

关系：

- `user_roles.user_id = users.id`。
- `user_roles.role_id = roles.id`。
- 唯一约束：`user_id + role_id`。

## 常见查询

查询用户角色：

```sql
SELECT
  u.id AS user_id,
  COALESCE(NULLIF(u.name, ''), u.email) AS user_name,
  u.email,
  u.active,
  string_agg(r.code, ', ' ORDER BY r.position, r.code) AS role_codes
FROM users u
LEFT JOIN user_roles ur
  ON ur.user_id = u.id
LEFT JOIN roles r
  ON r.id = ur.role_id
GROUP BY u.id, u.name, u.email, u.active
ORDER BY u.email;
```

判断当前用户是否是开发人员或运营人员：

```sql
SELECT
  u.id AS user_id,
  u.email,
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

筛选可作为 SKU 开发人员或平台商品运营人员的 active 用户：

```sql
SELECT DISTINCT
  u.id,
  COALESCE(NULLIF(u.name, ''), u.email) AS user_name,
  u.email,
  r.code AS role_code
FROM users u
JOIN user_roles ur
  ON ur.user_id = u.id
JOIN roles r
  ON r.id = ur.role_id
WHERE u.active = TRUE
  AND r.code IN ('product_dev', 'operator')
ORDER BY r.code, u.email;
```

查询某个用户通过运营绑定负责的平台商品：

```sql
SELECT
  u.id AS user_id,
  u.email,
  sp.id AS sku_product_id,
  sp.sku_code,
  st.store_name,
  sp.platform,
  sp.product_id
FROM users u
JOIN user_roles ur
  ON ur.user_id = u.id
JOIN roles r
  ON r.id = ur.role_id
JOIN ec_sku_product_operators spo
  ON spo.user_id = u.id
  AND spo.role = 'operator'
JOIN ec_sku_products sp
  ON sp.id = spo.sku_product_id
JOIN ec_stores st
  ON st.id = sp.store_id
WHERE u.id = :user_id
  AND r.code = 'operator';
```

查询某个用户通过开发绑定负责的 SKU：

```sql
SELECT
  u.id AS user_id,
  u.email,
  s.sku_code,
  s.product_name
FROM users u
JOIN user_roles ur
  ON ur.user_id = u.id
JOIN roles r
  ON r.id = ur.role_id
JOIN ec_sku_developer_assignments sda
  ON sda.user_id = u.id
JOIN ec_skus s
  ON s.sku_code = sda.sku_code
WHERE u.id = :user_id
  AND r.code = 'product_dev'
  AND s.deleted_at IS NULL;
```

## 查询注意事项

- 角色身份和职责绑定是两层概念：`roles.code` 判断用户身份，`ec_sku_developer_assignments` / `ec_sku_product_operators` 判断具体负责对象。
- 判断当前用户是否有开发或运营身份时，只需要查 `roles.code IN ('product_dev', 'operator')`。
- 查询当前用户负责哪些 SKU / 平台商品时，还必须 join 对应职责绑定表；不能只凭 role code 推断负责对象。
- `operator` role 表示运营身份；平台商品实际绑定仍以 `ec_sku_product_operators` 为准。
- `product_dev` role 表示开发身份；SKU 实际绑定仍以 `ec_sku_developer_assignments` 为准。
- 默认只展示 `users.active = TRUE` 的可用用户，除非用户明确要求历史/停用用户。
- 如需职责绑定明细，应加载 `responsible_user_assignments` Skill。
