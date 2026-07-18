# SKU Dimensions SQL Skill

用于回答 SKU 包装尺寸、内外箱重量、外箱装件数和体积估算相关问题。

## 适用问题

- SKU 内径 / 外径长宽高。
- 内箱重量、外箱重量、外箱可装件数 pcs。
- 单件体积、内径体积、外径体积、库存体积估算。
- 需要把尺寸信息和 SKU 主数据、库存、成本或利润指标组合展示。

## 主要表

### `ec_sku_dimensions`

SKU 尺寸和装箱参数表，一 SKU 最多一条。

- `sku_code`：内部 SKU 编码，唯一，对应 `ec_skus.sku_code`。
- `inner_length_cm`、`inner_width_cm`、`inner_height_cm`：内径长宽高，单位 cm。
- `outer_length_cm`、`outer_width_cm`、`outer_height_cm`：外径长宽高，单位 cm。
- `inner_box_weight_kg`：内箱重量，单位 kg。
- `outer_box_weight_kg`：外箱重量，单位 kg。
- `outer_box_pcs`：一个外箱可装多少件。
- `created_at`、`updated_at`。

关系：

- `ec_sku_dimensions.sku_code = ec_skus.sku_code`。

### `ec_sku_costs`

成本表仍保留历史/手工体积覆盖字段：

- `pkg_volume_override_l`：手工直填升量，单位 L。仅在需要兼容旧成本体积计算或排查旧数据时使用。

关系：

- `ec_sku_costs.sku_code = ec_skus.sku_code`。

## 体积计算口径

- 内径体积 L：`inner_length_cm * inner_width_cm * inner_height_cm / 1000`。
- 外径体积 L：`outer_length_cm * outer_width_cm * outer_height_cm / 1000`。
- 如果任一长宽高为空，该体积不可直接计算。
- 旧成本对象中的 `pkg_volume_l` 兼容口径：优先使用内径体积；如果内径三边缺失且 `ec_sku_costs.pkg_volume_override_l > 0`，才使用手工直填升量。
- 库存体积估算默认使用单件内径体积，除非用户明确要求外箱体积或外箱维度。

## 查询策略

- 查询尺寸时优先从 `ec_sku_dimensions` 读取，不要再从 `ec_sku_costs` 查长宽高。
- 只需要 SKU 名称或状态时，加载 `product_catalog` Skill。
- 需要库存数量再估算体积时，加载 `inventory_procurement` Skill，并用 `ec_sku_dimensions` 的内径体积参与估算。
- 需要利润、成本或 ROI 且涉及单件体积时，同时加载 `costs_profit` 和 `weekly_profit_attribution` Skill。

## 常用 SQL 片段

内径 / 外径体积：

```sql
SELECT
  s.sku_code,
  s.product_name,
  d.inner_length_cm,
  d.inner_width_cm,
  d.inner_height_cm,
  CASE
    WHEN d.inner_length_cm IS NOT NULL
     AND d.inner_width_cm IS NOT NULL
     AND d.inner_height_cm IS NOT NULL
    THEN d.inner_length_cm * d.inner_width_cm * d.inner_height_cm / 1000.0
  END AS inner_volume_l,
  d.outer_length_cm,
  d.outer_width_cm,
  d.outer_height_cm,
  CASE
    WHEN d.outer_length_cm IS NOT NULL
     AND d.outer_width_cm IS NOT NULL
     AND d.outer_height_cm IS NOT NULL
    THEN d.outer_length_cm * d.outer_width_cm * d.outer_height_cm / 1000.0
  END AS outer_volume_l,
  d.inner_box_weight_kg,
  d.outer_box_weight_kg,
  d.outer_box_pcs
FROM ec_skus s
LEFT JOIN ec_sku_dimensions d
  ON d.sku_code = s.sku_code
WHERE s.deleted_at IS NULL;
```

兼容旧 `pkg_volume_l` 口径：

```sql
COALESCE(
  CASE
    WHEN d.inner_length_cm IS NOT NULL
     AND d.inner_width_cm IS NOT NULL
     AND d.inner_height_cm IS NOT NULL
    THEN d.inner_length_cm * d.inner_width_cm * d.inner_height_cm / 1000.0
  END,
  NULLIF(c.pkg_volume_override_l, 0)
) AS pkg_volume_l
```
