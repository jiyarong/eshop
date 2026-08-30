# AI V2 SKU 营销运营上下文 API

## 请求

```http
GET /ai/v2/skus/marketing_context?sku_code=<SKU>&period_from=<MONDAY>&period_to=<SUNDAY>
Authorization: Bearer <user_api_key>
Accept: application/json
```

- `sku_code` 必填，输入会去除首尾空格并转成大写。
- API Key 所属用户必须拥有 `view_reports` 权限。
- `period_from`、`period_to` 必须同时传入，且分别为周一和周日。
- 周期最多 12 个自然周。
- 未传周期时，返回最近 4 个已经结束的完整自然周。
- 显式周期可以包含当前周；当前周会标记 `is_partial: true`，利润不会输出未完成周指标。
- 周期不能超过当前自然周；包含尚未开始的未来周时返回 `future_period_unsupported`。
- 日期边界和 `as_of` 使用 API Key 所属用户的时区。

## 响应结构

```json
{
  "data": {
    "schema_version": 1,
    "period": {},
    "sku": {},
    "profitability": {},
    "channel_performance": {},
    "inventory": {},
    "operations": {}
  }
}
```

### `sku`

返回 SKU/SPU、当前营销阶段和等级、经营状态，以及已绑定的平台商品。平台商品仅保留内部绑定 ID、店铺、平台商品标识、标题、类目、当前状态和价格摘要，不返回描述、条码、图片或平台原始载荷。

`source_status` 表示该绑定能否作为报表数据源。`source_reason` 常见值：

- `inactive_store`：ERP 店铺已停用。
- `store_account_not_linked`：店铺没有关联原始平台账号。
- `inactive_account`：原始平台账号已停用或不存在。
- `duplicate_store_account_mapping`：同一原始账号关联了多个 ERP 店铺，归属不唯一，接口拒绝猜测。
- `unsupported_platform`：当前营销上下文不支持该平台。

### `profitability.weekly`

- 只查询当前 SKU 通过 `Ec::SkuProduct` 硬绑定的有效店铺和平台商品。
- WB 的 BYN、Ozon 的 RUB 会按该周汇率统一换算为 CNY。
- `ads`、`goods_cost` 在统一口径中均为正费用；`pre_tax`、`tax`、`after_tax` 保留业务正负号。
- `margin_pct = after_tax / revenue`。
- `average_profit_per_order = after_tax / net_sales`。
- `ad_ratio_pct = ads / revenue`。
- `cost_return_pct = after_tax / goods_cost`。
- 分母为零或所需成本数据缺失时返回 `null`，不得按 0 解读。

### `channel_performance.weekly[].channels[]`

每个渠道统一使用 ERP `store_id`，平台原始账号使用 `account_ref`（例如 `wb:12`）。广告金额保持平台原币种，不跨币种合计；币种缺失或 WB 同一商品周内出现混合币种时，金额与金额派生指标返回 `null`，并标记 `monetary_data_status`。平台售价也通过 `currency_status` 明确币种是否可用。

`funnel` 使用以下归一化含义：

- WB：`views` 为商品卡打开，`add_to_cart` 为加购，`orders` 为下单，`fulfilled_orders` 为买断/成交。
- Ozon：`impressions` 为总曝光，`search_impressions` 为搜索/类目曝光，`views` 为详情页访问，`orders` 为下单件数，`fulfilled_orders` 为已妥投件数。

漏斗源的金额字段没有稳定的跨平台币种元数据，因此本接口不返回漏斗销售额或均价；销售额、利润和费用比较统一使用 `profitability.weekly` 的 CNY 口径。

`search_visibility` 只返回 SKU 第一层搜索可见度汇总，不包含具体关键词。WB 源不提供搜索人数，因此 `search_volume` 为 `null`，不能按 0 解读。

Ozon 多个平台商品合并时，`average_search_position` 按搜索曝光加权；缺少有效曝光权重时退回有位置数据行的简单平均。漏斗计数只要有一条来源行缺失该字段，聚合结果就返回 `null`，避免把来源缺口误判为零。

### `inventory`

- `current`：当前账面库存、平台仓/平台在途、采购在途、日均销量和周转天数，`scope` 固定为 `sku_all_sources`。没有最新库存 level 时标记 `no_records`，平台库存、平台在途、可用库存和断货状态返回 `null`；存在未归因库存或有效渠道绑定但缺少该渠道库存 level 时标记 `partial_sources`。
- `channel_coverage`：说明 `by_channel` 是否覆盖全局当前库存 level。`partial` 表示存在无法归因的库存 level；`unattributed_platform_stock` 和 `unattributed_inbound_stock` 给出未覆盖数量。`excluded_channel_count`、`missing_eligible_channel_count` 是数据源风险提示，不会在没有实际库存缺口时把归因覆盖率误标为 `partial`。
- `by_channel`：按店铺和履约类型压缩后的当前平台库存。
- `weekly_snapshots`：每个自然周取该周最后一份库存日快照，只保留 overview 和平台是否断货，不返回仓库分布明细。

`current` 与 `weekly_snapshots` 使用当前 SKU 的全局库存口径，确保 `available_stock = book_stock - platform_stock - platform_inbound_stock` 内部一致；`by_channel` 只纳入可明确归因的有效渠道。分析渠道库存时必须先检查 `channel_coverage.data_status`，并结合 listing 的 `source_status` 检查不可用渠道；不能把全局 `available_stock` 当作逐店铺可售库存。

### `operations`

返回周期内运营动作计数和最近 20 条动作。动作保留时间、类型、店铺、内部绑定 ID、平台商品 ID、平台 SKU ID、offer ID、操作人和字段变化，便于同店铺多 listing 时准确归因；长文本、大数组和字段过多的差异会被摘要，避免单条日志占满上下文。

## 数据状态

- `available`：存在已记录数据；不保证平台源数据覆盖整周，广告板块应同时检查 `days_with_data` 和 `data_through`。
- `no_records`：系统在该范围内没有已记录数据，不能据此断言平台没有业务活动。
- `partial_week`：自然周尚未结束，利润指标不输出。
- `partial_sources`：部分绑定店铺不可用，返回的汇总不完整；检查 `unavailable_store_ids`。
- `unavailable`：缺少账号、汇率或其他必要数据，检查 `reason`。

渠道查询期间账号被停用或删除时，该渠道会返回 `reason: "source_unavailable"`，不会将整份响应误报为 SKU 不存在。

订单商品、送仓单、完整库存详情、仓库分布和完整 `diff_result` 不进入本接口。需要审计或逐条取证时继续使用 `/ai/v2/skus/full_context`。
