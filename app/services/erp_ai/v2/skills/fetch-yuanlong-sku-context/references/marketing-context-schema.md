# SKU 营销运营上下文 API 字段说明

本文档用于解释 `fetch-yuanlong-sku-context` 默认获取的精炼接口。字段缺失或为
`null` 表示数据不可用，不应按零解读；`no_records` 只表示系统在查询范围内没有已记录数据。

## 请求

```http
GET /ai/v2/skus/marketing_context?sku_code=<SKU>&period_from=<MONDAY>&period_to=<SUNDAY>
Authorization: Bearer <assigned_user_api_key>
Accept: application/json
```

`sku_code` 必填。周期参数必须同时传入，且分别为周一和周日，最多 12 个自然周。
未传周期时返回最近 4 个已结束的完整自然周。显式周期可以包含当前周；当前周标记
`is_partial: true`，利润指标不输出未完成周。日期边界和 `as_of` 使用 API Key 所属用户的时区。

## 响应结构

```json
{
  "data": {
    "schema_version": 1,
    "period": {
      "from": "2026-08-17",
      "to": "2026-09-13",
      "as_of": "2026-09-16",
      "time_zone": "Asia/Shanghai",
      "week_starts_on": "monday"
    },
    "sku": {},
    "profitability": {},
    "channel_performance": {},
    "inventory": {},
    "operations": {}
  }
}
```

## `sku`

返回 SKU/SPU、当前营销阶段和等级、经营状态，以及已绑定的平台商品。`listings` 每行包含：

| 字段 | 含义 |
| --- | --- |
| `sku_code` | 内部 SKU 编码 |
| `product_name` / `product_name_ru` | 商品名称 |
| `spu_code` | 所属 SPU 编码 |
| `current_stage` / `current_grade` | 当前营销阶段 / 等级 |
| `operation_status` | SKU 经营状态 |
| `listings` | 平台商品绑定列表 |
| `listings[].platform` / `store_id` / `store_name` | 平台和店铺 |
| `listings[].platform_product_id` / `platform_sku_id` | 平台商品标识 |
| `listings[].title` / `brand` / `category` | 标题、品牌、类目 |
| `listings[].listing_status` | `active`、`archived`、`in_trash` 或 `unavailable` |
| `listings[].source_status` / `source_reason` | 该渠道是否可作为统计数据源及原因 |
| `listings[].price` | 当前价格摘要；金额始终与其 `currency` 配套 |

常见 `source_reason`：`inactive_store`、`store_account_not_linked`、`inactive_account`、
`duplicate_store_account_mapping`、`unsupported_platform`。

## `profitability.weekly`

利润统一折算为 CNY，按已结束自然周、有效绑定渠道汇总。主要字段：

| 字段 | 含义 |
| --- | --- |
| `period_from` / `period_to` | 自然周边界 |
| `data_status` | `available`、`no_records`、`partial_week` 或 `unavailable` |
| `net_sales` | 净销量 |
| `revenue` | 收入 |
| `ads` | 广告费用（正数费用） |
| `goods_cost` | 商品成本（正数费用） |
| `pre_tax` / `tax` / `after_tax` | 税前、税额、税后利润，保留业务正负号 |
| `margin_pct` | `after_tax / revenue` |
| `average_profit_per_order` | `after_tax / net_sales` |
| `ad_ratio_pct` | `ads / revenue` |
| `cost_return_pct` | `after_tax / goods_cost` |

分母为零、汇率缺失或成本数据不完整时，相关指标为 `null`。

## `channel_performance.weekly[].channels[]`

每个渠道按 `platform`、`store_id` 和 `account_ref` 唯一标识，并分别返回：

- `funnel`：WB 的曝光/加购/下单/买断漏斗；Ozon 的总曝光、搜索曝光、详情访问、加购、下单、妥投、退货和取消漏斗。
- `advertising`：广告曝光、点击、加购、订单、花费、归因收入及 CTR、CPO、DRR、ROAS 等指标。
- `search_visibility`：关键词数量（WB）、搜索量（Ozon）、访问、平均位置及可见度/转化率摘要。

广告金额不跨币种合计。币种缺失或同一商品周内混合币种时，金额和金额派生指标为
`null`，并通过 `monetary_data_status` 标记 `unavailable_currency` 或
`unavailable_mixed_currency`。计数缺失也保留为 `null`，不按零补齐。

## `inventory`

- `current`：账面库存、平台库存、平台在途、采购在途、日均销量和周转天数；`data_status` 说明当前数据是否完整。
- `channel_coverage`：说明库存 level 是否能归因到有效店铺，包含未归因库存数量和缺失渠道提示。
- `by_channel`：按有效店铺和履约类型压缩的平台库存，不是全局可售库存。
- `weekly_snapshots`：每个自然周最后一份日快照，只保留趋势汇总，不包含仓库明细。

分析店铺库存前先检查 `channel_coverage.data_status`。不要把全局 `available_stock` 当作逐店铺可售库存。

## `operations`

`summary` 返回周期内运营动作计数；`recent` 最多返回最近 20 条动作。动作只保留操作时间、类型、店铺、平台商品归属、操作人和经过裁剪的字段变化/备注，不返回原始载荷。

## 订单数据边界

营销接口不返回订单商品、送仓单、订单号、订单内部 ID、履约外部编号、同步时间、买家信息或物流跟踪号。
订单数量、成交和取消应优先使用 `profitability` 与 `channel_performance.funnel`。
只有需要逐单审计时才调用旧 `/ai/v2/skus/full_context`，并按旧 schema 解释；skill 脚本对误收到的旧响应会进一步移除这些字段，仅保留有业务意义的下单/发货/妥投事件日期。
