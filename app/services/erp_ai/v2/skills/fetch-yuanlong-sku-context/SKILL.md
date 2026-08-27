---
name: fetch-yuanlong-sku-context
description: 获取辕隆 ERP 中单个 SKU 的完整业务上下文，包括基础信息、逐周利润、逐周销售漏斗、逐周广告、逐周搜索词、周期订单、周期送仓、周期运营记录和库存，并缓存为本地 Markdown 文件。当 AI 在分析、诊断、规划或生成报告前需要了解某个辕隆 SKU 的当前或历史上下文时使用。
---

# 获取辕隆 SKU 上下文

优先调用本接口获取权威上下文，不要通过无关 API 或自行拼接 SQL 重建 SKU 信息。

## 接口

- 生产环境接口：`GET http://eshop.evexport.cn/ai/v2/skus/full_context`
- 鉴权方式：`Authorization: Bearer <分配的用户 API Key>`
- 必填参数：`sku_code`
- 可选参数：`period_from`、`period_to`

使用分配给当前用户或 Agent 的 API Key。默认从环境变量 `YUANLONG_API_KEY` 读取；不要把 API Key 写入命令、Markdown、日志、源代码或对话输出。需要切换接口环境时，可通过 `YUANLONG_API_BASE_URL` 覆盖生产环境地址。

解释接口响应前，读取 [references/api-schema.md](references/api-schema.md)。

## 自然周周期

自然周是周一至周日。主动根据用户要求计算日期，不要把周三至下周二等滚动 7 天区间提交给接口。

- `period_from` 必须是周一。
- `period_to` 必须是周日。
- 两个日期必须同时传入，或者同时不传。
- 用户给出周数时，由 AI 自行计算自然周头尾，不要要求用户手工提供日期。

除非用户明确要求只包含已经结束的完整周，否则“近 N 周”表示本自然周以及之前的 `N - 1` 个自然周。`period_from` 是本周一往前 `N - 1` 周的周一，`period_to` 是本周日。

例如今天是 2026-09-16，星期三：

- 近 4 周：`period_from=2026-08-24`，`period_to=2026-09-20`。
- 近 8 周：`period_from=2026-07-27`，`period_to=2026-09-20`。
- 之前 4 个已结束的完整自然周：`period_from=2026-08-17`，`period_to=2026-09-13`。

不传周期时，接口默认返回近 4 个自然周。逐周利润会主动排除尚未结束的本周，把利润周期整体向前平移一周；其他上下文板块仍使用请求周期或默认周期。

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
|-- base.md
|-- weekly_profit_per_week.md
|-- sales_funnel_per_week.md
|-- advertise_per_week.md
|-- search_terms_per_week.md
|-- ec_orders_full_period.md
|-- supply_orders_full_period.md
|-- operation_actions_full_period.md
|-- current_inventory_info.md
`-- history_inventory_info.md
```

`context` 下每个一级 key 对应一个 Markdown 文件。同一天目录中已存在的同名文件会原子更新，不相关的其他文件会保留。扁平对象列表和标量列表会渲染为 Markdown 表格；包含嵌套结构的复杂列表保留分节展示。接口统一排除 `raw_json`、`raw_payload`、`source_payload`、`item_payload` 等大体积原始载荷，但运营记录的 `diff_result` 及其中的变更前后值必须保留。`history_inventory_info.md` 只输出 `snapshot_date + content.overview`，嵌套汇总字段用点号展平，保证每个快照日期一行；仓库级 `distribution` 明细不写入历史趋势文件。

如果当天目录已经存在 `_metadata.md`，直接使用缓存的 Markdown 文件，不要再次请求接口。即使当天后续提示要求了不同周期，也遵循“每个 SKU 每天只获取一次”的规则。

只有用户明确要求“刷新”“重新获取”或“更新今天的上下文”时，才允许再次请求接口，并传入：

```bash
--refresh
```

获取成功或命中缓存后，只读取当前任务需要的 Markdown 文件。空数组或缺少记录表示系统中没有对应的已记录数据，不能据此断言相关业务事件从未发生。
