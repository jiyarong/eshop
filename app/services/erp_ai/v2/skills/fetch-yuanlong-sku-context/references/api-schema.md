# SKU 完整上下文 API 字段说明

本文档用于解释 `fetch-yuanlong-sku-context` 获取的数据。字段中文名称优先采用辕隆 ERP 页面中的中文文案；分析数据时仍以接口字段名和本文口径为准。

## 请求

```http
GET /ai/v2/skus/full_context?sku_code=<SKU>&period_from=<MONDAY>&period_to=<SUNDAY>
Authorization: Bearer <assigned_user_api_key>
Accept: application/json
```

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `sku_code` | 是 | 内部 SKU 编码，不区分输入大小写 |
| `period_from` | 否 | 查询周期开始日；传入时必须是周一，并与 `period_to` 同时传入 |
| `period_to` | 否 | 查询周期结束日；传入时必须是周日，并与 `period_from` 同时传入 |

错误状态：`400` 表示参数缺失，`401` 表示鉴权失败，`404` 表示 SKU 不存在，`422` 表示日期格式或自然周边界无效。

## 响应结构

```json
{
  "data": {
    "sku_code": "SKU001",
    "period": { "from": "2026-08-24", "to": "2026-09-20" },
    "context": {}
  }
}
```

| 字段 | 说明 |
| --- | --- |
| `data.sku_code` | 标准化后的内部 SKU 编码 |
| `data.period.from` | 本次上下文周期开始日 |
| `data.period.to` | 本次上下文周期结束日 |
| `data.context` | SKU 上下文，包含基础信息、逐周利润、逐周销售漏斗、逐周广告、逐周搜索词、周期订单、周期送仓、周期运营记录和库存 |

金额为 `null` 表示缺少计算所需的数据，不能按 `0` 解读。空数组表示系统在该查询范围内没有已记录明细，不能据此断言业务事件从未发生。

## `base`：SKU 基础信息

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `spu_code` | SPU 编码 | 当前 SKU 所属的 SPU；未归属时为 `null` |
| `spu_id` | SPU ID | SPU 数据库 ID；未归属时为 `null` |
| `related_spu_sku_codes` | 同 SPU 关联 SKU | 同一 SPU 下除当前 SKU 外的其他 SKU 编码 |
| `current_stage` | 当前营销阶段 | 常见值：`NEW` 新品、`GRW` 成长、`MAT` 成熟、`CLR` 清仓 |
| `current_grade` | 当前营销等级 | 常见值：`S`、`A`、`B`、`C` |
| `sku_products` | 平台商品绑定 | 当前 SKU 在各店铺的平台商品绑定列表 |
| `sku_products[].store_id` | 店铺 ID | `Ec::Store` ID |
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

## `weekly_profit_per_week`：逐周利润归集

此板块包含 `wr`、`wsu`、`wsu_deep` 三种口径。每项按已结束的自然周输出 `period_from`、`period_to`。为排除尚未结束的本周，利润窗口会相对请求周期整体向前移动一周。

### 三种归集口径

| 口径 | 页面中文 | 粒度与用途 |
| --- | --- | --- |
| `wr` | SKU 明细 | 按自然周、店铺、平台原生利润行展示。WB 与 Ozon 字段、币种和费用符号不同，适合核对平台原始归集 |
| `wsu` | 周汇总明细 | 按 SKU、平台、店铺归集，并统一折算为 CNY，适合比较各店铺利润表现 |
| `wsu_deep` | SKU 深度汇总 | 跨平台、跨店铺汇总到 SKU，并补充单均利润、广告占比和 180 天备货 ROI，适合经营判断 |

通用周期和店铺字段：

| 字段 | 说明 |
| --- | --- |
| `period_from` / `period_to` | 该利润行对应的完整自然周 |
| `wr[].stores[].store_ref` | 店铺引用，格式为 `wb:<账号ID>` 或 `ozon:<账号ID>` |
| `wr[].stores[].platform` | 平台：`wb` 或 `ozon` |
| `wr[].stores[].store_id` | 店铺引用中的平台账号 ID；不是 `Ec::Store` ID |
| `wr[].stores[].store_name` | 页面展示的店铺名称 |
| `wr[].stores[].data` | 当前店铺、当前自然周的 WR SKU 明细 |
| `wsu[].data` | 当前自然周的 WSU 店铺归集行 |
| `wsu_deep[].data` | 当前自然周的 WSU-DEEP SKU 汇总行 |

### WR：WB 字段

WB WR 金额除 `import_vat` 外统一为 BYN。费用字段多以正数展示，再按利润公式扣减。

| 字段 | 页面中文/含义 | 口径 |
| --- | --- | --- |
| `nm_id` | nmId | WB 商品 ID |
| `vendor_code` | 品号 | 内部 SKU/商家货号 |
| `report_type` | 报表区域类型 | 内部区域类型标识；业务含义以 `region` 为准 |
| `region` | 区域 | `白俄` 或 `出口` |
| `sales_qty` | 销售件数 | 周内销售件数 |
| `return_qty` | 退货件数 | 周内退货件数 |
| `net_qty` | 净销量 | `sales_qty - return_qty` |
| `retail_amount` | 零售金额 | WB 财务明细中的零售金额，BYN |
| `import_vat` | 单件进口增值税 | 展示值保留 CNY；税务计算时会折算为 BYN |
| `settlement` | 结算额 | WB 应结算金额，BYN |
| `acquiring` | 收单手续费 | 展示用内部调整项；当前不单独进入 `net` 公式 |
| `delivery` | 配送费 | 配送费用，BYN |
| `reimb` | 补偿/赔付 | 展示用内部调整项；当前不单独进入 `net` 公式 |
| `logistics_reimb` | 物流补偿 | 展示用物流补偿项；当前不单独进入 `net` 公式 |
| `pickup` | 取件费 | 展示用内部调整项；当前不单独进入 `net` 公式 |
| `penalty` | 罚款 | 展示用内部调整项；当前不单独进入 `net` 公式 |
| `storage` | 仓储费 | RUB 原始仓储费折算为 BYN |
| `ad` | 广告费 | 广告费用，BYN |
| `net` | 账面小计 | `settlement - delivery - storage - ad` |
| `tax_base` | 税基 | WB 税务计算基础，BYN |
| `goods_cost` | 货物成本 | `net_qty × 单件货物成本`，从 CNY 折算为 BYN |
| `pre_tax` | 税前利润 | `net - goods_cost` |
| `tax` | 税额 | 按店铺税制计算；一般税制考虑销项税和进口增值税，可能为负数 |
| `after_tax` | 税后净利 | `pre_tax - tax` |

### WR：Ozon 字段

Ozon WR 金额默认使用 RUB；`cost_cny`、`import_vat_cny` 明确使用 CNY。平台费用和成本通常以负数输出，正负号可直接参与加总。

| 字段 | 页面中文/含义 | 口径 |
| --- | --- | --- |
| `ozon_sku_id` | SKU | Ozon 平台 SKU ID |
| `sku_code` | 品号 | 内部 SKU 编码 |
| `sales_revenue` | 销售收入 | 商品销售收入，RUB |
| `commission` | 平台佣金 | Ozon 佣金，通常为负数 |
| `delivery_charge` | 物流费 | 配送及物流费用，通常为负数 |
| `payment_fee` | 支付手续费 | 支付处理费用，通常为负数 |
| `dispatch_fee` | 发货处理费 | 发货/处理费用，通常为负数 |
| `packing_fee` | 包装费 | 包装费用，通常为负数 |
| `return_delivery` | 退货物流费 | 退货产生的物流费用，通常为负数 |
| `storage_fee` | 仓储费 | Ozon 仓储费用，通常为负数 |
| `defect_fee` | 缺陷/损坏费用 | 商品缺陷或损坏相关费用，通常为负数 |
| `crossdock_fee` | 越库费用 | Cross-dock 费用，通常为负数 |
| `other_fee` | 其他费用 | 其他已归集平台费用，通常为负数 |
| `order_count` | 订单数 | 归集到该 SKU 的销售订单数 |
| `return_count` | 退货数 | 归集到该 SKU 的退货数 |
| `net_sales_count` | 净销量 | 销售订单扣除退货后的归集结果 |
| `ppc_cost` | PPC 广告费 | PPC 广告费用，负数 |
| `promotion_cost` | 推广费 | Promotion 推广费用，负数 |
| `total_ad_cost` | 广告费 | `ppc_cost + promotion_cost`，负数 |
| `blr_sale` | 白俄销售额 | 白俄罗斯目的地订单销售额，RUB |
| `blr_count` | 白俄订单数 | 白俄罗斯目的地净订单数 |
| `export_count` | 出口订单数 | 非白俄罗斯目的地净订单数 |
| `cost_cny` | 单件货物成本 | 单件货物成本，CNY |
| `import_vat_cny` | 单件进口增值税 | 单件进口增值税，CNY |
| `goods_cost` | 货物成本 | 净销量对应的货物成本，折算为 RUB 后以负数输出 |
| `blr_tax` | 白俄税额 | 白俄罗斯销售税影响，通常为负数 |
| `export_refund` | 出口退税 | 出口订单的进口增值税退税；退货冲回时可能为负数 |
| `book_profit` | 广告前账面利润 | 销售收入加上所有负的平台费用 |
| `book_profit_after_ad` | 广告后账面利润 | `book_profit + total_ad_cost`；`total_ad_cost` 在输出中为负数 |
| `pre_tax_profit` | 税前毛利 | `book_profit_after_ad + goods_cost`；`goods_cost` 为负数 |
| `after_tax_profit` | 税后净利 | `pre_tax_profit + blr_tax + export_refund` |
| `after_tax_margin_pct` | 税后利润率 | `after_tax_profit / sales_revenue × 100%` |

### WSU：按平台与店铺统一归集

WSU 将 WB 的 BYN 和 Ozon 的 RUB 统一折算为 CNY。`ads`、`goods_cost` 是正数费用额；`pre_tax`、`tax`、`after_tax` 保留利润或税额的正负号。

| 字段 | 页面中文 | 口径 |
| --- | --- | --- |
| `sku` | SKU | 内部 SKU 编码 |
| `platform` | 平台 | `WB` 或 `Ozon` |
| `shop` | 店铺 | 平台账号/店铺名称 |
| `net_sales` | 净销量 | 销售减退货后的件数 |
| `revenue` | 销售额 | WB 取 `settlement`，Ozon 取 `sales_revenue`，统一折算为 CNY |
| `ads` | 广告费 | 统一为正数费用额，CNY |
| `goods_cost` | 货物成本 | 统一为正数费用额，CNY |
| `pre_tax` | 税前毛利 | 统一折算后的税前利润，CNY |
| `tax` | 税额 | `pre_tax - after_tax`，CNY；可能为负数 |
| `after_tax` | 税后净利 | 统一折算后的税后利润，CNY |
| `margin_pct` | 利润率 | `after_tax / revenue × 100%` |

未能可靠归属到 SKU 的费用不进入单个 WSU 行，而进入报表的“未分摊费用”。因此汇总判断时需区分 SKU 行税后净利与“含未分摊税后净利”。当前完整上下文只返回 SKU 行，不返回比较数据和汇总卡片。

### WSU-DEEP：跨平台 SKU 深度汇总

WSU-DEEP 将同一 SKU 在所有平台和店铺的 WSU 行合并，金额均为 CNY。

| 字段 | 页面中文 | 口径 |
| --- | --- | --- |
| `sku` | SKU | 内部 SKU 编码 |
| `net_sales` | 净销量 | 跨平台、跨店铺净销量合计 |
| `revenue` | 销售额 | 跨平台、跨店铺销售额合计 |
| `ads` | 广告费 | 跨平台、跨店铺广告费合计 |
| `goods_cost` | 货物成本 | 跨平台、跨店铺货物成本合计 |
| `pre_tax` | 税前毛利 | 跨平台、跨店铺税前利润合计 |
| `tax` | 税额 | 跨平台、跨店铺税额合计 |
| `after_tax` | 税后净利 | 跨平台、跨店铺税后净利合计 |
| `margin_pct` | 利润率 | `after_tax / revenue × 100%` |
| `average_profit_per_order` | 平均每单利润 | `after_tax / net_sales` |
| `ad_ratio_pct` | 广告占比 | `ads / revenue × 100%` |
| `cost_return_pct` | 成本回报率 | `after_tax / goods_cost × 100%` |
| `projected_roi_pct` | ROI（按 180 天备货） | 按当前日均净销量推演 180 天备货量，以预计经营净利扣除仓储资金占用和利息后除以货物成本基数 |
| `annualized_return_pct` | 年化收益率 | 将 180 天备货模型的 ROI 按预计清货周期年化 |
| `annualized_net_profit_cny` | 年化净利 | 180 天备货模型调整后经营净利按预计清货周期年化，CNY |

ROI 字段为 `null` 时，常见原因是净销量非正、缺少单件成本或缺少商品体积，不能按零收益解读。

## `advertise_per_week`：逐周广告数据

结构为“自然周 -> 店铺 -> 平台商品”。第一版按 SKU、店铺和平台商品汇总，不展开单个广告活动。金额保留平台原币种，禁止跨币种直接加总。

历史数据直接读取 WB 和 Ozon 的广告日统计表，不根据广告当前状态过滤，也不要求广告与商品的当前关系仍有效。因此广告关闭、归档或移除商品后，已同步的前三周数据仍会保留。`no_records` 只表示该周没有已记录的广告日统计，不能断言从未投放。

Ozon 同一个广告单元、商品和日期可能同时存在 `cpc` 与 `cpc_history`。接口优先采用 `cpc_history`，没有时才使用 `cpc`，避免同一天 CPC 数据重复计算；其他计费模式正常参与汇总。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `period_from` / `period_to` | 自然周范围 | 周一至周日，使用请求周期 |
| `is_partial` | 是否未完整 | 周结束日晚于用户时区当天时为 `true` |
| `stores[].store_ref` | 店铺引用 | 格式为 `wb:<账号ID>` 或 `ozon:<账号ID>` |
| `stores[].platform` | 平台 | `wb` 或 `ozon` |
| `stores[].store_id` | ERP 店铺 ID | `Ec::Store` ID |
| `stores[].store_name` | 店铺名称 | ERP 页面展示名称 |
| `stores[].data_status` | 店铺数据状态 | 至少一个商品有记录时为 `available`，否则为 `no_records` |
| `stores[].days_with_data` | 有数据天数 | 该店铺本周有广告统计的去重日期数 |
| `stores[].data_through` | 数据截至日 | 本周最近一条广告日统计日期；无记录时为 `null` |
| `stores[].data` | 商品广告数据 | 每个平台商品一行，即使无记录也保留该行 |

### 商品广告指标

| 字段 | 页面中文/含义 | 口径 |
| --- | --- | --- |
| `sku_code` | SKU | 内部 SKU 编码 |
| `platform_sku_id` | 平台商品 ID | WB 为 `nmId`，Ozon 为平台 SKU ID |
| `currency` | 币种 | WB 取原始统计币种；Ozon 当前为 `RUB`；`MIXED` 表示 WB 周内出现多个币种 |
| `data_status` | 数据状态 | `available` 表示本周有统计，`no_records` 表示无已记录统计 |
| `days_with_data` | 有数据天数 | 当前商品本周有统计的去重日期数 |
| `data_through` | 数据截至日 | 当前商品本周最近统计日期；无记录时为 `null` |
| `impressions` | 曝光量 | 广告展示次数 |
| `clicks` | 点击量 | 广告点击次数 |
| `cart_additions` | 加购数 | 广告归因的加购次数 |
| `orders` | 订单数 | 广告归因订单数 |
| `ordered_units` | 下单件数 | WB 使用广告下单件数；Ozon 当前与广告订单数一致 |
| `canceled` | 取消数 | WB 广告归因取消数；Ozon 当前数据源不提供，返回 `0` |
| `modeled_orders` | 模型归因订单数 | Ozon 模型归因订单；WB 当前数据源不提供，返回 `0` |
| `spend` | 广告花费 | 平台原币种的广告支出 |
| `attributed_revenue` | 广告归因销售额 | 平台直接归因的销售额，使用 `currency` 标示币种 |
| `modeled_revenue` | 模型归因销售额 | Ozon 模型归因销售额；WB 当前数据源不提供，返回 `0` |
| `avg_position` | 平均广告位置 | WB 周内日均位置的算术平均；数值越小通常越靠前；Ozon 当前为 `null` |
| `campaign_count` | 广告活动数 | 本周产生统计的去重 WB 广告活动或 Ozon 广告单元数量 |
| `ctr_pct` | 点击率（CTR） | `clicks / impressions × 100%` |
| `cart_conversion_pct` | 点击加购率 | `cart_additions / clicks × 100%` |
| `cr_pct` | 点击下单率（CR） | `orders / clicks × 100%` |
| `avg_cpc` | 平均点击成本 | `spend / clicks`，平台原币种 |
| `cpo` | 平均订单成本 | `spend / orders`，平台原币种 |
| `drr_pct` | 广告费率（DRR） | `spend / attributed_revenue × 100%` |
| `roas` | 广告投入产出比 | `attributed_revenue / spend` |

比率分母为零时返回 `null`，避免把不可计算误读为零。`is_partial` 与 `days_with_data` 应一起判断：当前周可能尚未结束，历史完整周也可能因平台同步缺日而数据不完整。

## `sales_funnel_per_week`：逐周销售漏斗

结构为“自然周 -> 店铺 -> SKU 数据行”。它使用请求周期，不像利润板块那样向前移动一周。当前自然周的数据仅统计到最近同步日，未来日期没有数据，因此不能直接与完整自然周等长比较。

| 字段 | 说明 |
| --- | --- |
| `period_from` / `period_to` | 漏斗自然周范围 |
| `stores[].store_ref` | 店铺引用，格式为 `wb:<账号ID>` 或 `ozon:<账号ID>` |
| `stores[].platform` | `wb` 或 `ozon` |
| `stores[].store_id` | 店铺引用中的平台账号 ID；不是 `Ec::Store` ID |
| `stores[].store_name` | 页面展示店铺名称 |
| `stores[].data` | 当前店铺、当前自然周、当前 SKU 的漏斗数据；无记录时为空数组 |

### WB 漏斗字段

| 字段 | 页面中文 | 口径 |
| --- | --- | --- |
| `sku_code` | SKU | 内部 SKU 编码；未匹配绑定时可能退化为平台商品 ID |
| `product_name` | 商品名 | 内部 SKU 商品名称；未匹配绑定时为 `null` |
| `open_card` | 打开商品卡 | 商品卡打开次数 |
| `add_to_cart` | 加购数 | 加入购物车次数 |
| `conv_to_cart` | 加购转化率 | `add_to_cart / open_card × 100%` |
| `cart_to_order` | 加购下单率 | `orders / add_to_cart × 100%` |
| `orders` | 下单数 | 下单件数/数量 |
| `orders_sum` | 下单金额 | 下单金额 |
| `buyouts` | 成交数 | 完成成交/买断数量 |
| `buyouts_sum` | 成交金额 | 完成成交金额 |
| `buyout_percent` | 成交率 | `buyouts / orders × 100%` |
| `cancel_count` | 取消数 | 取消数量 |
| `cancel_sum` | 取消金额 | 取消金额 |
| `add_to_wishlist` | 收藏数 | 加入收藏/愿望单次数 |
| `stock_wb` | WB 库存 | 周末最近同步记录中的 WB 仓库存 |
| `stock_mp` | 卖家库存 | 周末最近同步记录中的卖家仓库存 |

### Ozon 漏斗字段

Ozon 字段沿用平台统计语义。`hits_view` 是总曝光，不等同于访问人数；`hits_view_pdp` 才是详情页访问。

| 字段 | 页面中文 | 口径 |
| --- | --- | --- |
| `sku_code` | SKU | 内部 SKU 编码；未匹配绑定时可能退化为平台 SKU ID |
| `product_name` | 商品名称 | 内部 SKU 商品名称；未匹配绑定时为 `null` |
| `hits_view` | 总曝光量 | 平台总展示次数 |
| `hits_view_search` | 搜索/目录曝光 | 搜索和类目列表中的展示次数 |
| `hits_view_pdp` | 详情页访问 | 商品详情页访问次数 |
| `session_view` | 访问人数 | 唯一身份访问者总计 |
| `hits_tocart` | 加购数 | 添加至购物车总计 |
| `hits_tocart_search` | 搜索/目录加购 | 从搜索或目录直接加购的次数 |
| `hits_tocart_pdp` | 详情页加购 | 从详情页加购的次数 |
| `search_to_card_conversion` | 点击率（CTR） | `hits_view_pdp / hits_view_search × 100%` |
| `conv_tocart` | 详情页加购率 | `hits_tocart_pdp / hits_view_pdp × 100%` |
| `cart_to_order` | 加购到下单转化率 | `ordered_units / hits_tocart_pdp × 100%` |
| `order_conversion` | 下单转化率（CR） | `ordered_units / hits_view × 100%` |
| `average_price` | 平均售价 | `revenue / ordered_units`；无下单时为 `null` |
| `ordered_units` | 下单件数 | 已订购商品件数 |
| `delivered_units` | 已妥投/签收数 | 已完成妥投或签收的商品件数 |
| `revenue` | 下单总金额 | 订购金额 |
| `total_drr` | 广告花费占比（DPP） | 同期广告花费 / 下单总金额 × 100%；无广告映射时为 `null` |
| `returns_count` | 退货数 | 按订单日期归集的退货商品数 |
| `cancellations` | 取消数 | 按订单日期归集的取消商品数 |
| `position_category` | 平均搜索排名 | 周内平台类目/搜索排名的平均值；数值越小通常排名越靠前 |
| `total_ending_inventory` | 期末总库存 | 周末该 SKU 所有店铺的期末平台库存 |
| `store_ending_inventory` | 店铺期末库存 | 周末当前店铺的期末平台库存 |

## `ec_orders_full_period`：周期订单明细

返回请求周期内归属当前 SKU 的订单商品明细，一条 `ec_order_items` 记录对应一行。同一订单有 N 条匹配当前 SKU 的 item，就返回 N 行；订单与履约字段会随 item 展开，便于直接生成 Markdown 表格。

SKU 归属不使用 `ec_order_items.sku_code` 兜底，而是严格使用商品绑定：店铺和平台必须一致，Ozon 使用 `ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id`，WB 使用 `ec_sku_products.product_id = ec_order_items.platform_sku_id`。因此订单中属于其他 SKU 的 item 不会混入结果。日期按 API 用户时区，以 `ec_orders.ordered_at` 落入请求周期为准。

三个表共有的 `platform`、`store_id` 只返回一次。同名但语义不同的状态、同步时间和取消时间使用 `order_*`、`fulfillment_*`、`item_*` 前缀区分。原始嵌套 JSON `source_payload`、`item_payload` 以及数据库维护字段 `created_at`、`updated_at` 不返回，避免重复平台原文使上下文过大。

### 公共与订单字段

| 字段 | 中文含义 | 来源/说明 |
| --- | --- | --- |
| `platform` | 平台 | `ec_order_items.platform`，`wb` 或 `ozon` |
| `store_id` | 店铺 ID | `Ec::Store` ID，只返回一次 |
| `store_name` | 店铺名称 | ERP 店铺展示名称 |
| `order_id` | 订单 ID | `ec_orders.id` |
| `order_key` | 订单唯一键 | 平台、店铺内的规范化订单键 |
| `external_order_id` | 平台订单 ID | 平台原始订单标识 |
| `external_order_number` | 平台订单号 | 平台展示订单号 |
| `order_status` | 订单状态 | ERP 规范化订单状态 |
| `order_source_status` | 平台订单状态 | `ec_orders.source_status` |
| `order_source_substatus` | 平台订单子状态 | `ec_orders.source_substatus` |
| `ordered_at` | 下单时间 | 用于判断是否落入请求周期 |
| `in_process_at` | 开始处理时间 | 订单进入处理流程的时间 |
| `order_completed_at` | 订单完成时间 | `ec_orders.completed_at` |
| `order_cancelled_at` | 订单取消时间 | `ec_orders.cancelled_at` |
| `buyer_city` | 买家城市 | 平台收货地址城市 |
| `buyer_region` | 买家地区 | 平台收货地址地区/州 |
| `buyer_country` | 买家国家 | 平台收货国家 |
| `payment_method_source` | 支付方式 | 平台原始支付方式 |
| `is_legal_entity` | 是否企业买家 | `true` 表示法人/企业客户 |
| `order_synced_at` | 订单同步时间 | `ec_orders.synced_at` |

### 履约字段

item 没有关联履约记录时，下列字段均为 `null`。

| 字段 | 中文含义 | 来源/说明 |
| --- | --- | --- |
| `fulfillment_id` | 履约记录 ID | `ec_order_fulfillments.id` |
| `external_fulfillment_id` | 平台履约 ID | 平台 posting/履约标识 |
| `fulfillment_key` | 履约唯一键 | 平台、店铺内的规范化履约键 |
| `fulfillment_type` | 履约类型 | `fbo`、`fbw`、`fbs`、`fba`、`fbm` 或 `unknown` |
| `fulfillment_status` | 履约状态 | ERP 规范化履约状态 |
| `fulfillment_source_status` | 平台履约状态 | `ec_order_fulfillments.source_status` |
| `fulfillment_source_substatus` | 平台履约子状态 | `ec_order_fulfillments.source_substatus` |
| `warehouse_external_id` | 平台仓库 ID | 发货仓的平台标识 |
| `warehouse_name` | 仓库名称 | 发货仓名称 |
| `delivery_method_name` | 配送方式 | 平台配送方法名称 |
| `delivery_type_source` | 平台配送类型 | 平台原始配送类型 |
| `cluster_from` | 发货集群 | 货物发出集群/区域 |
| `cluster_to` | 收货集群 | 货物目标集群/区域 |
| `tracking_number` | 物流单号 | 平台或承运商跟踪号 |
| `shipped_at` | 发货时间 | 履约发货时间 |
| `delivered_at` | 妥投时间 | 履约完成配送时间 |
| `fulfillment_cancelled_at` | 履约取消时间 | `ec_order_fulfillments.cancelled_at` |
| `cancel_reason_source` | 平台取消原因 | 平台原始取消原因或代码 |
| `fulfillment_raw_source_type` | 履约原始表类型 | 用于追溯履约数据来源 |
| `fulfillment_raw_source_id` | 履约原始记录 ID | 用于追溯履约数据来源 |
| `fulfillment_synced_at` | 履约同步时间 | `ec_order_fulfillments.synced_at` |

### 商品明细字段

| 字段 | 中文含义 | 来源/说明 |
| --- | --- | --- |
| `item_id` | 订单商品 ID | `ec_order_items.id`，每个返回行唯一 |
| `external_item_id` | 平台商品明细 ID | 平台订单内的商品行标识 |
| `sku_code` | 内部 SKU | 固定为本次查询 SKU，由硬绑定确定，不使用 item 冗余值 |
| `platform_sku_id` | 平台 SKU ID | Ozon SKU 或 WB `nmId` |
| `offer_id` | 商家货号 | 平台 offer/article |
| `product_name_source` | 平台商品名称 | 导入时记录的平台商品名称或货号文本 |
| `quantity` | 数量 | 当前 item 的商品件数；一行不等于一件，需按该字段求和 |
| `currency_code` | 币种 | 价格和费用字段的币种 |
| `unit_price` | 成交单价 | 当前商品单位成交价 |
| `old_unit_price` | 原单价 | 折扣前单价；平台未提供时为 `null` |
| `discount_amount` | 折扣金额 | 当前商品行折扣额 |
| `discount_percent` | 折扣比例 | 当前商品行折扣百分比 |
| `commission_amount` | 佣金金额 | 平台佣金金额 |
| `commission_percent` | 佣金比例 | 平台佣金百分比 |
| `payout` | 预计/实际结算额 | 平台归集到当前商品行的 payout |
| `item_synced_at` | 商品明细同步时间 | `ec_order_items.synced_at` |

结果按 `ordered_at` 升序、`item_id` 升序排列。空数组表示周期内没有已记录且能通过平台商品硬绑定归属到当前 SKU 的订单 item，不能据此断言平台上从未产生订单。

## `supply_orders_full_period`：周期送仓记录

返回请求周期内当前 SKU 的送仓商品明细，字段与 ERP“送仓记录”界面一致，并增加 `platform`、`store_id`、`store_name` 方便跨店铺分析。每个平台商品明细一行，结果按创建时间、平台、送仓单号和平台商品 ID 升序排列。

周期边界按 API 用户时区计算。WB 使用界面“创建时间”对应的 `raw_wb_supplies.supply_created_at`；Ozon 使用 `raw_ozon_supply_orders.created_at`。WB 商品明细来自 `raw_wb_supply_items`，并通过账号和送仓单号关联 `raw_wb_supplies`；Ozon 商品明细从 `raw_ozon_supply_orders.items` JSON 展开。SKU 归属使用当前店铺商品绑定：WB 匹配 `product_id/nmId`，Ozon 匹配 `platform_sku_id`。

| 公共字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `platform` | 平台 | `wb` 或 `ozon` |
| `store_id` | 店铺 ID | `Ec::Store` ID |
| `store_name` | 店铺名称 | ERP 页面展示名称 |
| `supply_id` | 送仓单号 | WB 送仓单 ID 或 Ozon supply order ID |
| `status` | 状态 | 平台原始状态代码，中文含义见下方状态说明 |
| `platform_item_id` | 平台商品 ID | WB 商品 `nmId` 或 Ozon SKU ID |
| `sku_code` | SKU | 本次查询的内部 SKU 编码 |
| `product_name` | 商品名称 | 当前 SKU 商品名称 |
| `quantity` | 数量 | WB 为当前商品计划数量；Ozon 为当前商品送仓数量 |
| `created_at` | 创建时间 | 用于判断记录是否落入请求周期 |
| `synced_at` | 同步时间 | 当前商品明细或送仓单最近同步时间 |

### WB 送仓字段

| 字段 | 页面中文 | 口径 |
| --- | --- | --- |
| `preorder_id` | 预订单号 | WB 预订单 ID |
| `accepted_quantity` | 实收数量 | 当前商品已接收数量 |
| `remaining_quantity` | 待收数量 | `max(quantity - accepted_quantity, 0)` |
| `warehouse_name` | 计划仓 | 原计划接收仓库 |
| `actual_warehouse_name` | 实际仓 | 实际接收仓库 |
| `transit_warehouse_name` | 中转仓 | 中转仓库名称 |
| `scheduled_at` | 计划送仓时间 | WB 计划送达时间 |
| `actual_at` | 实际送仓时间 | WB 实际送达时间 |
| `packaging` | 包装类型 | `without_boxes` 无箱、`boxes` 箱装、`mono_pallet` 单品托盘、`super_safe`、`piece_pallet` 按件托盘或 `unknown` |
| `pallet` | 托盘送仓 | WB 是否标记为托盘送仓 |
| `acceptance_cost` | 接收费 | WB 接收费用 |
| `paid_acceptance_coefficient` | 付费接收系数 | WB 接收计费系数 |
| `storage_coefficient` | 仓储系数 | WB 仓储计费系数 |
| `delivery_coefficient` | 配送系数 | WB 配送计费系数 |
| `supplier_assign_name` | 指派方 | WB 指派的供应方名称 |
| `reject_reason` | 拒绝原因 | 送仓单被拒绝时的平台原因 |
| `supply_quantity` | 送仓总量 | 整张送仓单的计划总数量，可能包含其他 SKU |
| `supply_accepted_quantity` | 送仓实收量 | 整张送仓单的实收总数量，可能包含其他 SKU |
| `ready_for_sale_quantity` | 可售数量 | 已完成接收并可售的数量 |
| `unloading_quantity` | 卸货数量 | 正在卸货的数量 |
| `depersonalized_quantity` | 去个性化数量 | WB 去个性化处理数量 |
| `can_show_quantity` | 数量可见 | WB 是否允许展示送仓数量 |

WB 状态：`1` 未计划、`2` 已计划、`3` 允许卸货、`4` 接收中、`5` 已接收、`6` 已在闸口卸货。

### Ozon 送仓字段

| 字段 | 页面中文 | 口径 |
| --- | --- | --- |
| `order_number` | 订单编号 | Ozon 页面展示的送仓订单编号 |
| `timeslot_from` | 送仓时段开始 | Ozon timeslot 起始时间；为保持表格扁平而从 `timeslot` 拆出 |
| `timeslot_to` | 送仓时段结束 | Ozon timeslot 结束时间 |
| `origin_warehouse` | 交货仓（起点） | `drop_off_warehouse.name` |
| `destination_warehouses` | 目的仓 / 集群 | Ozon supplies 中的目的仓名称；没有仓名时使用已同步的集群名称，多个值以 ` / ` 连接 |
| `state_updated_at` | 状态更新时间 | Ozon 平台状态最近更新时间 |

Ozon 常见状态：`DATA_FILLING` 填写资料中、`READY_TO_SUPPLY` 等待送仓、`ACCEPTED_AT_SUPPLY_WAREHOUSE` 发货仓已接收、`IN_TRANSIT` 运输中、`ACCEPTANCE_AT_STORAGE_WAREHOUSE` 目的仓接收中、`REPORTS_CONFIRMATION_AWAITING` 等待确认报告、`REPORT_REJECTED` 报告已驳回、`COMPLETED` 已完成、`REJECTED_AT_SUPPLY_WAREHOUSE` 发货仓已拒绝、`CANCELLED` 已取消、`OVERDUE` 已逾期。

空数组表示请求周期内没有已记录且能通过平台商品绑定归属到当前 SKU 的送仓商品明细，不能据此断言平台上从未创建送仓单。

## `operation_actions_full_period`：周期运营记录

返回请求周期内当前 SKU 的 `ec_operation_actions`，按 API 用户时区和 `operated_at` 判断周期，按操作时间、记录 ID 升序排列。每条记录保留操作类型、平台店铺、平台商品、归属运营和完整 `diff_result`。

`ec_operation_actions` 没有独立的 `before`、`after` 数据库列。系统变更通常保存在 `diff_result.fields.<字段>.from/to`，其中 `from` 是修改前、`to` 是修改后；数组变化还可能使用 `added`、`removed`，图片变化可能使用 `primary_from`、`primary_to`。如果某条记录在 `diff_result` 中直接包含 `before`、`after`，接口也会原样保留。不要只读取 `to` 而忽略变更前值。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `action_id` | 运营记录 ID | `ec_operation_actions.id` |
| `operated_at` | 变更时间 | 用于判断记录是否落入请求周期 |
| `operation_type` | 变更类型 | 见下方类型说明 |
| `record_by_system` | 是否系统记录 | `true` 为同步或系统自动记录，`false` 通常为人工记录 |
| `platform` | 平台 | `wb` 或 `ozon` |
| `store_id` | 店铺 ID | `Ec::Store` ID |
| `store_name` | 店铺 | ERP 页面展示名称 |
| `sku_code` | SKU | 本次查询的内部 SKU 编码 |
| `sku_product_id` | 平台商品绑定 ID | `Ec::SkuProduct` ID |
| `platform_product_id` | 平台商品 ID | WB 通常为 `nmId`；Ozon 为商品绑定 ID |
| `platform_sku_id` | 平台 SKU ID | Ozon SKU；WB 可能为空或仅作辅助信息 |
| `offer_id` | 商家货号 | 平台 offer/article |
| `operated_by_user_id` | 归属运营 ID | 记录归属用户 ID |
| `operated_by_user_name` | 归属运营 | 页面展示的用户名称 |
| `diff_result` | 变更内容 | 完整业务差异；保留修改前后、增删项、归属来源和业务元数据 |

常见 `operation_type`：`listing_content` 内容、`listing_pricing` 价格、`listing_specification` 规格、`manual_note` 人工记录、`sku_adv_on_off` 广告开关、`sku_adv_budget` 广告预算、`sku_inbound_change` 平台在途、`supply_order` 送仓记录。

为控制上下文大小，完整上下文响应会递归移除键名为或以其结尾的 `raw_json`、`raw_payload`，以及 `source_payload`、`item_payload`。该过滤应用于所有上下文板块，不会移除 `diff_result` 中的 `before`、`after`、`from`、`to`、`added`、`removed` 等业务变化。

空数组表示请求周期内没有已记录的运营操作，不能据此断言平台或人工从未发生变化。

## `search_terms_per_week`：逐周搜索词概况

按自然周和店铺返回 ERP“搜索词分析”界面的第一层 SKU 汇总，不返回点击展开后的第二层具体搜索词明细，也不返回页面计算的环比提示。Ozon 第一层来自 `raw_ozon_product_queries`；WB 第一层主体来自 `raw_wb_search_report_products`，并使用 `raw_wb_analytics_search_terms` 计算搜索词数。Ozon 的 `raw_ozon_product_query_details` 和 WB 的具体关键词排行不会进入结果。

| 字段 | 中文含义 | 说明 |
| --- | --- | --- |
| `period_from` / `period_to` | 自然周范围 | 周一至周日，使用请求周期 |
| `is_partial` | 是否未完整 | 周结束日晚于 API 用户时区当天时为 `true` |
| `stores[].store_ref` | 店铺引用 | `wb:<账号ID>` 或 `ozon:<账号ID>` |
| `stores[].platform` | 平台 | `wb` 或 `ozon` |
| `stores[].store_id` | 店铺 ID | `Ec::Store` ID |
| `stores[].store_name` | 店铺名称 | ERP 页面展示名称 |
| `stores[].data_status` | 数据状态 | 当前周有第一层汇总时为 `available`，否则为 `no_records` |
| `stores[].data` | SKU 周汇总 | 当前 SKU 在该店铺、该自然周的第一层数据，通常为零行或一行 |

### 第一层汇总字段

| 字段 | 页面中文 | 口径 |
| --- | --- | --- |
| `sku_code` | SKU | 内部 SKU 编码 |
| `product_name` | 商品名称 | ERP SKU 商品名称 |
| `term_count` | 搜索词数 | WB 当前商品周内去重关键词数；Ozon 第一层不提供，为 `null` |
| `search_volume` | 搜索人数 | Ozon 搜索该商品的唯一用户数；WB 第一层页面不展示，返回 `0` |
| `avg_position` | 平均位置 | 按流量加权的平均搜索位置，数值越小通常越靠前 |
| `views` | 商品点击 / 商品浏览人数 | WB 为打开商品卡次数；Ozon 为查看商品的唯一用户数 |
| `add_to_cart` | 加购 | WB 加购次数；Ozon 第一层不提供，为 `null` |
| `cart_conversion` | 点击到加购转化率 | WB 按商品卡打开次数加权的 `open_to_cart`；Ozon 为 `null` |
| `orders` | 已下单 | WB 下单数；Ozon 第一层不提供，为 `null` |
| `revenue` | 搜索 GMV | Ozon 搜索归因 GMV，当前为 RUB；WB 第一层不提供，为 `null` |
| `conversion` | 加购到下单 / 搜索到浏览转化率 | WB 为按加购数加权的 `cart_to_order`；Ozon 为按搜索人数加权的 `view_conversion`，单位均为百分比 |
| `visibility` | 可见度 | WB 按商品卡打开次数加权的可见度；Ozon 为 `null` |

Ozon 搜索词数据只同步已结束自然周：周一可能先以截至上周五的数据写入上周完整周，周三再用上周一至周日数据覆盖。因此周一、周二读取上周时，周末数据可能尚未计入。当前自然周通常为 `no_records`，不能按零流量解读。

空数组或 `no_records` 表示该周没有已同步的第一层商品查询汇总，不能据此断言平台上没有搜索曝光。分析时不要从本板块推断具体关键词，因为第二层明细被明确排除。

## `current_inventory_info`：当前库存

当前库存按 API 用户时区的当天计算，不受请求周期影响。字段直接来自库存报表，可能随页面能力扩展。

### `list`：列表口径

| 字段 | 说明 |
| --- | --- |
| `sku_code` / `product_name` / `product_name_ru` | SKU 及中俄文商品名称 |
| `marketing_grade` / `marketing_stage` | 当前营销等级和阶段 |
| `incoming_quantity` | 已下单但尚未收货的采购在途数量 |
| `book_stock` | 账面库存 |
| `platform_inbound_stock` | 平台入库中库存 |
| `platform_stock` | 平台 FBO/FBW 库存口径 |
| `available_stock` | 海外可用库存；当前公式为 `book_stock - platform_stock - platform_inbound_stock` |
| `pkg_length_cm` / `pkg_width_cm` / `pkg_height_cm` | 包装长宽高，厘米 |
| `unit_volume_l` | 单件体积，升 |
| `daily_sales_velocity` | 当前日均销量速度 |
| `turnover_days` | 现有账面库存按当前销量速度预计可售天数 |
| `turnover_days_with_procurement` | 加上采购在途后的预计可售天数 |
| `cache_updated_at` | 库存查询缓存更新时间 |

### `detail`：详情口径

`detail` 保留库存详情页的完整数据，包括汇总、采购在途批次、账面批次、销售和退货分布、平台店铺及仓库库存、对账行和分页信息。常用字段：

| 字段 | 说明 |
| --- | --- |
| `summary.purchase_quantity` | 累计采购数量 |
| `summary.adjustment_quantity` | 账面调整数量 |
| `summary.received_quantity` | 调整后的累计收货数量 |
| `summary.sales_quantity` | 累计销售数量 |
| `summary.return_quantity` | 累计退货数量 |
| `summary.supply_quantity` | 累计发往平台的供应数量 |
| `summary.fbo_fbw_stock` | 当前平台 FBO/FBW 库存 |
| `incoming_batches` | 采购在途批次，包括批次号、状态、预计到货日和采购数量 |
| `platform_shop_rows` | 按平台店铺汇总的 FBO/FBW、入库中和 FBS 库存 |
| `platform_warehouse_rows` | 按平台仓库和集群展开的库存明细 |
| `book_formula` / `platform_formula` | 页面用于解释账面库存和海外可用库存的计算项 |

## `history_inventory_info`：历史库存

API 返回所选周期内 `snapshot_type = inventory` 的 SKU 日快照，按日期升序：

```json
[
  {
    "snapshot_date": "2026-09-01",
    "content": { "overview": {}, "distribution": {} }
  }
]
```

| 字段 | 说明 |
| --- | --- |
| `snapshot_date` | 快照日期 |
| `content.overview` | 当天库存核心指标，口径与当前库存列表相近 |
| `content.overview.platform_totals` | 当天按 WB/Ozon 汇总的平台库存及履约类型分布 |
| `content.distribution` | 当天店铺、仓库和集群级库存明细；API 原样返回 |

为便于 AI 阅读趋势，本 skill 生成的 `history_inventory_info.md` 只保留 `snapshot_date + content.overview`，将嵌套汇总字段用点号展平，并保证一天一行。体积较大的 `content.distribution` 不写入 Markdown 缓存，但仍存在于接口原始响应中。
