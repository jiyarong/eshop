# Costs And Profit SQL Skill

用于回答 SKU 成本、平台成本参数、目标价、预测成本、批次费用分摊、平台财务流水、利润口径相关问题。

## 适用问题

- SKU 基础成本、采购成本、体积重量、清关/进口税参数。
- WB/Ozon 平台成本、佣金、履约费、退货费、目标价。
- 预测成本和生效区间。
- 批次费用分摊、国际运费、清关、认证、仓储、杂费。
- 平台财务流水和利润归集排查。

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
- `pkg_length_cm`、`pkg_width_cm`、`pkg_height_cm`：包装长宽高。
- `pkg_volume_override_l`：手工覆盖体积，升。
- `memo`。
- `created_at`、`updated_at`。

关系：

- `ec_sku_costs.sku_code = ec_skus.sku_code`。

### `ec_sku_platform_costs`

SKU 平台成本和目标价参数，唯一粒度为 `sku_code + platform + delivery_mode + company_type`。

- `sku_code`：内部 SKU 编码。
- `platform`：平台，`wb` 或 `ozon`。
- `delivery_mode`：履约方式，例如 `fbo`、`fbs`、`fbw`。
- `company_type`：主体类型，例如 `general`、`small`。
- `exchange_rate_rub_cny`：卢布兑人民币汇率。
- `commission_rate`：佣金率。
- `acquiring_rate`：收单费率。
- `ad_spend_rate`：广告花费率。
- `sales_tax_rate`：销售税率。
- `return_rate`：退货率。
- `storage_30d_cny`：30 天仓储成本。
- `fbo_delivery_cny`：FBO 配送成本，人民币。
- `target_price_rub`：目标价，卢布。
- `target_price_rf_rub`：俄罗斯目标价，Ozon 常用。
- `target_price_by_rub`：白俄罗斯目标价，Ozon 常用。
- `min_price_rub`：最低价。
- WB 字段：`wb_logistics_base_rub`、`logistics_coeff`、`wb_return_rate`、`wb_fixed_return_rate`。
- Ozon 字段：`ozon_fwd_base_rub`、`ozon_fwd_per_liter_rub`、`ozon_ret_base_rub`、`ozon_ret_per_liter_rub`、`ozon_warehouse_op_rub`、`ozon_fbs_delivery_rub`。
- `created_at`、`updated_at`。

关系：

- `ec_sku_platform_costs.sku_code = ec_skus.sku_code`。
- 与店铺口径组合时，通常通过 `ec_stores.platform` 和 `ec_stores.company_type` 匹配平台成本的 `platform`、`company_type`。

### `ec_sku_predicted_costs`

按时间区间维护的预测成本。

- `sku_code`：内部 SKU 编码。
- `cost_money`：预测成本金额。
- `cost_currency`：币种，默认 `CNY`。
- `effective_from`：生效开始日期。
- `effective_to`：生效结束日期，可为空。
- `note`。
- `created_at`、`updated_at`。

口径：

- 查询某日生效成本：`effective_from <= date` 且 `effective_to IS NULL OR effective_to >= date`。
- 多条匹配时通常按 `effective_from DESC, id DESC` 取最新。

## 费用分摊

### `ec_cost_allocations`

费用分摊单。

- `id`：分摊单 ID。
- `allocation_no`：分摊单号，唯一。
- `cost_type`：费用类型，`international_freight`、`customs`、`certification`、`warehouse`、`misc`。
- `allocation_method`：分摊方法，`manual`、`by_quantity`、`by_purchase_amount`。
- `status`：状态，`draft`、`locked`。
- `total_amount_cny`：总金额，人民币。
- `allocated_on`：分摊日期。
- `memo`。
- `created_at`、`updated_at`。

### `ec_cost_allocation_items`

费用分摊明细。

- `cost_allocation_id`：分摊单 ID。
- `sku_batch_id`：SKU 批次 ID。
- `amount_cny`：分摊金额，人民币。
- `memo`。
- `created_at`、`updated_at`。

关系与口径：

- `ec_cost_allocation_items.cost_allocation_id = ec_cost_allocations.id`。
- `ec_cost_allocation_items.sku_batch_id = ec_sku_batches.id`。
- 成本汇总通常只统计 `ec_cost_allocations.status = 'locked'`。
- 批次分摊成本可通过 `ec_sku_batches.sku_code` 汇总到 SKU。

## 汇率

### `ec_weekly_rates`

- `week_start`：周开始日期。
- `currency`：币种。
- `rate_to_cny`：兑人民币汇率。
- `created_at`、`updated_at`。

## 平台财务原始表

Ozon：

- `raw_ozon_finance_transactions`：财务流水，字段 `account_id`、`operation_id`、`operation_date`、`operation_type`、`operation_type_name`、`posting_number`、`order_number`、`amount`、`accruals_for_sale`、`sale_commission`、`delivery_charge`、`return_delivery_charge`、`items`、`services`、`currency_code`。
- `raw_ozon_accrual_by_day`：日维度 accrual，字段 `account_id`、`accrual_date`、`posting_number`、`ozon_sku_id`、`type_id`、`type_name`、`accrued_category`、`amount`、`currency_code`。
- `raw_ozon_finance_realizations`：结算报告，字段 `account_id`、`report_date`、`doc_date`、`doc_number`、`total_amount`、`rows`。

WB：

- `raw_wb_finance_details`：财务明细，字段 `account_id`、`rrdid`、`nm_id`、`order_dt`、`sale_dt`、`doc_type`、`seller_oper_name`、`quantity`、`retail_amount`、`for_pay`、`delivery_rub`、`penalty`、`paid_storage`、`deduction`、`commission_percent`、`srid`。
- `raw_wb_sales_reports`：销售报告头，字段 `account_id`、`wb_report_id`、`date_from`、`date_to`、`total_sales`、`total_returns`、`total_delivery`、`total_penalty`、`total_commission`、`net_payable`。
- `raw_wb_sales_report_items`：销售报告明细，字段 `sales_report_id`、`account_id`、`nm_id`、`srid`、`doc_type`、`quantity`、`retail_amount`、`ppvz_for_pay`、`delivery_rub`、`penalty`、`commission_percent`、`sale_dt`、`order_dt`。

## 查询策略

- 成本参数优先使用 `ec_sku_costs` 和 `ec_sku_platform_costs`。
- 批次实际成本要结合 `ec_sku_batches.purchase_unit_price_cny`、`ec_cost_allocation_items.amount_cny`。
- 查询利润归集时必须说明口径：订单口径、平台财务流水口径、费用分摊口径可能不同。
- Ozon 财务按 `posting_number`、`ozon_sku_id`、`operation_date` 排查。
- WB 财务按 `nm_id`、`srid`、`sale_dt`、`rrdid` 排查。
- 平台财务表关联内部 SKU 时，应先通过店铺账号定位 `ec_stores`，再通过 `ec_sku_products` 的 `product_id` / `platform_sku_id` 归属。
