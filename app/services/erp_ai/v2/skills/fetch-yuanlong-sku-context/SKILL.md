---
name: fetch-yuanlong-sku-context
description: 获取辕隆 ERP 中单个 SKU 的精炼营销运营上下文，包括基础信息、逐周利润、渠道漏斗、广告、搜索可见度、库存和运营动作，并缓存为本地 Markdown 文件。当 AI 在营销分析、经营诊断、备货规划或生成报告前需要了解某个辕隆 SKU 时使用。
---

# 获取辕隆 SKU 营销运营上下文

优先调用本接口获取权威上下文，不要通过无关 API 或自行拼接 SQL 重建 SKU 信息。

## 接口

- 生产环境接口：`GET http://eshop.evexport.cn/ai/v2/skus/marketing_context`
- 鉴权方式：`Authorization: Bearer <分配的用户 API Key>`
- 必填参数：`sku_code`
- 可选参数：`period_from`、`period_to`

本 skill 默认使用精炼的营销接口，不请求完整订单、送仓明细或原始变更日志。只有用户明确要求逐单审计、售后取证或数据排查时，才单独调用旧的 `/ai/v2/skus/full_context`；不要把完整订单明细作为营销分析上下文整体读入。

使用分配给当前用户或 Agent 的 API Key。默认从环境变量 `YUANLONG_API_KEY` 读取；不要把 API Key 写入命令、Markdown、日志、源代码或对话输出。需要切换接口环境时，可通过 `YUANLONG_API_BASE_URL` 覆盖生产环境地址。

解释接口响应前，读取 [references/marketing-context-schema.md](references/marketing-context-schema.md)。旧 `/full_context` 的字段说明仍保留在 [references/api-schema.md](references/api-schema.md)，仅用于明确的审计任务。

## 自然周周期

自然周是周一至周日。主动根据用户要求计算日期，不要把周三至下周二等滚动 7 天区间提交给接口。

- `period_from` 必须是周一。
- `period_to` 必须是周日。
- 两个日期必须同时传入，或者同时不传。
- 用户给出周数时，由 AI 自行计算自然周头尾，不要要求用户手工提供日期。

除非用户明确要求只包含已经结束的完整周，否则“近 N 周”表示最近结束的 `N` 个完整自然周。营销接口默认返回最近 4 个已结束周；显式周期可以包含当前周，此时当前周标记 `is_partial: true`，利润指标不输出未完成周。

例如今天是 2026-09-16，星期三：

- 最近 4 个完整周：`period_from=2026-08-17`，`period_to=2026-09-13`。
- 显式包含当前周的 4 周：`period_from=2026-08-24`，`period_to=2026-09-20`。

接口最多接受 12 个自然周。日期边界使用 API Key 所属用户的时区。

## 获取与本地缓存

在用户当前工作目录运行 skill 自带脚本：

```bash
python3 <skill目录>/scripts/fetch_context.py SKU-CODE
```

指定周期：

```bash
python3 <skill目录>/scripts/fetch_context.py SKU-CODE \
  --period-from 2026-07-27 \
  --period-to 2026-09-20
```

脚本会在当前目录写入：

```text
skus/<SKU_CODE>/context_data/<YYYY-MM-DD>/
|-- _metadata.md
|-- sku.md
|-- profitability.md
|-- channel_performance.md
|-- inventory.md
`-- operations.md
```

响应中的每个一级业务字段对应一个 Markdown 文件。扁平对象列表和标量列表会渲染为 Markdown 表格；复杂列表保留分节展示。接口只返回用于营销决策的聚合指标，不返回订单号、订单内部 ID、同步时间、买家信息、物流跟踪号或原始载荷，因此不会生成 `ec_orders_full_period.md` 和 `supply_orders_full_period.md`。

脚本对意外收到的旧 `full_context` 响应也执行白名单过滤：订单行只保留平台、店铺、订单状态、下单日期、必要履约状态/事件（发货/妥投）、SKU、数量、币种和金额；会移除 `order_id`、`order_key`、`external_order_id`、`external_order_number`、`item_id`、履约/商品外部编号、同步时间、处理/完成/取消时间、买家地域、支付方式和 tracking number 等字段。保留的日期用于业务事件顺序，不保留纯同步或内部流程时间。送仓行同样移除送仓单号、订单编号、创建/同步时间和时段明细。过滤后的旧文件仅作为临时审计线索，不应替代营销接口的汇总指标。

如果当天目录已经存在且 `_metadata.md` 标记了 `marketing_context`，直接使用缓存的 Markdown 文件，不要再次请求接口。旧版本生成的 `full_context` 缓存会在升级后的首次运行时自动迁移为精炼文件；迁移完成后仍遵循“每个 SKU 每天只获取一次”的规则，即使当天后续提示要求了不同周期也不重复请求。

只有用户明确要求“刷新”“重新获取”或“更新今天的上下文”时，才允许再次请求接口，并传入：

```bash
--refresh
```

获取成功或命中缓存后，只读取当前任务需要的 Markdown 文件。空数组或缺少记录表示系统中没有对应的已记录数据，不能据此断言相关业务事件从未发生。
