# SKU v3 上下文 API 字段说明

本文档用于解释 `fetch-yuanlong-sku-context` 获取的 v3 分段 SKU 经营上下文。字段中文含义优先对齐辕隆 ERP 的 SKU 详情页、销售漏斗、利润归集、库存、生命周期、送仓记录和运营记录页面；分析时仍以接口字段名和本文口径为准。

v3 默认拉取 Markdown，适合人类和 AI 快速阅读；JSON 接口保留完整结构。Markdown 渲染会把扁平数组压成表格，`operation_actions_full_period.md` 会按日志表展示并省略展开后的 `diff_result`，完整变更明细仍以 JSON 中的 `diff_result` 为准。

金额为 `null` 表示缺少计算所需数据，不能按 `0` 解读。空数组表示系统在该查询范围内没有已记录明细，不能据此断言业务事件从未发生。所有日期边界按响应中的 `period.time_zone` 解读。

## 请求

所有分段接口共享参数：

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `sku_code` | 是 | 内部 SKU 编码，不区分输入大小写 |
| `period_from` | 否 | 查询周期开始日；传入时必须是周一 |
| `period_to` | 否 | 查询周期结束日；传入时必须是周日 |
| `target_days` | 否 | 仅分仓建议使用，表示建议覆盖天数；服务端会限制在允许范围内 |

脚本默认请求 Markdown 格式：

```http
GET /ai/v3/sku/<section>_context.md?sku_code=<SKU>&period_from=<MONDAY>&period_to=<SUNDAY>
Authorization: Bearer <assigned_user_api_key>
Accept: text/markdown
```

可请求的分段接口与本地文件：

| 本地文件 | 接口 | 上下文键 |
| --- | --- | --- |
| `base.md` | `/ai/v3/sku/base_context.md` | `base` |
| `sales_funnel.md` | `/ai/v3/sku/sales_funnel_context.md` | `sales_funnel` |
| `profit.md` | `/ai/v3/sku/profit_context.md` | `profit` |
| `inventory.md` | `/ai/v3/sku/inventory_context.md` | `inventory` |
| `lifecycle.md` | `/ai/v3/sku/lifecycle_context.md` | `lifecycle` |
| `advertise_per_week.md` | `/ai/v3/sku/advertising_context.md` | `advertise_per_week` |
| `ec_orders_full_period.md` | `/ai/v3/sku/orders_context.md` | `ec_orders_full_period` |
| `supply_orders_full_period.md` | `/ai/v3/sku/supply_orders_context.md` | `supply_orders_full_period` |
| `operation_actions_full_period.md` | `/ai/v3/sku/operation_actions_context.md` | `operation_actions_full_period` |
| `warehouse_recommendation.md` | `/ai/v3/sku/warehouse_recommendation_context.md` | `warehouse_recommendation` |
| `search_terms_per_week.md` | `/ai/v3/sku/search_terms_context.md` | `search_terms_per_week` |

完整接口 `/ai/v3/sku/full_context.md` 仍可用于一次性获取全部上下文，但默认应使用分段接口，避免单个请求过慢。

错误状态：`400` 表示参数缺失，`401` 表示鉴权失败，`404` 表示 SKU 不存在，`422` 表示日期格式、自然周边界或参数值无效。

## 响应信封

每个分段接口都会返回同样的外层信封，只是 `data` 内只包含当前分段的上下文键。

| 字段 | 说明 |
| --- | --- |
| `data.schema_version` | 上下文结构版本，v3 固定为 `3` |
| `data.sku_code` | 标准化后的内部 SKU 编码 |
| `data.period.from` | 请求周期开始日，完整自然周的周一 |
| `data.period.to` | 请求周期结束日，完整自然周的周日 |
| `data.period.as_of` | 服务端按用户时区计算的上下文生成日期；库存、生命周期等“当前值”以此日期为准 |
| `data.period.time_zone` | 服务端解析日期边界和展示日期所用时区 |
| `data.period.week_starts_on` | 周起始规则，当前固定为 `monday` |

## `base.md` / `base`：SKU 基础信息

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `spu_code` | SPU 编码 | 当前 SKU 所属的 SPU；未归属时为 `null` |
| `spu_id` | SPU ID | SPU 数据库 ID；未归属时为 `null` |
| `related_spu_sku_codes` | 同 SPU 关联 SKU | 同一 SPU 下除当前 SKU 外的其他 SKU 编码 |
| `current_stage` | 当前营销阶段 | 常见值：`NEW` 新品、`GRW` 成长、`MAT` 成熟、`CLR` 清仓 |
| `current_grade` | 当前营销等级 | 常见值：`S`、`A`、`B`、`C` |
| `sku_products` | 平台商品绑定 | 当前 SKU 在各店铺的平台商品绑定列表 |
| `sku_products[].store_id` | ERP 店铺 ID | `Ec::Store` ID |
| `sku_products[].platform` | 平台 | `wb` 或 `ozon` |
| `sku_products[].product_id` | 平台商品 ID | WB 使用商品 `nmId`；Ozon 为平台商品绑定 ID |
| `sku_products[].offer_id` | 商家货号 | 平台侧 offer/vendor code |
| `sku_products[].product_info` | 平台商品基础信息 | 当前同步到库的平台商品资料；未同步到对应商品时为 `null`，字段随平台不同 |
| `sku_products[].price_info` | 当前价格信息 | 最近一次同步到库的当前价格；未同步价格或没有对应商品时为 `null`，不包含价格历史 |

### WB 商品与价格字段

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `product_info.nm_id` | WB 商品 ID | WB 的 `nmId` |
| `product_info.vendor_code` | 商家编码 | WB 商品卡片中的商家货号 |
| `product_info.title` | 商品标题 | WB 商品名称 |
| `product_info.brand` | 品牌 | WB 商品品牌 |
| `product_info.subject_id` | 品类 ID | WB 商品所属 subject ID |
| `product_info.subject_name` | 品类名称 | WB 商品所属 subject 名称 |
| `product_info.wb_category` | WB 类目 | WB 返回的类目名称 |
| `product_info.description` | 商品描述 | WB 商品卡片描述 |
| `product_info.is_in_trash` | 是否在回收站 | `true` 表示商品已进入 WB 回收站 |
| `product_info.synced_at` | 商品同步时间 | 该商品基础信息最近同步时间 |
| `price_info.price` | 商品原价 | 折扣前价格 |
| `price_info.discount` | 普通折扣率 | WB 普通折扣百分比 |
| `price_info.club_discount` | WB Club 折扣率 | 会员额外折扣百分比 |
| `price_info.final_price` | 当前成交价 | 应用当前折扣后的最终价格 |
| `price_info.is_in_quarantine` | 价格是否隔离 | `true` 表示当前价格处于 WB 价格隔离状态 |
| `price_info.updated_at` | 价格更新时间 | 当前价格记录最近更新时间 |

### Ozon 商品与价格字段

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `product_info.ozon_product_id` | Ozon 商品 ID | Ozon 平台商品 ID |
| `product_info.offer_id` | 商家货号 | Ozon 商品的 offer ID |
| `product_info.name` | 商品名称 | Ozon 商品标题 |
| `product_info.description_category_id` | 描述类目 ID | Ozon 描述类目编号 |
| `product_info.type_id` | 商品类型 ID | Ozon 商品类型编号 |
| `product_info.currency_code` | 商品币种 | 商品资料中的币种代码 |
| `product_info.barcodes` | 条形码 | 商品绑定的条形码列表 |
| `product_info.is_archived` | 是否归档 | `true` 表示商品已归档 |
| `product_info.is_autoarchived` | 是否自动归档 | `true` 表示商品由 Ozon 自动归档 |
| `product_info.has_discounted_fbo_item` | 是否有 FBO 折价品 | 是否存在 FBO 折价商品 |
| `product_info.discounted_fbo_stocks` | FBO 折价品库存 | 当前同步的 FBO 折价品库存数量 |
| `product_info.created_at` | 平台创建时间 | Ozon 返回的商品创建时间 |
| `product_info.synced_at` | 商品同步时间 | 该商品基础信息最近同步时间 |
| `price_info.price` | 当前售价 | Ozon 当前基础售价 |
| `price_info.old_price` | 划线价 | 优惠前展示价格 |
| `price_info.marketing_price` | 营销活动价 | 应用平台营销活动后的价格 |
| `price_info.min_price` | 最低价格 | 商家设置或平台返回的最低价格 |
| `price_info.buybox_price` | Buy Box 价格 | 当前主报价价格 |
| `price_info.discount_percent` | 折扣率 | 当前折扣百分比 |
| `price_info.is_in_discount` | 是否参与折扣 | 当前商品是否处于折扣状态 |
| `price_info.currency_code` | 价格币种 | 各价格字段使用的币种代码 |
| `price_info.acquiring` | 收单费 | 当前价格对应的收单费用 |
| `price_info.volume_weight` | 体积重量 | Ozon 计费使用的体积重量 |
| `price_info.synced_at` | 价格同步时间 | 当前价格最近同步时间 |

`product_info` 和 `price_info` 只返回便于分析的结构化字段，不返回 `raw_json`、图片、佣金明细或平台完整原始载荷，避免基础上下文过大。

## `sales_funnel.md` / `sales_funnel`：销售漏斗

此板块对应 SKU 详情页的“销售漏斗”。周期必须是完整自然周；服务端会同时返回当前周期 `P0` 和若干前序同长度周期，便于比较。漏斗数据包含平台原始漏斗、ERP 订单归属和库存快照三类来源，不能把所有字段都当成同一张平台报表。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `sku_funnel_overview_per_week.metrics` | SKU 总览指标列表 | SKU 维度会排除 `store_ending_inventory`，因为店铺库存不能直接跨店铺作为单一指标解释 |
| `sku_funnel_overview_per_week.periods` | SKU 周期总览 | 每个周期一行，`values` 按 `metrics` 存放 SKU 汇总值 |
| `sku_funnel_store_listing_perweek.metrics` | 店铺/Listing 指标列表 | 店铺 Listing 维度字段，包含平台专属指标和店铺期末库存 |
| `sku_funnel_store_listing_perweek.periods` | 周期定义 | 每个周期的 `period_key`、`period_from`、`period_to` |
| `sku_funnel_store_listing_perweek.store_listings` | 店铺/Listing 分组 | 每个 SKU 平台绑定一个分组；Markdown 中的 `rows_per_week` 通常会渲成表格 |
| `store_listings[].store_ref` | 平台账号引用 | 格式通常为 `wb:<账号ID>` 或 `ozon:<账号ID>` |
| `store_listings[].store_id` | ERP 店铺 ID | `Ec::Store` ID |
| `store_listings[].sku_product_id` | SKU 平台绑定 ID | `Ec::SkuProduct` ID |
| `store_listings[].platform` | 平台 | `wb` 或 `ozon` |
| `store_listings[].store_name` | 店铺名称 | ERP 内店铺展示名 |
| `store_listings[].listing_label` | Listing 标签 | 优先商品名，否则商家货号或平台商品 ID |
| `*.periods[].period_key` / `rows_per_week[].period_key` | 周期键 | `P0` 为请求周期；`P-1`、`P-2` 等为等长前序周期 |
| `*.periods[].values` / `rows_per_week[].values` | 指标值 | 扁平指标字典；Markdown 表格中会展开为指标列 |
| `*.periods[].available_metrics` / `rows_per_week[].available_metrics` | 可用指标 | 表示该周期有来源数据支撑的字段。缺失字段不要强行按 0 分析 |

### 漏斗指标

| 指标 | 中文含义 | 说明 |
| --- | --- | --- |
| `product_card_views` | 商品卡访问 | WB 为打开商品卡；Ozon 为 PDP 详情页访问 |
| `cart_additions` | 加购 | WB/Ozon 商品卡来源加购 |
| `cart_rate` | 加购率 | `cart_additions / product_card_views * 100` |
| `orders` | 下单 | 平台漏斗口径下单件数，来自平台漏斗源 |
| `cart_to_order_rate` | 加购到下单率 | `orders / cart_additions * 100` |
| `cancellations` | 取消数 | 平台漏斗源中的取消件数 |
| `conversions` | 成交 | ERP 订单归属中状态为 `delivered` 或 `returned` 的件数 |
| `visit_to_conversion_rate` | 访问到成交率 | `conversions / product_card_views * 100` |
| `net_sales` | 净销量 | ERP 订单归属中已签收/已完成销量，按平台绑定匹配 |
| `store_ending_inventory` | 店铺期末库存 | 该店铺在周期结束日库存快照中的 FBO/FBW 类库存 |
| `sku_ending_inventory` | SKU 期末总库存 | 周期结束日 SKU 账面库存快照总量 |
| `order_amount` | 下单金额 | 平台漏斗源金额；WB/Ozon 均保留源币种 |
| `currency` | 币种 | 店铺 Listing 漏斗金额字段的币种 |
| `platform_fulfilled` | 平台成交/签收 | WB 为 buyouts；Ozon 为 delivered_units |
| `ozon_total_views` | Ozon 总曝光 | Ozon 全来源曝光 |
| `ozon_search_views` | Ozon 搜索/目录曝光 | Ozon 搜索或目录曝光 |
| `ozon_click_rate` | Ozon 详情页点击率 | `product_card_views / ozon_search_views * 100` |
| `ozon_all_cart_additions` | Ozon 全来源加购 | Ozon 全入口加购 |
| `ozon_search_cart_additions` | Ozon 搜索/目录加购 | Ozon 搜索或目录来源加购 |
| `ozon_average_search_position` | Ozon 平均搜索排名 | Ozon 搜索/目录平均排名；数值越小排名越靠前 |
| `ozon_returns` | Ozon 退货数 | Ozon 漏斗源退货件数 |
| `wb_buyout_amount` | WB 成交金额 | WB 漏斗源成交金额 |
| `wb_buyout_rate` | WB 平台成交率 | WB buyouts / orders |
| `wb_cancel_amount` | WB 取消金额 | WB 漏斗源取消金额 |
| `wb_wishlist` | WB 收藏数 | WB 加入收藏数量 |
| `wb_stock` | WB 库存 | 当前周期最后一个有数据日的 WB 库存 |
| `wb_seller_stock` | WB 卖家库存 | 当前周期最后一个有数据日的 WB 卖家库存 |

## `profit.md` / `profit`：利润归集

此板块对应 SKU 详情页的“利润归集”。v3 返回按周 SKU 总览和店铺/Listing 明细，金额已统一为 CNY。费用字段如 `ads`、`goods_cost` 通常以正数费用额展示；利润、税额保留正负号。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `sku_profit_overview_per_week.metrics` | SKU 利润指标列表 | 跨平台、跨店铺汇总后的 SKU 周指标 |
| `sku_profit_overview_per_week.periods` | SKU 周利润总览 | 每个周期一行，`values` 按 `metrics` 存放汇总值 |
| `sku_profit_store_listing_perweek.metrics` | 店铺/Listing 利润指标列表 | 与 SKU 总览指标一致，但粒度为单店铺单 Listing |
| `sku_profit_store_listing_perweek.periods` | 周期定义 | 每个周期的 `period_key`、`period_from`、`period_to` |
| `sku_profit_store_listing_perweek.store_listings` | 店铺/Listing 分组 | 每个分组包含 `rows_per_week`，Markdown 通常会渲成表格 |
| `store_listings[].store_ref` | 平台账号引用 | 格式通常为 `wb:<账号ID>` 或 `ozon:<账号ID>` |
| `store_listings[].store_id` | ERP 店铺 ID | `Ec::Store` ID |
| `store_listings[].sku_product_id` | SKU 平台绑定 ID | `Ec::SkuProduct` ID，可能为空 |
| `store_listings[].platform` | 平台 | `wb` 或 `ozon` |
| `store_listings[].store_name` | 店铺名称 | ERP 内店铺展示名 |
| `store_listings[].listing_label` | Listing 标签 | 页面上的店铺商品标签 |
| `*.periods[].values` / `rows_per_week[].values` | 指标值 | 扁平指标字典；Markdown 表格中会展开为指标列 |

### 利润指标

| 指标 | 中文含义 | 说明 |
| --- | --- | --- |
| `net_sales` | 净销量 | 销售减退货后的件数 |
| `revenue` | 销售额 | 统一折算为 CNY 的收入 |
| `average_price` | 销售均价 | `revenue / net_sales` |
| `commission_fee` | 销售佣金 | 平台佣金，CNY |
| `payment_fee` | 支付手续费 | 平台支付/收单费用，CNY |
| `delivery_fee` | 物流费 | 正向发货物流费用，CNY |
| `return_delivery_fee` | 退货物流费 | 退货相关物流费用，CNY |
| `storage_fee` | 仓储费 | 平台仓储费用，CNY |
| `dispatch_fee` | 退件费 | 发货/退件处理费用，CNY |
| `packing_fee` | 包装费 | 包装费用，CNY |
| `defect_fee` | 瑕疵处理费 | 缺陷、损坏等平台费用，CNY |
| `crossdock_fee` | 越库费 | Cross-dock/中转费用，CNY |
| `other_platform_fee` | 其它平台费 | 其他已归属平台费用，CNY |
| `ads` | 广告费 | 已归属到该 SKU/Listing 的广告费用，CNY |
| `ad_ratio_pct` | 广告占比 | `ads / revenue * 100` |
| `goods_cost` | 货物成本 | 净销量对应货物成本，CNY |
| `cost_ratio_pct` | 成本占比 | `goods_cost / revenue * 100` |
| `pre_tax` | 税前利润 | 扣除平台费、广告费、货物成本后的税前利润，CNY |
| `tax` | 税费 | 税额影响，CNY；可能为负数 |
| `after_tax` | 净利润 | 税后净利，CNY |
| `profit_margin_pct` | 利润率 | `after_tax / revenue * 100` |
| `average_profit_per_order` | 平均每单利润 | `after_tax / net_sales` |
| `annualized_return_pct` | 年化收益率 | 按当前销售速度、成本和库存周转模型估算 |
| `annualized_net_profit_cny` | 年化净利 | 按模型年化后的预计净利润，CNY |

`annualized_return_pct` 和 `annualized_net_profit_cny` 为模型指标；缺成本、销量非正、缺体积或周转数据时可能为 `null`。

## `inventory.md` / `inventory`：库存

此板块只描述库存概况和库存趋势，不包含订单明细、送仓记录或运营日志。当前库存来自 SKU 库存详情页口径；历史趋势来自通用日快照，不会在 GET 请求中触发同步或写库。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `current_inventory_info.fields` | 当前库存字段列表 | `values` 中字段的展示顺序 |
| `current_inventory_info.values` | 当前库存值 | 以 `period.as_of` 对应日期为准的库存概览 |
| `current_inventory_info.forecast_explanation` | 简单预测说明 | SKU 详情页中普通预测日销的公式解释 |
| `current_inventory_info.strict_forecast` | 严谨预测详情 | 断货修正预测的输入、路径和结果；若有效观察日不足，预测日销可能为空 |
| `current_inventory_info.data_through` | 库存数据截至 | 最新平台库存同步时间 |
| `history_inventory_info.sku_inventory_trend` | SKU 周库存趋势 | 最近若干周的库存快照汇总，按周展示 |
| `history_inventory_info.store_listing_inventory_trend` | 店铺库存日趋势 | 店铺/Listing 级别近日期间库存走势 |

### 当前库存字段

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `incoming_quantity` | 采购中库存 | 已下单或在途、预计会进入账面的采购数量 |
| `book_stock` | 账面可用库存 | ERP 账面可用库存，来自批次、销售、退货、平台仓补正等汇总 |
| `platform_stock` | 平台在库 | 平台 FBO/FBW 仓库存合计 |
| `fbs_total_stock` | FBS 库存 | 可用于 FBS/海外仓履约的库存口径，详情页公式为账面可用减平台在库和平台在途等 |
| `daily_sales_velocity` | 预测日销 | 生命周期销量趋势口径，不剔除断货日 |
| `turnover_days` | 库存覆盖天数 | `book_stock / daily_sales_velocity` |
| `turnover_days_with_procurement` | 含采购库存覆盖天数 | `(book_stock + incoming_quantity) / daily_sales_velocity` |
| `platform_fbs_stock` | 平台 FBS 库存 | ERP 聚合的 FBS 库存 |
| `platform_reported_fbs_stock` | 平台上报 FBS 库存 | 优先取平台原始 FBS 数量，用于校对 ERP 聚合值 |
| `strict_forecast_daily_sales` | 严谨预测日销 | 剔除全平台断货日后的预测日销；无有效观察日时为空 |
| `strict_forecast_cover_days` | 严谨库存覆盖 | 按 `strict_forecast_daily_sales` 计算的覆盖天数 |

### 库存趋势字段

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `sku_inventory_trend.metrics` | 周趋势指标列表 | `book_stock`、`platform_stock`、`turnover_days_with_procurement`、`fbs_stock`、`platform_inbound_stock`、`incoming_quantity`、`daily_sales_velocity`、`turnover_days` |
| `sku_inventory_trend.available_metrics` | 可用周趋势指标 | 至少有一个周快照存在该指标时才会列入 |
| `sku_inventory_trend.weeks[].week_start` | 周开始日 | 自然周周一 |
| `sku_inventory_trend.weeks[].week_end` | 周结束日 | 自然周周日 |
| `sku_inventory_trend.weeks[].snapshot_date` | 使用的快照日期 | 优先使用周内最后一个有效快照；没有快照时为 `null` |
| `sku_inventory_trend.weeks[].is_week_end` | 是否周日快照 | `true` 表示刚好使用周日快照 |
| `sku_inventory_trend.weeks[].missing` | 是否缺快照 | `true` 表示该周没有可用库存快照 |
| `sku_inventory_trend.weeks[].values` | 周趋势指标值 | 按 `sku_inventory_trend.metrics` 存放 |
| `store_listing_inventory_trend.metrics` | 店铺日趋势指标列表 | `platform_stock`、`fbs_stock`、`platform_inbound_stock` |
| `store_listing_inventory_trend.from_date` / `to_date` | 店铺日趋势范围 | 通常为截至 `period.as_of` 的近 28 日 |
| `store_listing_inventory_trend.selected_store_key` | 默认选中店铺键 | 页面默认查看的店铺键 |
| `store_listing_inventory_trend.store_options` | 可选店铺列表 | `key` 为店铺键，`label` 为平台和店铺名 |
| `store_listing_inventory_trend.store_listings[].store_key` | 店铺键 | 由平台和店铺/账号身份组成 |
| `store_listing_inventory_trend.store_listings[].store_label` | 店铺标签 | 页面展示的店铺名 |
| `store_listing_inventory_trend.store_listings[].days[].date` | 日期 | 日趋势日期 |
| `store_listing_inventory_trend.store_listings[].days[].snapshot_date` | 快照日期 | 使用的库存快照日期 |
| `store_listing_inventory_trend.store_listings[].days[].missing` | 是否缺快照 | `true` 表示当天没有该店铺库存快照 |
| `store_listing_inventory_trend.store_listings[].days[].values` | 店铺库存值 | `platform_stock` 为 FBO/FBW，`fbs_stock` 为 FBS，`platform_inbound_stock` 为平台入库在途 |

## `lifecycle.md` / `lifecycle`：生命周期

此板块对应 SKU 详情页的“生命周期”。`summary` 是当前生命周期状态和累计表现；`key_events` 是时间线关键事件，不是完整运营日志。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `summary.fields` | 汇总字段列表 | `values` 中字段的展示顺序 |
| `summary.values` | 生命周期汇总值 | 当前 SKU 的生命周期、状态、累计销量利润和库存覆盖 |
| `key_events.sold` | 是否已成交 | `true` 表示已有首次成交事件或销量记录 |
| `key_events.data_started_on` | 完整可用数据始于 | 用于解释早期数据不完整的日期 |
| `key_events.events` | 关键事件 | 生命周期时间线节点，按时间排列 |

### 生命周期汇总字段

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `first_sale_at` | 首次成交 | SKU 首次成交时间；未成交时为 `null` |
| `lifecycle_days` | 生命周期天数 | 从首次成交到 `period.as_of` 的天数；未成交时通常为空 |
| `current_grade` | 当前营销等级 | 当前 Grade，如 `S`、`A`、`B`、`C` |
| `current_stage` | 当前营销阶段 | 当前 Stage，如 `NEW`、`GRW`、`MAT`、`CLR` |
| `net_sales` | 累计净销量 | 生命周期累计净销量 |
| `revenue` | 累计销售额 | 生命周期累计销售额，CNY |
| `net_profit` | 累计净利润 | 生命周期累计税后净利润，CNY |
| `daily_sales_velocity` | 预测日销 | 普通预测日销，不剔除断货日 |
| `inventory_cover_days` | 库存覆盖天数 | 按普通预测日销计算的库存覆盖 |
| `stockout_adjusted_daily_sales` | 断货修正预测日销 | 剔除全平台断货日后的预测日销 |
| `stockout_adjusted_inventory_cover_days` | 断货修正库存覆盖 | 按断货修正预测日销计算的覆盖天数 |

### 生命周期事件字段

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `events[].id` | 事件 ID | 生命周期事件记录 ID |
| `events[].event_type` | 事件类型 | 常见值：`first_sale`、`marketing_state_changed`、`purchase_ordered`、`purchase_received`、`profit_grade_reached`、`cumulative_profit_reached`、`replenishment`、`platform_stockout`、`all_platform_stockout`、`stock_recovered` |
| `events[].occurred_at` | 发生时间 | 事件时间，含时区 |
| `events[].occurred_on` | 发生日期 | 按响应时区折算后的日期 |
| `events[].source_type` | 来源类型 | 触发事件的业务对象类型 |
| `events[].source_id` | 来源 ID | 来源业务对象 ID |
| `events[].source_key` | 来源键 | 可读的来源唯一键，如订单号、批次号、送仓单号等 |
| `events[].sku_product_id` | SKU 平台绑定 ID | 与具体店铺 Listing 相关时有值 |
| `events[].content` | 事件内容 | 结构化事件内容；字段随事件类型变化 |
| `events[].duration_days` | 持续天数 | 对断货、恢复等持续型事件有意义 |
| `events[].details` | 展示详情 | 页面时间线使用的详情项，通常已带中文字段名 |

## `advertise_per_week.md` / `advertise_per_week`：逐周广告数据

结构为“自然周 -> 店铺 -> 平台商品”。第一版按 SKU、店铺和平台商品汇总，不展开单个广告活动。金额保留平台原币种，禁止跨币种直接加总。

历史数据直接读取 WB 和 Ozon 的广告日统计表，不根据广告当前状态过滤，也不要求广告与商品的当前关系仍有效。因此广告关闭、归档或移除商品后，已同步的历史统计仍会保留。`no_records` 只表示该周没有已记录的广告日统计。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `period_from` / `period_to` | 自然周范围 | 当前广告统计周 |
| `is_partial` | 是否非完整周期 | 默认请求完整自然周时通常为 `false` |
| `stores` | 店铺分组 | 当前 SKU 绑定的可用广告店铺 |
| `stores[].store_ref` | 平台账号引用 | 格式通常为 `wb:<账号ID>` 或 `ozon:<账号ID>` |
| `stores[].platform` | 平台 | `wb` 或 `ozon` |
| `stores[].store_id` | ERP 店铺 ID | `Ec::Store` ID |
| `stores[].store_name` | 店铺名称 | ERP 内店铺展示名 |
| `stores[].data_status` | 数据状态 | `available` 有记录，`no_records` 无记录，`unavailable` 源不可用 |
| `stores[].days_with_data` | 有数据天数 | 该周有广告日统计的日期数 |
| `stores[].data_through` | 广告数据截至 | 该店铺该周最新广告统计日期 |
| `stores[].data` | 平台商品广告汇总 | 每个绑定平台 SKU 一行 |
| `data[].sku_code` | 内部 SKU | 当前 SKU 编码 |
| `data[].platform_sku_id` | 平台 SKU ID | WB 使用 `nmId` 字符串，Ozon 使用 Ozon SKU ID |
| `data[].currency` | 币种 | Ozon 通常为 `RUB`；WB 若来源币种混杂可能为 `MIXED` |
| `data[].data_status` | 商品数据状态 | `available` 或 `no_records` |
| `data[].days_with_data` | 商品有数据天数 | 该商品有广告日统计的日期数 |
| `data[].data_through` | 商品数据截至 | 该商品最新广告统计日期 |

### 广告指标

| 指标 | 中文含义 | 说明 |
| --- | --- | --- |
| `impressions` | 曝光 | 广告曝光次数 |
| `clicks` | 点击 | 广告点击次数 |
| `cart_additions` | 加购 | 广告带来的加购次数 |
| `orders` | 订单数 | 广告归因订单数 |
| `ordered_units` | 下单件数 | 广告归因商品件数 |
| `canceled` | 取消 | 广告归因取消数 |
| `modeled_orders` | 模型订单数 | Ozon 模型归因订单数 |
| `spend` | 广告花费 | 平台原币种金额 |
| `attributed_revenue` | 归因收入 | 平台原币种金额 |
| `modeled_revenue` | 模型收入 | Ozon 模型归因收入 |
| `campaign_count` | 广告活动数 | WB campaign 或 Ozon ad unit 去重数量 |
| `avg_position` | 平均排名 | WB 广告平均位置；越小越靠前 |
| `ctr_pct` | 点击率 | `clicks / impressions * 100` |
| `cart_conversion_pct` | 点击到加购率 | `cart_additions / clicks * 100` |
| `cr_pct` | 点击到下单率 | `orders / clicks * 100` |
| `avg_cpc` | 平均点击成本 | `spend / clicks` |
| `cpo` | 单订单广告成本 | `spend / orders` |
| `drr_pct` | 广告费率 | `spend / attributed_revenue * 100` |
| `roas` | ROAS | `attributed_revenue / spend` |

## `ec_orders_full_period.md` / `ec_orders_full_period`：周期订单明细

此板块是请求周期内归属到当前 SKU 的订单商品明细。归属规则以 `ec_sku_products` 硬绑定为准：同一店铺、同一平台下，Ozon 按 `platform_sku_id` 匹配，WB 按 `product_id/nmId` 匹配。不要用 `ec_order_items.sku_code` 兜底判断归属。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `platform` | 平台 | `wb` 或 `ozon` |
| `store_id` | ERP 店铺 ID | `Ec::Store` ID |
| `store_name` | 店铺名称 | ERP 内店铺展示名 |
| `order_id` | ERP 订单 ID | 内部订单记录 ID |
| `order_key` | 订单键 | ERP 内唯一订单键 |
| `external_order_id` | 平台订单 ID | 平台侧订单 ID |
| `external_order_number` | 平台订单号 | 平台侧可读订单号 |
| `order_status` | ERP 订单状态 | 标准化状态，如已下单、已签收、取消、退货等 |
| `order_source_status` | 来源订单状态 | 平台原始状态 |
| `order_source_substatus` | 来源订单子状态 | 平台原始子状态 |
| `ordered_at` | 下单时间 | 按请求时区边界筛选 |
| `in_process_at` | 处理中时间 | 平台进入处理状态时间 |
| `order_completed_at` | 订单完成时间 | 订单完成或签收时间 |
| `order_cancelled_at` | 订单取消时间 | 订单取消时间 |
| `buyer_city` / `buyer_region` / `buyer_country` | 买家地区 | 买家城市、区域、国家 |
| `payment_method_source` | 支付方式来源 | 平台原始支付方式 |
| `is_legal_entity` | 是否法人买家 | `true` 表示法人/企业买家 |
| `order_synced_at` | 订单同步时间 | 订单记录最近同步时间 |
| `fulfillment_id` | ERP 履约 ID | 内部履约记录 ID |
| `external_fulfillment_id` | 平台履约 ID | 平台侧履约 ID |
| `fulfillment_key` | 履约键 | ERP 内唯一履约键 |
| `fulfillment_type` | 履约类型 | FBO、FBW、FBS 等平台履约口径 |
| `fulfillment_status` | ERP 履约状态 | 标准化履约状态 |
| `fulfillment_source_status` | 来源履约状态 | 平台原始履约状态 |
| `fulfillment_source_substatus` | 来源履约子状态 | 平台原始履约子状态 |
| `warehouse_external_id` | 平台仓库 ID | 平台侧仓库 ID |
| `warehouse_name` | 仓库名称 | 发货或履约仓库 |
| `delivery_method_name` | 配送方式 | 平台配送方式名称 |
| `delivery_type_source` | 配送类型来源 | 平台原始配送类型 |
| `cluster_from` / `cluster_to` | 发出/目的集群 | 平台履约集群或区域 |
| `tracking_number` | 物流单号 | 平台或物流商跟踪号 |
| `shipped_at` | 发货时间 | 履约发货时间 |
| `delivered_at` | 签收时间 | 履约签收时间 |
| `fulfillment_cancelled_at` | 履约取消时间 | 履约取消时间 |
| `cancel_reason_source` | 取消原因 | 平台原始取消原因 |
| `fulfillment_raw_source_type` / `fulfillment_raw_source_id` | 履约原始来源 | 便于追溯原始同步记录 |
| `fulfillment_synced_at` | 履约同步时间 | 履约记录最近同步时间 |
| `item_id` | ERP 订单商品 ID | 内部订单商品记录 ID |
| `external_item_id` | 平台商品行 ID | 平台侧商品行 ID |
| `sku_code` | 内部 SKU | 当前 SKU 编码 |
| `platform_sku_id` | 平台 SKU ID | 订单商品上的平台 SKU ID |
| `offer_id` | 商家货号 | 订单商品上的 offer/vendor code |
| `product_name_source` | 商品名来源 | 平台订单商品名称 |
| `quantity` | 件数 | 订单商品数量 |
| `currency_code` | 币种 | 价格字段币种 |
| `unit_price` | 单价 | 平台同步的商品单价 |
| `old_unit_price` | 原单价 | 优惠前或原始单价 |
| `discount_amount` | 折扣金额 | 平台商品行折扣额 |
| `discount_percent` | 折扣率 | 平台商品行折扣百分比 |
| `commission_amount` | 佣金金额 | 平台商品行佣金 |
| `commission_percent` | 佣金率 | 平台商品行佣金百分比 |
| `payout` | 预计结算 | 平台商品行预计结算额 |
| `buyer_paid_unit_price` | 买家支付单价 | Ozon 买家实际支付单价等补充价格 |
| `buyer_currency_code` | 买家支付币种 | 买家支付单价币种 |
| `buyer_paid_synced_at` | 买家支付价同步时间 | 补充价格最近同步时间 |
| `seller_discount_unit_price` | 卖家折扣单价 | 卖家承担折扣后的单价 |
| `seller_discount_currency_code` | 卖家折扣币种 | 卖家折扣单价币种 |
| `seller_discount_synced_at` | 卖家折扣价同步时间 | 补充价格最近同步时间 |
| `item_synced_at` | 商品行同步时间 | 订单商品记录最近同步时间 |

## `supply_orders_full_period.md` / `supply_orders_full_period`：周期送仓记录

此板块是请求周期内平台送仓/入仓单的明细行。WB 按送仓创建时间筛选，Ozon 按供货订单创建时间筛选；只返回能通过当前 SKU 平台绑定匹配到的商品行。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `platform` | 平台 | `wb` 或 `ozon` |
| `store_id` | ERP 店铺 ID | `Ec::Store` ID |
| `store_name` | 店铺名称 | ERP 内店铺展示名 |
| `supply_id` | 送仓/供货单 ID | 平台送仓单或供货单 ID |
| `status` | 状态 | 平台原始状态 ID 或状态码 |
| `platform_item_id` | 平台商品 ID | WB 为 `nmId`，Ozon 为平台 SKU ID |
| `sku_code` | 内部 SKU | 当前 SKU 编码 |
| `product_name` | 商品名 | ERP SKU 商品名 |
| `quantity` | 计划数量 | 该商品行计划送仓数量 |
| `created_at` | 创建时间 | 平台送仓/供货单创建时间 |
| `synced_at` | 同步时间 | 商品行最近同步时间 |

### WB 送仓字段

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `preorder_id` | 预订单 ID | WB 预订单号 |
| `accepted_quantity` | 已接受数量 | WB 已接受商品数量 |
| `remaining_quantity` | 剩余数量 | `quantity - accepted_quantity`，不小于 0 |
| `warehouse_name` | 计划仓库 | WB 送仓单仓库 |
| `actual_warehouse_name` | 实际仓库 | 实际入仓仓库 |
| `transit_warehouse_name` | 中转仓库 | 中转仓信息 |
| `scheduled_at` | 预约时间 | 送仓预约时间 |
| `actual_at` | 实际时间 | 实际送达或处理时间 |
| `packaging` | 包装类型 | WB 包装类型 ID |
| `pallet` | 是否上托 | `true` 表示箱子在托盘上 |
| `acceptance_cost` | 接收费 | WB 接收费 |
| `paid_acceptance_coefficient` | 付费接收系数 | WB 付费接收系数 |
| `storage_coefficient` | 仓储系数 | WB 仓储费系数 |
| `delivery_coefficient` | 配送系数 | WB 配送费系数 |
| `supplier_assign_name` | 供应商分配名 | WB 返回的供应商/承运分配信息 |
| `reject_reason` | 拒收原因 | WB 拒收或异常原因 |
| `supply_quantity` | 单据总数量 | 送仓单总数量 |
| `supply_accepted_quantity` | 单据已接受数量 | 送仓单维度已接受数量 |
| `ready_for_sale_quantity` | 可售数量 | 已可售数量 |
| `unloading_quantity` | 卸货中数量 | 卸货中数量 |
| `depersonalized_quantity` | 去标识数量 | WB 返回的 depersonalized 数量 |
| `can_show_quantity` | 可展示数量 | WB 返回的可展示数量 |

### Ozon 供货字段

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `order_number` | 供货单号 | Ozon 可读供货单号 |
| `destination_cluster` | 目的集群 | Ozon 目的宏区域/集群 |
| `destination_warehouse` | 目的仓 | Ozon 目的仓名称 |
| `timeslot` | 预约时段 | Ozon 入仓预约时段 |
| `origin_warehouse` | 发出仓 | Drop-off 仓库名称 |
| `state_updated_at` | 状态更新时间 | Ozon 供货单状态最近更新时间 |

## `operation_actions_full_period.md` / `operation_actions_full_period`：周期运营记录

此板块是请求周期内当前 SKU 的运营动作日志，按 `operated_at`、`action_id` 升序排列。它不是指标汇总，也不是因果诊断结果。分析效果时必须结合动作时间、销售漏斗、利润、库存和同期其他动作，不能把动作后的指标变化直接归因给单个动作。

v3 Markdown 会把此文件整体渲染为日志表，核心列包含动作 ID、时间、类型、平台、店铺、Listing、操作人、系统/人工标记和 `diff_summary`。JSON 额外保留完整 `diff_result`。v3 默认排除 `sku_inbound_change`，因为平台在途已归入库存和送仓上下文。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `action_id` | 动作 ID | 运营记录 ID |
| `operated_at` | 变更时间 | 操作发生时间 |
| `operation_type` | 变更类型 | 机器可读类型 |
| `operation_type_label` | 变更类型中文 | 页面展示文案 |
| `record_by_system` | 是否系统记录 | `true` 为系统自动记录，`false` 通常为人工记录 |
| `platform` | 平台 | `wb` 或 `ozon` |
| `store_id` | ERP 店铺 ID | `Ec::Store` ID |
| `store_name` | 店铺名称 | ERP 内店铺展示名 |
| `sku_code` | 内部 SKU | 当前 SKU 编码 |
| `sku_product_id` | SKU 平台绑定 ID | `Ec::SkuProduct` ID |
| `platform_product_id` | 平台商品 ID | WB 为 `nmId`；Ozon 为商品 ID |
| `platform_sku_id` | 平台 SKU ID | Ozon 常用；WB 可能为空或与商品 ID 口径不同 |
| `offer_id` | 商家货号 | 平台侧 offer/vendor code |
| `operated_by_user_id` | 操作人 ID | 系统或用户 ID |
| `operated_by_user_name` | 操作人 | 页面展示名 |
| `diff_summary` | 变更摘要 | 已格式化的人类可读差异，适合直接读日志 |
| `diff_result` | 完整变更明细 | JSON 中可用；字段随 `operation_type` 变化，Markdown 中通常省略 |

常见 `operation_type`：

| 类型 | 中文含义 | 说明 |
| --- | --- | --- |
| `listing_content` | 内容 | 标题、描述、图片、类目等 Listing 内容变化 |
| `listing_pricing` | 价格 | 价格、折扣、收单费等变化 |
| `listing_specification` | 规格 | 尺寸、重量、属性等规格变化 |
| `manual_note` | 人工记录 | 人工补充的运营备注 |
| `sku_adv_on_off` | 广告开关 | 广告启用状态变化 |
| `sku_adv_budget` | 广告预算 | 广告预算变化 |
| `supply_order` | 送仓记录 | 送仓相关事件 |

## `warehouse_recommendation.md` / `warehouse_recommendation`：分仓建议

此板块用于判断各平台店铺的库存分布是否覆盖销售区域。销售来源为请求周期内 `ec_orders.ordered_at`，库存来源为平台仓/区域库存报表。它不是采购计划，也不会直接等于应补货量。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `sales_period.from` / `sales_period.to` | 销售统计期 | 与请求周期一致 |
| `sales_period.days` | 统计天数 | 周期总天数 |
| `sales_period.source` | 销售来源 | 当前为 `ec_orders.ordered_at` |
| `target_days` | 目标覆盖天数 | 分仓建议希望覆盖的销售天数 |
| `stores` | 店铺分仓结果 | 当前 SKU 绑定且有可用平台账号的 WB/Ozon 店铺 |
| `stores[].store_ref` | 平台账号引用 | 格式通常为 `wb:<账号ID>` 或 `ozon:<账号ID>` |
| `stores[].platform` | 平台 | `wb` 或 `ozon` |
| `stores[].store_id` | ERP 店铺 ID | `Ec::Store` ID |
| `stores[].store_name` | 店铺名称 | ERP 内店铺展示名 |
| `stores[].data_status` | 数据状态 | `available` 有销售/库存建议行，`no_records` 无 SKU 行，`unavailable` 源不可用 |
| `stores[].inventory_synced_at` | 库存同步时间 | 分仓建议使用的库存数据更新时间 |
| `stores[].summary` | 店铺汇总 | 当前 SKU 在该店铺的销量、库存和建议汇总 |
| `stores[].sales_clusters` | 销售区域明细 | 按平台区域/集群拆分的销售和库存覆盖 |
| `stores[].reason` | 不可用原因 | `data_status` 为 `unavailable` 时出现 |

### 分仓汇总与区域字段

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `status` | 状态 | 平台查询给出的建议状态 |
| `sales_quantity` | 销量 | 统计期内匹配到该区域/店铺的销量 |
| `sales_share_pct` | 销售占比 | 区域销量占店铺 SKU 销量百分比，仅区域明细有 |
| `daily_sales` | 日均销量 | `sales_quantity / sales_period.days` |
| `days_of_stock` | 库存覆盖天数 | 当前可用库存可覆盖的天数 |
| `available` | 可售库存 | 平台仓可售数量 |
| `reserved` | 预留库存 | 平台已预留但未完成履约库存 |
| `inbound` | 在途库存 | 平台入库在途数量 |
| `fbs_available` | FBS 可用库存 | 店铺汇总中的 FBS 可用库存 |
| `recommended` | 建议量 | 按目标覆盖天数计算的建议库存量 |
| `distribution_gap` | 分布缺口 | 建议量与当前区域可用/在途之间的缺口 |
| `mapped_orders` | 已映射订单数 | 成功映射到区域/集群的订单数 |
| `total_orders` | 总订单数 | 统计期订单总数 |
| `mapping_coverage` | 映射覆盖率 | `mapped_orders / total_orders` |
| `receiving_warehouse_count` | 接收仓数量 | 区域内可接收仓数量 |
| `warehouses` | 仓库库存 | 区域下仓库级库存明细 |
| `warehouses[].warehouse_name` | 仓库名称 | 平台仓名称 |
| `warehouses[].warehouse_id` | 仓库 ID | 平台仓 ID |
| `warehouses[].cluster_name` | 所属集群 | 平台区域/集群名称 |
| `warehouses[].available` | 可售库存 | 仓库可售数量 |
| `warehouses[].reserved` | 预留库存 | 仓库预留库存 |
| `warehouses[].inbound` | 在途库存 | 仓库入库在途库存 |

## `search_terms_per_week.md` / `search_terms_per_week`：逐周搜索词

结构为“自然周 -> 店铺 -> 搜索词行”。搜索词来自平台搜索词报表，通常用于判断曝光、点击、转化和排名，不代表自然搜索全量，也不等同于广告关键词。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `period_from` / `period_to` | 自然周范围 | 当前搜索词统计周 |
| `is_partial` | 是否非完整周期 | 默认请求完整自然周时通常为 `false` |
| `stores` | 店铺分组 | 当前 SKU 绑定且有搜索词来源的店铺 |
| `stores[].store_ref` | 平台账号引用 | 格式通常为 `wb:<账号ID>` 或 `ozon:<账号ID>` |
| `stores[].platform` | 平台 | `wb` 或 `ozon` |
| `stores[].store_id` | ERP 店铺 ID | `Ec::Store` ID |
| `stores[].store_name` | 店铺名称 | ERP 内店铺展示名 |
| `stores[].data_status` | 数据状态 | `available` 有记录，`no_records` 无记录，`unavailable` 源不可用 |
| `stores[].data` | 搜索词明细 | 字段随平台搜索词报表变化；通常每行一个搜索词或查询词 |

### 常见搜索词指标

| 指标 | 中文含义 | 说明 |
| --- | --- | --- |
| `query` / `search_term` / `text` | 搜索词 | 平台返回的查询词文本 |
| `sku_code` | 内部 SKU | 当前 SKU 编码；v3 输出中店铺行可能已移除嵌套 SKU 对象 |
| `platform_sku_id` / `nm_id` | 平台商品 ID | Ozon SKU ID 或 WB `nmId` |
| `search_volume` | 搜索量 | 平台搜索词报表中的搜索量 |
| `views` | 展示/浏览 | 搜索词带来的商品展示或浏览 |
| `clicks` | 点击 | 搜索词带来的点击 |
| `add_to_cart` / `cart_additions` | 加购 | 搜索词带来的加购 |
| `orders` | 订单 | 搜索词归因订单 |
| `revenue` | 收入 | 搜索词归因收入，保留平台原币种 |
| `avg_position` / `median_position` | 排名 | 平均或中位排名；数值越小越靠前 |
| `conversion` / `conversion_pct` | 转化率 | 搜索词口径转化率 |
| `visibility` | 可见度 | 平台搜索可见度指标 |

搜索词报表字段在不同平台和同步版本间可能增减。遇到本文未列出的搜索词字段时，优先按字段名、店铺平台和页面“搜索词”报表含义理解，避免与广告字段混用。
