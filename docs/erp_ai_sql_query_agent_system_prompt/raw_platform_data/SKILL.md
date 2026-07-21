# Raw Platform Data SQL Skill

用于需要查看 WB/Ozon 平台原始接口数据、原始状态、原始商品信息、广告、搜索词、评价、问答、聊天、供货、财务明细时加载。优先使用标准化 `Ec::*` 表；只有标准化表缺少字段或用户明确要求平台原始数据时才使用本 Skill。

## 原始账号

### `raw_wb_seller_accounts`

- `id`：WB 原始账号 ID。
- `name`：账号名。
- `company_type`：主体类型。
- `is_active`：是否启用。
- `token_type`、`token_expires_at`：token 元信息。
- `api_token`：敏感字段，不要查询。

关系：`ec_stores.wb_raw_account_id = raw_wb_seller_accounts.id`。

### `raw_ozon_seller_accounts`

- `id`：Ozon 原始账号 ID。
- `client_id`：敏感/凭据相关字段，不要查询。
- `api_key`：敏感字段，不要查询。
- `company_name`、`legal_name`、`company_type`、`inn`、`ownership_form`。
- `is_active`。
- `performance_client_id`、`performance_client_secret`：敏感字段，不要查询。

关系：`ec_stores.ozon_raw_account_id = raw_ozon_seller_accounts.id`。

## Ozon 商品与库存

- `raw_ozon_products`：商品主数据。字段：`account_id`、`ozon_product_id`、`offer_id`、`name`、`currency_code`、`description_category_id`、`type_id`、`is_archived`、`is_autoarchived`、`barcodes`、`images`、`commissions`、`availabilities`、`discounted_fbo_stocks`、`synced_at`。
- `raw_ozon_product_attributes`：商品属性。字段：`account_id`、`ozon_product_id`、`offer_id`、`barcode`、`product_attributes`、`complex_attributes`、`synced_at`。
- `raw_ozon_product_prices`：商品价格。字段：`account_id`、`ozon_product_id`、`offer_id`、`price`、`old_price`、`marketing_price`、`min_price`、`buybox_price`、`discount_percent`、`is_in_discount`、`commissions`、`acquiring`、`volume_weight`、`synced_at`。
- `raw_ozon_product_stocks`：商品库存。字段：`account_id`、`ozon_product_id`、`offer_id`、`present_fbo`、`reserved_fbo`、`present_fbs`、`reserved_fbs`、`stocks_by_warehouse`、`synced_at`。
- `raw_ozon_analytics_stocks`：库存分析。字段：`account_id`、`ozon_sku`、`item_code`、`item_name`、`warehouse_name`、`present`、`reserved`、`synced_at`。
- `raw_ozon_sales_funnel_daily`：Ozon 日维度 SKU 销售漏斗。字段：`account_id`、`stat_date`、`sku`、`product_name`、`hits_view`、`hits_view_search`、`hits_view_pdp`、`session_view`、`session_view_search`、`session_view_pdp`、`hits_tocart`、`hits_tocart_search`、`hits_tocart_pdp`、`ordered_units`、`revenue`、`returns_count`、`cancellations`、`synced_at`。注意 `session_view*` 是区间去重会话口径，日表跨天汇总不能替代周/月接口区间口径。

关系：

- Ozon 商品绑定通常使用 `ec_sku_products.product_id = raw_ozon_products.ozon_product_id::text`，并通过 `ec_stores.ozon_raw_account_id = raw_ozon_products.account_id` 限定店铺账号。
- Ozon SKU 相关数据可用 `ec_sku_products.platform_sku_id = ozon_sku::text` 归属。

## Ozon 订单、退货与财务

- `raw_ozon_postings_fbo`：FBO posting。字段：`account_id`、`posting_number`、`order_id`、`order_number`、`status`、`substatus`、`created_at`、`in_process_at`、`fact_delivery_date`、`cancel_reason_id`、`financial_data`、`analytics_data`、`synced_at`。
- `raw_ozon_postings_fbs`：FBS posting。字段：`account_id`、`posting_number`、`order_id`、`order_number`、`status`、`substatus`、`created_at`、`in_process_at`、`shipment_date`、`delivering_date`、`tracking_number`、`delivery_method_name`、`financial_data`、`analytics_data`、`synced_at`。
- `raw_ozon_posting_items`：posting 明细。字段：`account_id`、`posting_number`、`posting_type`、`ozon_sku`、`offer_id`、`name`、`quantity`、`price`、`old_price`、`payout`、`commission_amount`、`commission_percent`、`currency_code`、`synced_at`。
- `raw_ozon_posting_destinations`：目的地。字段：`account_id`、`posting_number`、`city`、`region`、`warehouse_name`、`delivery_schema`、`delivery_method_name`、`fact_delivery_date`、`is_belarus`。
- `raw_ozon_returns`：退货。字段：`account_id`、`return_id`、`posting_number`、`order_number`、`order_id`、`ozon_sku`、`offer_id`、`product_name`、`quantity`、`price`、`return_schema`、`return_type`、`return_reason_name`、`visual_status`、`return_date`、`final_moment`、`visual_change_moment`、`synced_at`。
- `raw_ozon_finance_transactions`：财务流水。字段见 `costs_profit` Skill。
- `raw_ozon_accrual_by_day`：日维度 accrual。字段见 `costs_profit` Skill。

## Ozon 广告、搜索、评价与沟通

- `raw_ozon_performance_campaigns`：广告活动。字段：`account_id`、`campaign_id`、`title`、`state`、`adv_object_type`、`payment_type`、`daily_budget`、`weekly_budget`、`from_date`、`to_date`。
- `raw_ozon_performance_daily_stats`：广告日统计。字段：`account_id`、`campaign_id`、`stat_date`、`impressions`、`clicks`、`spend`、`orders_count`、`orders_revenue`。
- `raw_ozon_performance_sku_spends`：SKU 广告花费。字段：`account_id`、`ozon_sku_id`、`period_from`、`period_to`、`ad_type`、`campaign_id`、`spend`、`allsku_spend`、`combo_spend`、`cpo_spend`。
- `raw_ozon_product_queries`：商品搜索表现。字段：`account_id`、`period_from`、`period_to`、`sku`、`name`、`offer_id`、`category`、`position`、`gmv`、`unique_search_users`、`unique_view_users`、`view_conversion`。
- `raw_ozon_product_query_details`：搜索词明细。字段：`account_id`、`period_from`、`period_to`、`sku`、`query`、`query_index`、`position`、`gmv`、`order_count`、`unique_search_users`、`unique_view_users`。
- `raw_ozon_reviews`：评价。字段：`account_id`、`review_id`、`ozon_sku`、`offer_id`、`product_name`、`rating`、`status`、`text/comment`、`response`、`created_at`、`updated_at`。
- `raw_ozon_questions`：问答。字段：`account_id`、`question_id`、`ozon_sku`、`offer_id`、`product_name`、`text`、`answer`、`status`、`created_at`、`answer_at`。
- `raw_ozon_chats`、`raw_ozon_chat_messages`：聊天。

## WB 商品与库存

- `raw_wb_products`：商品卡。字段：`account_id`、`nm_id`、`vendor_code`、`title`、`brand`、`subject_id`、`subject_name`、`wb_category`、`imt_id`、`is_in_trash`、`synced_at`。
- `raw_wb_product_skus`：条码/尺码。字段：`product_id`、`chrt_id`、`barcode`、`tech_size`、`wb_size`、`skus`。
- `raw_wb_product_prices`：价格。字段：`account_id`、`product_id`、`price`、`discount`、`club_discount`、`final_price`、`is_in_quarantine`。
- `raw_wb_fbs_stocks`：FBS 库存。字段：`account_id`、`nm_id`、`barcode`、`amount`、`synced_at`。
- `raw_wb_stocks`：仓库库存。字段：`account_id`、`warehouse_id`、`barcode`、`quantity`、`sku_id`、`updated_at`。
- `raw_wb_warehouses`：仓库。字段：`account_id`、`wb_warehouse_id`、`name`、`city`、`address`、`warehouse_type`、`work_time`、`latitude`、`longitude`、`is_active`。

关系：

- WB 商品绑定使用 `ec_sku_products.product_id = raw_wb_products.nm_id::text`，并通过 `ec_stores.wb_raw_account_id = raw_wb_products.account_id` 限定店铺账号。
- WB 条码库存可从 `raw_wb_product_skus.product_id -> raw_wb_products.id` 再关联 `barcode`。

## WB 订单、销售、退货与供货

- `raw_wb_orders`：平台订单。字段：`account_id`、`wb_order_id`、`g_number`、`order_uid`、`srid`、`nm_id`、`barcode`、`article`、`delivery_type`、`warehouse_id`、`warehouse_type`、`supplier_status`、`wb_status`、`price`、`converted_price`、`created_at`、`synced_at`。
- `raw_wb_stats_orders`：统计订单。字段：`account_id`、`order_date`、`last_change_date`、`nm_id`、`supplier_article`、`barcode`、`total_price`、`discount_percent`、`is_cancel`、`cancel_date`、`g_number`、`srid`、`warehouse_name`、`oblast`。
- `raw_wb_stats_sales`：统计销售。字段：`account_id`、`sale_date`、`last_change_date`、`sale_id`、`nm_id`、`supplier_article`、`barcode`、`total_price`、`price_with_disc`、`finished_price`、`for_pay`、`is_storno`、`srid`、`warehouse_name`。
- `raw_wb_sales_reports`、`raw_wb_sales_report_items`：销售报告和明细。字段见 `costs_profit` Skill。
- `raw_wb_goods_returns`：退货。字段：`account_id`、`nm_id`、`order_id`、`shk_id`、`srid`、`barcode`、`status`、`return_type`、`reason`、`order_dt`、`ready_to_return_dt`、`completed_dt`、`expired_dt`。
- `raw_wb_supplies`：供货单。字段：`account_id`、`wb_supply_id`、`name`、`preorder_id`、`is_done`、`status_id`、`supply_created_at`、`supply_date`、`closed_at`、`fact_date`。
- `raw_wb_supply_items`：供货商品。字段：`account_id`、`wb_supply_id`、`nm_id`、`quantity`、`accepted_qty`、`synced_at`。

## WB 广告、分析、评价与沟通

- `raw_wb_sales_funnel_daily`：WB 日维度商品销售漏斗。字段：`account_id`、`stat_date`、`nm_id`、`vendor_code`、`product_name`、`brand`、`subject_id`、`subject`、`open_card`、`add_to_cart`、`orders`、`orders_sum`、`buyouts`、`buyouts_sum`、`cancel_count`、`cancel_sum`、`buyout_percent`、`cart_to_order`、`conv_to_cart`、`share_order_percent`、`add_to_wishlist`、`localization_percent`、`synced_at`。
- `raw_wb_analytics_search_terms`：搜索词。字段：`account_id`、`stat_date`、`keyword`、`nm_id`、`product_name`、`brand_name`、`subject_name`、`frequency`、`week_frequency`、`open_card`、`add_to_cart`、`orders`、`avg_position`、`median_position`、`visibility`。
- `raw_wb_ad_campaigns`：广告活动。字段：`account_id`、`wb_advert_id`、`name`、`campaign_type`、`status`、`start_time`、`end_time`、`daily_budget`、`total_budget`。
- `raw_wb_ad_daily_stats`：广告日统计。字段：`campaign_id`、`stat_date`、`views`、`clicks`、`spend`、`orders`、`revenue`、`ctr`、`cpc`、`cr`。
- `raw_wb_ad_sku_spends`：SKU 广告花费。字段：`campaign_id`、`nm_id`、`stat_date`、`spend`。
- `raw_wb_reviews`：评价。字段：`account_id`、`wb_review_id`、`nm_id`、`vendor_code`、`rating`、`text`、`answer_text`、`is_answered`、`was_viewed`、`wb_created_at`。
- `raw_wb_questions`：问答。字段：`account_id`、`wb_question_id`、`nm_id`、`vendor_code`、`text`、`answer_text`、`is_answered`、`was_viewed`、`wb_created_at`。
- `raw_wb_chats`、`raw_wb_chat_messages`：聊天。

## 使用原则

- 原始表的 `account_id` 必须通过 `ec_stores.wb_raw_account_id` 或 `ec_stores.ozon_raw_account_id` 与内部店铺绑定，避免跨店铺混算。
- 原始平台商品归属内部 SKU 时优先用 `ec_sku_products`，不要用商品名模糊匹配。
- 原始 JSON 字段只用于已展开字段不足的排查场景。
- 不要查询任何账号 token、api key、client secret 字段。
