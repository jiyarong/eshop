# Activepieces 外部 Agent Context Pack

本目录是提供给外部 Agent 创建、修改和验收 Activepieces 工作流的上下文包。它把稳定的项目约束、ERP 数据口径、Activepieces 操作顺序和现有流程样板分开，避免 Agent 只看截图或凭经验猜流程结构。

在 Codex 中处理本项目的 Activepieces 任务时，可调用 `$activepieces-workflow-context`。该 skill 会读取本目录，并根据任务选择创建、修改、验证或交接流程的工作方式。

## 使用方式

每次任务提供两部分内容：

1. 本目录中与任务相关的稳定 context。
2. 一份任务增量说明，使用 [`00-task-template.md`](00-task-template.md) 填写目标流程、允许的副作用、输入输出和验收标准。

推荐按以下顺序读取：

1. [`01-project-rules.md`](01-project-rules.md)
2. [`02-erp-api-contract.md`](02-erp-api-contract.md)
3. [`03-business-glossary.md`](03-business-glossary.md)
4. [`04-activepieces-runbook.md`](04-activepieces-runbook.md)
5. [`05-existing-flows.md`](05-existing-flows.md)
6. [`06-validation-checklist.md`](06-validation-checklist.md)
7. [`07-agent-prompt-template.md`](07-agent-prompt-template.md)

## 规范来源

本 context pack 是入口和摘要，业务实现仍以仓库中的实际代码和快照为准：

- 项目总约束：[`AGENTS.md`](../../../AGENTS.md)
- 库存工作流：[`script/activepieces/sku_inventory_health/`](../../../script/activepieces/sku_inventory_health/)
- Ozon Listing 工作流：[`script/activepieces/ozon_listing_diagnosis/`](../../../script/activepieces/ozon_listing_diagnosis/)
- V3 API 字段说明：[`app/services/erp_ai/v3/skills/fetch-yuanlong-sku-context/references/api-schema.md`](../../../app/services/erp_ai/v3/skills/fetch-yuanlong-sku-context/references/api-schema.md)

当摘要和实际流程快照不一致时，Agent 必须先读取 Activepieces 当前结构和步骤设置，再以当前结构为准，并把差异记录到任务结果中。

## 不能放入 context pack 的内容

- `YUANLONG_TOKEN`、`SUB2_API_KEY` 或任何其他密钥的实际值。
- 生产数据库导出、未脱敏的客户或订单数据。
- 把 `flow-definition.json` 当成 Activepieces 原生导入包的说明。
- 未经确认的步骤编号、动作名称或动态下拉显示标签。

项目变量只在 Activepieces 中通过表达式引用，例如 `{{variables['YUANLONG_TOKEN']}}`。外部 Agent 只需要知道变量名和允许用途，不需要知道变量值。

