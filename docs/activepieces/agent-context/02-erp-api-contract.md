# ERP API 合同摘要

完整字段说明见 [`api-schema.md`](../../../app/services/erp_ai/v3/skills/fetch-yuanlong-sku-context/references/api-schema.md)。本文件帮助外部 Agent 快速确定请求边界和响应校验方式。

## V3 SKU 分段接口

常用接口如下。所有接口都使用 `GET`，参数至少包含 `sku_code`：

| 业务板块 | JSON 路径 | `data` 内的上下文键 |
| --- | --- | --- |
| 基础信息 | `/ai/v3/sku/base_context.json` | `base` |
| 库存 | `/ai/v3/sku/inventory_context.json` | `inventory` |
| 生命周期 | `/ai/v3/sku/lifecycle_context.json` | `lifecycle` |
| 利润 | `/ai/v3/sku/profit_context.json` | `profit` |
| 销售漏斗 | `/ai/v3/sku/sales_funnel_context.json` | `sales_funnel` |
| 分仓建议 | `/ai/v3/sku/warehouse_recommendation_context.json` | `warehouse_recommendation` |
| 广告 | `/ai/v3/sku/advertising_context.json` | `advertise_per_week` |
| 搜索词 | `/ai/v3/sku/search_terms_context.json` | `search_terms_per_week` |
| 订单 | `/ai/v3/sku/orders_context.json` | `ec_orders_full_period` |
| 送仓 | `/ai/v3/sku/supply_orders_context.json` | `supply_orders_full_period` |
| 运营动作 | `/ai/v3/sku/operation_actions_context.json` | `operation_actions_full_period` |

不是每个任务都需要全部接口。Agent 应先根据输出合同选择最小数据集合，并说明每个接口为何需要。

## 请求参数

```text
sku_code       必填，内部 SKU 编码
period_from    可选，必须是自然周周一
period_to      可选，必须是自然周周日
target_days    可选，仅分仓建议使用
```

日期边界和展示日期必须依据响应中的 `data.period.time_zone` 解读。当前项目的计划周期规则是上海时区自然周，但样本流程可能返回其他用户时区，不能从 fixture 推断全局时区。

## 响应信封

每个接口都应先校验外层结构：

```json
{
  "data": {
    "schema_version": 3,
    "sku_code": "JJ005-6",
    "period": {
      "from": "YYYY-MM-DD",
      "to": "YYYY-MM-DD",
      "as_of": "YYYY-MM-DD",
      "time_zone": "Asia/Shanghai",
      "week_starts_on": "monday"
    }
  }
}
```

实际上下文位于 `data.<context_key>`。不同接口合并前必须校验 SKU、版本、`as_of` 和时区一致；缺失或冲突应进入明确的错误或 `insufficient_data` 分支。

## 错误和缺失语义

| 状态 | 含义 | 流程处理建议 |
| --- | --- | --- |
| `400` | 参数缺失 | 停止并报告输入错误 |
| `401` | 鉴权失败 | 停止，不重试密钥，不输出伪成功 |
| `404` | SKU 不存在 | 停止并报告 SKU |
| `422` | 日期或参数不合法 | 修正参数后重试，不能忽略 |
| `null` 字段 | 没有可用计算数据 | 保留 `null`，结论降级 |
| 空数组 | 当前查询范围没有明细 | 保留空数组，不推断“从未发生” |

## 其他只读数据

Ozon Listing 诊断使用 `/ai/sql_queries.json` 读取 Listing 文本、官方属性目录和搜索词明细。该接口只允许只读 SQL，必须明确指定返回列，并检查 `has_more`；结果截断时应停止诊断或显式分页，不能静默使用不完整集合。

