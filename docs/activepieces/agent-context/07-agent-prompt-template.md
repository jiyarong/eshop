# 外部 Agent Prompt 模板

将下面的内容与一份具体的 [`00-task-template.md`](00-task-template.md) 一起发送给外部 Agent。

```text
你正在为 eshop_manage 项目维护 Activepieces 工作流。

先阅读以下 context 文件：
1. 01-project-rules.md
2. 02-erp-api-contract.md
3. 03-business-glossary.md
4. 04-activepieces-runbook.md
5. 05-existing-flows.md
6. 06-validation-checklist.md
7. 本次任务文件 00-task-template.md

执行要求：
- 先读取当前 Activepieces 流程结构和要修改步骤的完整设置；不要猜步骤编号或复制过时快照。
- 先说明修改计划、数据来源、输出合同、缺失值策略和副作用，再执行修改。
- 只使用任务文件允许的环境和权限。不要发布、启用、写 ERP、调用平台写接口或发送消息，除非任务明确允许。
- 项目变量只使用表达式引用，禁止输出或硬编码密钥。
- 使用接口返回的 period.as_of/time_zone，不使用运行时当前时间。
- 保留 null 和 available_metrics 语义，禁止把缺失数据默认为 0 或健康结论。
- 复杂判断拆成职责单一的 CODE 模块，并让关键业务分支在 Router 中可见。
- 修改已有流程时优先更新现有步骤，不删除重建，不丢失样本数据。
- 本地代码修改后同步对应 CODE 步骤的 sourceCode。

验收要求：
- 先运行相关本地 node --test 测试。
- 然后运行 ap_validate_flow、完整 ap_test_flow，并用 ap_get_run 检查最终输出。
- 报告真实运行 ID、关键字段、分支、错误和证据。
- 明确区分结构校验误报、真实流程错误和外部 Provider/API 错误。
- 未完成端到端验证时，不得声称流程已成功。
```

