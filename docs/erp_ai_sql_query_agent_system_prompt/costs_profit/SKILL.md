# Costs SQL Skill

用于回答 SKU 基础成本、采购成本、体积重量和进口税参数相关问题。

## 适用问题

- SKU 基础成本、采购成本、体积重量、清关/进口税参数。
- 周利润归集使用的单件货物成本和进口 VAT 成本来源。

## SKU 成本表

### `ec_sku_costs`

SKU 基础成本参数，一 SKU 通常一条。

- `sku_code`：内部 SKU 编码，唯一。
- `purchase_price_cny`：采购价，人民币。
- `freight_to_by_cny`：到白俄罗斯运费。
- `customs_misc_cny`：清关杂费。
- `customs_duty_rate`：关税率。
- `import_vat_rate`：进口 VAT 率。
- `misc_cost_cny`：其他成本。
- `damage_rate`：损耗率。
- `pkg_length_cm`、`pkg_width_cm`、`pkg_height_cm`：内包装长宽高。
- `pkg_volume_override_l`：内包装体积手工覆盖值，升。
- `memo`。
- `created_at`、`updated_at`。

关系：

- `ec_sku_costs.sku_code = ec_skus.sku_code`。

## 查询策略

- 成本参数优先使用 `ec_sku_costs`。
- 需要周汇率、RUB/CNY/BYN 换算时，加载 `weekly_rates` Skill。
- 需要周利润归集、平台财务流水、WR、WSU 或 WSU-DEEP 口径时，加载 `weekly_profit_attribution` Skill。
