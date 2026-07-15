# Weekly Profit Attribution SQL Skill

用于回答周利润归集、WR、WSU、WSU-DEEP、平台财务流水归因和未归集金额排查相关问题。

## 适用问题

- WR：单平台、单账号、按周的利润归集明细。
- WSU：跨账号、跨平台，按 `SKU + platform + shop` 汇总的周利润。
- WSU-DEEP：跨账号、跨平台，按 SKU 聚合并补充投产、周转和年化指标的深度周利润。
- 周利润的收入、广告、仓储、配送、货物成本、税、税后利润和未归集金额口径排查。

## 周期与汇率

口径：

- WR、WSU、WSU-DEEP 都按自然周计算，开始日必须是周一，结束日必须是周日。
- 当前周未结束时不要作为已完成周报口径。
- 找不到对应 `week_start` 的周汇率时，周利润归集不可计算。
- 对比期是当前周期前一段等长日期范围。
- 周汇率表字段和换算公式详见 `weekly_rates` Skill。

## 账号与成本基础

### WB 账号：`raw_wb_seller_accounts`

- `id`：平台原始账号 ID，WR 的 `store_ref` 使用 `wb:<id>`。
- `name`：店铺展示名。
- `company_type`：税制口径，利润归集会区分一般纳税和小规模口径。
- `is_active`：WR 只使用启用账号。
- 不要查询 `api_token`、`token_type`、`token_expires_at`。

### Ozon 账号：`raw_ozon_seller_accounts`

- `id`：平台原始账号 ID，WR 的 `store_ref` 使用 `ozon:<id>`。
- `company_name`：店铺展示名。
- `company_type`：税制口径。
- `is_active`：WR 只使用启用账号。
- 不要查询 `api_key`、`client_id`、`performance_client_id`、`performance_client_secret`。

### SKU 成本：`ec_sku_costs`

- `sku_code`：内部 SKU 编码，唯一。
- `purchase_price_cny`、`freight_to_by_cny`、`customs_misc_cny`：采购、运费和清关杂费。
- `customs_duty_rate`、`import_vat_rate`：关税和进口 VAT 参数。
- `misc_cost_cny`、`damage_rate`：其他成本和损耗参数。
- `pkg_length_cm`、`pkg_width_cm`、`pkg_height_cm`、`pkg_volume_override_l`：WSU-DEEP ROI 计算会使用体积。

模型计算口径：

- `goods_cost_cny = purchase_price_cny + freight_to_by_cny + customs_misc_cny + customs_duty_cny + import_vat_cny`。
- `customs_duty_cny = purchase_price_cny * customs_duty_rate`。
- `import_vat_cny = (purchase_price_cny + customs_duty_cny) * import_vat_rate`。
- `pkg_volume_l` 优先由长宽高计算，缺失时使用 `pkg_volume_override_l`。

## WB WR 表结构与关系

### `raw_wb_finance_details`

WB 财务明细，是 WB WR 的主表。

- `account_id`：关联 `raw_wb_seller_accounts.id`。
- `sale_dt`：财务发生日期，WR 周期筛选字段。
- `rrdid`：财务行唯一键。
- `nm_id`：WB 商品 ID，可为空；为空时会尝试通过 `shk_id` 反推。
- `shk_id`：WB 条码/货件维度 ID，用于补齐 `nm_id`。
- `report_type`：销售类型，`1` 通常为白俄本地，`2` 通常为出口。
- `seller_oper_name`、`bonus_type_name`：操作类型和未归集分类。
- `for_pay`、`acquiring_fee`、`retail_price_with_disc`、`retail_amount`：结算、手续费和销售额字段。
- `quantity`：数量。
- `delivery_rub`、`rebill_logistic_cost`：物流费用。
- `vw`、`ppvz_reward`、`penalty`、`paid_storage`、`deduction`：平台费用、罚款、仓储和扣款线索。

### `raw_wb_paid_storages`

- `account_id`、`calc_date`：账号和仓储计费日期。
- `nm_id`、`vendor_code`：商品标识。
- `warehouse_price_rub`：仓储费。

### `raw_wb_ad_settled_fees`

- `account_id`：账号。
- `advert_id`：WB 广告活动 ID。
- `period_from`、`period_to`：广告结算周期。
- `upd_sum_rub`：该广告活动结算金额。
- `camp_name`、`payment_type`：广告活动和支付类型线索。

### `raw_wb_ad_campaigns`、`raw_wb_ad_campaign_products`、`raw_wb_ad_sku_spends`

- `raw_wb_ad_campaigns.wb_advert_id = raw_wb_ad_settled_fees.advert_id`。
- `raw_wb_ad_campaign_products.campaign_id = raw_wb_ad_campaigns.id`，`nm_id` 是活动关联商品。
- `raw_wb_ad_sku_spends.campaign_id = raw_wb_ad_campaigns.id`，`nm_id` 和 `stat_date` 用于 SKU 维度广告消耗分摊。
- `raw_wb_ad_sku_spends.spend` 是按商品日期拆出的广告消耗。

### `raw_wb_products`

- `account_id`：账号。
- `nm_id`：WB 商品 ID。
- `vendor_code`：内部 SKU 归集使用的主要字段。
- `title`、`brand`、`subject_name`：商品排查字段。

WB 关联关系：

- 财务、仓储、广告都先限定 `account_id` 和周日期范围。
- `raw_wb_finance_details.nm_id`、`raw_wb_paid_storages.nm_id`、广告消耗 `nm_id` 通过 `raw_wb_products.vendor_code` 归到内部 SKU。
- 成本通过 `raw_wb_products.vendor_code = ec_sku_costs.sku_code` 查找；代码里存在少量别名和大小写兜底，SQL 查询应优先展示原始 `vendor_code` 和匹配后的 `sku_code`。

## Ozon WR 表结构与关系

### `raw_ozon_accrual_by_day`

Ozon 日维度财务 accrual，是 Ozon WR 的主表。

- `account_id`：关联 `raw_ozon_seller_accounts.id`。
- `accrual_date`：财务发生日期，WR 周期筛选字段。
- `posting_number`：发货单号。
- `ozon_sku_id`：Ozon SKU。
- `type_id`、`type_name`：费用类型。
- `accrued_category`：费用分类。
- `amount`：金额，通常为 RUB。
- `currency_code`：币种，默认 `RUB`。

### `raw_ozon_posting_items`

- `account_id`、`posting_number`：关联 accrual 发货单。
- `ozon_sku`：Ozon SKU，对应 `raw_ozon_accrual_by_day.ozon_sku_id`。
- `offer_id`：平台商品编码，用于匹配内部 SKU。
- `quantity`、`price`、`payout`、`commission_amount`：订单商品金额线索。

### `raw_ozon_performance_sku_spends`

- `account_id`：账号。
- `ozon_sku_id`：Ozon SKU。
- `period_from`、`period_to`：广告消耗周期。
- `ad_type`：广告类型，利润归集中区分 `ppc` 和 `promotion`。
- `spend`：SKU 维度广告消耗。
- `campaign_id`、`allsku_spend`、`combo_spend`、`cpo_spend`：广告排查字段。

### `raw_ozon_posting_destinations`

- `account_id`、`posting_number`：发货单目的地。
- `is_belarus`：是否白俄本地销售。
- `region`、`city`、`warehouse_name`、`delivery_schema`、`delivery_method_name`：目的地和履约排查字段。

### `ec_skus`

- `sku_code`：内部 SKU 编码。
- `deleted_at`：默认排除软删除 SKU。
- Ozon WR 通过 `raw_ozon_posting_items.offer_id` 大小写匹配 `ec_skus.sku_code`，再读取 `ec_sku_costs`。

Ozon 关联关系：

- `raw_ozon_accrual_by_day.account_id`、`accrual_date` 是主筛选条件。
- `raw_ozon_accrual_by_day.ozon_sku_id = raw_ozon_posting_items.ozon_sku` 用于获取 `offer_id`。
- `raw_ozon_posting_items.offer_id` 匹配 `ec_skus.sku_code`，成本从 `ec_sku_costs` 获取。
- `raw_ozon_posting_destinations.posting_number` 判定白俄本地或出口销售，影响税和进口 VAT 退回。
- 广告成本优先来自 `raw_ozon_performance_sku_spends`，财务 accrual 中广告类型与 Performance 消耗差额进入未归集。

## WR 计算逻辑

WR 是单账号周利润，输入是 `store_ref`、`from_date`、`to_date`。

- `store_ref` 格式：`wb:<raw_wb_seller_accounts.id>` 或 `ozon:<raw_ozon_seller_accounts.id>`。
- 查询账号时必须要求账号 `is_active = true`。
- 先按 `from_date.beginning_of_week(:monday)` 读取 `ec_weekly_rates`。
- 当前期计算后，再计算前一段等长日期范围用于同比较字段。

### WB WR

1. 从 `raw_wb_finance_details` 读取本账号、周周期内的财务明细。
2. 用同批财务行建立 `shk_id -> nm_id` 映射，补齐缺失的 `nm_id`。
3. 按 `[nm_id, report_type]` 聚合；无法归到商品的金额进入 `unallocated`。
4. 按 `seller_oper_name` 分类：销售计入结算和销售数量，退货冲减结算并计入退货数量，物流、补偿、罚款、取件分别进入对应费用桶。
5. 仓储费从 `raw_wb_paid_storages` 按 `calc_date` 和 `nm_id` 汇总，并归到出口类型。
6. 广告费从 `raw_wb_ad_settled_fees` 读取结算额，再按 `raw_wb_ad_sku_spends` 的 SKU 消耗占比分摊；缺少 SKU 消耗时按广告活动关联商品平均分摊。
7. 通过 `raw_wb_products.nm_id -> vendor_code -> ec_sku_costs.sku_code` 获取成本。
8. `net_qty = sales_qty - return_qty`。
9. WB WR 结果为 BYN 口径：`net = settlement - delivery - storage - ad`，货物成本按 `net_qty * goods_cost_cny` 折算到 BYN 并加 3% 缓冲。
10. `pre_tax = net - goods_cost`。
11. 税费按账号税制计算：一般纳税口径使用销项 VAT 减进口 VAT，小规模口径按税基 6%。
12. `after_tax = pre_tax - tax`。

WB WR 行字段：

- `nm_id`、`vendor_code`、`region`。
- `sales_qty`、`return_qty`、`net_qty`。
- `settlement`、`delivery`、`storage`、`ad`、`goods_cost`。
- `pre_tax`、`tax`、`after_tax`。

### Ozon WR

1. 从 `raw_ozon_accrual_by_day` 读取本账号、周周期内的 accrual。
2. 从 `raw_ozon_posting_items` 建立 `ozon_sku -> offer_id -> ec_skus.sku_code` 映射。
3. 从 `ec_sku_costs` 读取 `goods_cost_cny` 和 `import_vat_cny` 计算口径。
4. 从 `raw_ozon_performance_sku_spends` 读取广告消耗，按 `ad_type` 分为 `ppc` 和 `promotion`。
5. 从 `raw_ozon_posting_destinations` 判断发货单是否白俄本地销售。
6. 按 `type_id` 分类 accrual：销售收入、佣金、支付手续费、配送、退货、仓储、发货、打包、缺陷、crossdock 和其他费用。
7. accrual 中广告类型不直接归入普通费用，而是与 Performance SKU 消耗对账；差额作为未归集广告。
8. 按 `posting_number` 的净销售额判断订单、销售、退货和净销量。
9. 白俄本地/出口数量按发货单目的地拆分，影响 VAT 和出口进口 VAT 退回。
10. `book_profit = sales_revenue + platform fees`。
11. `book_profit_after_ad = book_profit - total_ad_cost`，其中广告成本在结果里通常为负数。
12. 货物成本：`goods_cost = -(net_sales_count * goods_cost_cny * rate_cny_rub * 1.03)`。
13. `pre_tax_profit = book_profit_after_ad + goods_cost`。
14. 白俄本地销售计算 VAT 成本，出口销售按数量退回进口 VAT。
15. `after_tax_profit = pre_tax_profit + blr_tax + export_refund`。

Ozon WR 行字段：

- `ozon_sku_id`、`sku_code`。
- `sales_revenue`、`commission`、`delivery_charge`。
- `ppc_cost`、`promotion_cost`、`total_ad_cost`。
- `order_count`、`return_count`、`net_sales_count`、`blr_count`、`export_count`。
- `goods_cost`、`pre_tax_profit`、`after_tax_profit`、`after_tax_margin_pct`。

## WSU 计算逻辑

WSU 是跨账号、跨平台的周利润汇总，结果统一为 CNY。

1. 根据 `from_date` 解析 `Ec::WeeklyRate`。
2. 遍历所有 `RawWb::SellerAccount`，对每个账号运行 WB WR 归集。
3. WB WR 行按 `vendor_code` 聚合为 SKU；跳过空 SKU。
4. WB 金额从 BYN 转 CNY：`byn_cny = rate_byn_rub / rate_cny_rub`。
5. WB 行字段：`sku`、`platform = 'WB'`、`shop`、`net_sales`、`revenue`、`ads`、`goods_cost`、`pre_tax`、`tax`、`after_tax`。
6. WB 未归集金额按 `-(unallocated sum * byn_cny)` 计入 `wb_unallocated`。
7. 遍历所有 `RawOzon::SellerAccount`，对每个账号运行 Ozon WR 归集。
8. Ozon WR 行按 `sku_code` 输出；跳过空 SKU。
9. Ozon 金额从 RUB 转 CNY：`rub_cny = 1 / rate_cny_rub`。
10. Ozon `revenue = sales_revenue * rub_cny`。
11. Ozon `ads = -(ppc_cost + promotion_cost) * rub_cny`。
12. Ozon `goods_cost = -goods_cost * rub_cny`。
13. Ozon `pre_tax = (pre_tax_profit || book_profit_after_ad) * rub_cny`。
14. Ozon `after_tax = (after_tax_profit || book_profit_after_ad) * rub_cny`。
15. Ozon `tax = pre_tax - after_tax`。
16. Ozon 未归集金额按 `unallocated[:total] * rub_cny` 计入 `ozon_unallocated`。
17. WSU 行按 `after_tax` 降序排序，并计算 `margin_pct = after_tax / revenue * 100`。

WSU 行字段：

- `sku`、`platform`、`shop`。
- `net_sales`、`revenue`、`ads`、`goods_cost`。
- `pre_tax`、`tax`、`after_tax`、`margin_pct`。

WSU 汇总字段：

- `total_sales_revenue`、`total_after_tax`、`total_margin_pct`。
- `wb_sales_revenue`、`wb_ads`、`wb_goods_cost`、`wb_pre_tax`、`wb_after_tax`。
- `ozon_sales_revenue`、`ozon_ads`、`ozon_goods_cost`、`ozon_pre_tax`、`ozon_after_tax`。
- `wb_unallocated`、`ozon_unallocated`、`unallocated_total`。
- `after_tax_with_unallocated`、`margin_with_unallocated_pct`。

## WSU-DEEP 计算逻辑

WSU-DEEP 基于 WSU 的 CNY 明细继续聚合和扩展指标。

1. 先执行 WSU 的跨账号、跨平台归集逻辑。
2. 按大写后的 `sku` 聚合所有平台和店铺。
3. 对每个 SKU 汇总 `net_sales`、`revenue`、`ads`、`goods_cost`、`pre_tax`、`tax`、`after_tax`。
4. 从 `ec_skus` 读取 SKU，并包含 `ec_sku_costs` 成本。
5. `margin_pct = after_tax / revenue * 100`。
6. `average_profit_per_order = after_tax / net_sales`。
7. `ad_ratio_pct = ads / revenue * 100`。
8. `cost_return_pct = after_tax / goods_cost * 100`。
9. ROI 使用 `Ec::ProjectedStockRoiCalculator`：输入 `net_sales_quantity`、`operating_profit_cny`、周期天数、单件 `goods_cost_cny` 和单件体积 `pkg_volume_l`。
10. ROI 以 180 天备货假设计算预估备货量、平均库存、周转周期、仓储费、资金利息、成本基数、调整后经营净利、投产比和年化收益。
11. 成本或体积缺失时，基础利润指标仍可返回，但 `projected_roi_pct`、`annualized_return_pct` 等深度投产指标可能为空。

WSU-DEEP 行字段：

- `sku`。
- `net_sales`、`revenue`、`ads`、`goods_cost`。
- `pre_tax`、`tax`、`after_tax`、`margin_pct`。
- `average_profit_per_order`、`ad_ratio_pct`、`cost_return_pct`。
- `projected_roi_pct`、`annualized_return_pct`、`annualized_net_profit_cny`。

WSU-DEEP 汇总字段：

- `total_sku_count`、`total_net_sales`。
- `total_sales_revenue`、`total_ads`、`total_goods_cost`。
- `total_pre_tax`、`total_after_tax`、`total_margin_pct`。
- `unallocated_total`、`after_tax_with_unallocated`。

## 线上样本验证过程

以下样本来自线上 `2026-07-06 ~ 2026-07-12` 完整自然周，用于校验 WR、WSU、WSU-DEEP 的字段换算和聚合链路。

汇率：

- `ec_weekly_rates.week_start = 2026-07-06`。
- `rate_cny_rub = 11.3803`。
- `rate_byn_rub = 26.584`。
- `rub_cny = 1 / 11.3803 = 0.087871`。
- `byn_cny = 26.584 / 11.3803 = 2.335967`。

### WB WR 到 WSU

样本：`store_ref = wb:2`，SKU `KJ-217-GD`。

WR 中该 SKU 有白俄和出口两行：

- 白俄行：`sales_qty = 2`、`return_qty = 0`、`settlement = 817.65`、`ad = 74.49`、`goods_cost = 336.62`、`pre_tax = 212.36`、`after_tax = 148.62`。
- 出口行：`sales_qty = 10`、`return_qty = 0`、`settlement = 3908.31`、`ad = 372.44`、`goods_cost = 1683.08`、`pre_tax = 1636.22`、`after_tax = 1328.25`。

转换到 WSU：

- `net_sales = (2 - 0) + (10 - 0) = 12`。
- `revenue = (817.65 + 3908.31) * 2.335967 = 11039.68`。
- `ads = (74.49 + 372.44) * 2.335967 = 1044.01`。
- `goods_cost = (336.62 + 1683.08) * 2.335967 = 4717.95`。
- `pre_tax = (212.36 + 1636.22) * 2.335967 = 4318.22`。
- `after_tax = (148.62 + 1328.25) * 2.335967 = 3449.92`。
- `tax = 4318.22 - 3449.92 = 868.30`。
- `margin_pct = 3449.92 / 11039.68 * 100 = 31.25`。

对应 WSU 行：

- `sku = KJ-217-GD`、`platform = WB`、`net_sales = 12`、`revenue = 11039.68`、`ads = 1044.01`、`goods_cost = 4717.95`、`pre_tax = 4318.22`、`tax = 868.30`、`after_tax = 3449.92`、`margin_pct = 31.25`。

### Ozon WR 到 WSU

样本：`store_ref = ozon:1`，SKU `KJ-217-GD`。

WR 行：

- `sales_revenue = 187420.00`。
- `ppc_cost = -7900.00`。
- `promotion_cost = -20962.00`。
- `goods_cost = -80537.28`。
- `pre_tax_profit = 47891.60`。
- `after_tax_profit = 60424.45`。
- `net_sales_count = 18`。

转换到 WSU：

- `net_sales = 18`。
- `revenue = 187420.00 * 0.087871 = 16468.81`。
- `ads = -(-7900.00 + -20962.00) * 0.087871 = 2536.14`。
- `goods_cost = -(-80537.28) * 0.087871 = 7076.90`。
- `pre_tax = 47891.60 * 0.087871 = 4208.29`。
- `after_tax = 60424.45 * 0.087871 = 5309.57`。
- `tax = 4208.29 - 5309.57 = -1101.28`。
- `margin_pct = 5309.57 / 16468.81 * 100 = 32.24`。

对应 WSU 行：

- `sku = KJ-217-GD`、`platform = Ozon`、`net_sales = 18`、`revenue = 16468.81`、`ads = 2536.14`、`goods_cost = 7076.90`、`pre_tax = 4208.29`、`tax = -1101.28`、`after_tax = 5309.57`、`margin_pct = 32.24`。

### WSU 到 WSU-DEEP

样本：SKU `KJ-217-GD` 在该周 WSU 中共有四行：

- Ozon / NEVASTAL：`net_sales = 18`、`revenue = 16468.81`、`ads = 2536.14`、`goods_cost = 7076.90`、`pre_tax = 4208.29`、`tax = -1101.28`、`after_tax = 5309.57`。
- WB / ООО "Такси Линк"：`net_sales = 12`、`revenue = 11039.68`、`ads = 1044.01`、`goods_cost = 4717.95`、`pre_tax = 4318.22`、`tax = 868.30`、`after_tax = 3449.92`。
- WB / OOO «МИРОВОЙ ВЫБОР»：`net_sales = 1`、`revenue = 999.65`、`ads = 0.00`、`goods_cost = 393.17`、`pre_tax = 557.99`、`tax = 162.91`、`after_tax = 395.08`。
- Ozon / Domos：`net_sales = 0`、`revenue = 0.00`、`ads = 0.00`、`goods_cost = 0.00`、`pre_tax = -705.74`、`tax = 0.00`、`after_tax = -705.74`。

WSU-DEEP 聚合结果：

- `net_sales = 18 + 12 + 1 + 0 = 31`。
- `revenue = 16468.81 + 11039.68 + 999.65 + 0.00 = 28508.14`。
- `ads = 2536.14 + 1044.01 + 0.00 + 0.00 = 3580.15`。
- `goods_cost = 7076.90 + 4717.95 + 393.17 + 0.00 = 12188.02`。
- `pre_tax = 4208.29 + 4318.22 + 557.99 - 705.74 = 8378.76`。
- `tax = -1101.28 + 868.30 + 162.91 + 0.00 = -70.07`。
- `after_tax = 5309.57 + 3449.92 + 395.08 - 705.74 = 8448.83`。
- `margin_pct = 8448.83 / 28508.14 * 100 = 29.64`。
- `average_profit_per_order = 8448.83 / 31 = 272.54`。
- `ad_ratio_pct = 3580.15 / 28508.14 * 100 = 12.56`。
- `cost_return_pct = 8448.83 / 12188.02 * 100 = 69.32`。

对应 WSU-DEEP 行：

- `sku = KJ-217-GD`、`net_sales = 31`、`revenue = 28508.14`、`ads = 3580.15`、`goods_cost = 12188.02`、`pre_tax = 8378.76`、`tax = -70.07`、`after_tax = 8448.83`、`margin_pct = 29.64`、`average_profit_per_order = 272.54`、`ad_ratio_pct = 12.56`、`cost_return_pct = 69.32`。

## 查询策略

- 用户问单店铺周利润、单平台账号周利润、WR 时，使用 WR 口径并明确平台账号和自然周。
- 用户问跨平台、跨店铺、SKU+店铺维度周利润时，使用 WSU 口径。
- 用户问 SKU 总体周利润、投产、年化、周转、深度利润分析时，使用 WSU-DEEP 口径。
- 直接用 SQL 排查时，优先查询上述原始表的中间归因字段；不要假设存在已经落库的 WR、WSU 或 WSU-DEEP 结果表。
- 未归集金额不应静默丢弃；回答利润时应说明是否包含 `unallocated`。
- Ozon 广告成本注意符号：WR 结果中广告成本通常为负数，WSU 展示时转为正向成本字段 `ads`。
- WB WR 是 BYN 口径，WSU/WSU-DEEP 是 CNY 口径；跨报表比较前必须先确认币种。
