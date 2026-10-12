# 项目规则摘要

本文件摘录创建 Activepieces 工作流时最容易被外部 Agent 忽略的项目约束。完整规则仍以仓库根目录 [`AGENTS.md`](../../../AGENTS.md) 为准。

## 流程结构

- 读取型流程优先采用：`Manual Trigger → 参数/Data Mapper → HTTP → 字段提取/Data Mapper → 规范化与校验 → Router → 小型 CODE 模块 → 报告`。
- 每个 CODE 模块只承担一种职责。Grade、Stage、诊断类型等业务分支使用可见的 Router，不要把所有规则藏进一个大型代码节点。
- 只修改实际存在的步骤。不能根据顺序猜 `step_N`，必须先调用 `ap_flow_structure` 获取真实步骤名、父子关系和分支位置。
- 修改前调用 `ap_read_step_settings`；CODE 步骤需要时调用 `ap_read_step_code`。`ap_flow_structure` 返回的配置文本可能被截断，不能作为完整备份。
- 已有流程优先使用 `ap_update_step`、`ap_update_trigger`。不要删除重建步骤，以免丢失样本数据、历史设置或分支关系。

## ERP 请求和变量

- ERP 地址为 `https://eshop.evexport.cn`，但任务文件可以覆盖为测试地址。
- Bearer token 使用项目变量 `{{variables['YUANLONG_TOKEN']}}`。禁止硬编码 token，也禁止把 token 写入 CODE、日志、Prompt、fixture 或快照。
- HTTP 节点通常使用 `GET`、`Accept: application/json`、`authType: BEARER_TOKEN`。
- JSON API 的常用数据路径是 `{{step_name['output'].body.data}}`；实际路径必须以当前接口响应和步骤设置为准。
- 步骤输出引用格式是 `{{step_name['output'].field}}`。不要写 `{{step_name.field}}`。

## 数据完整性

- 以接口返回的 `data.period.as_of` 和 `data.period.time_zone` 为日期事实来源。不要使用 JavaScript 运行时当前日期。
- `null` 表示缺少数据，不能自动转换成 `0`、空字符串或健康结论。
- `available_metrics` 中没有的指标视为不可用。
- 空数组只表示查询范围内没有明细，不能推断业务事件从未发生。
- 多个 V3 接口的 SKU、`schema_version`、`period.as_of` 和时区不一致时，应在规范化节点停止并报告证据冲突。
- 每个重要结论都应保留来源字段、计算值和缺失原因；不能只输出一个颜色或建议数量。

## 副作用和环境

- 报表和诊断流程的 GET 请求保持只读，不在页面请求或测试中触发同步、写库、采购、运营动作或消息发送。
- 草稿测试和正式发布是不同操作。除非任务明确授权，不发布、不启用、不修改生产定时器。
- 外部 Agent 只能使用任务文件声明的权限。写 ERP、调用平台写接口、发送通知和修改 AI Provider 都必须单独列入允许范围。

## 代码与快照

- 本地 `.mjs` 不会自动同步到 Activepieces。修改后必须用 `ap_update_step` 更新对应 CODE 步骤的 `sourceCode`。
- `flow-definition.json` 是节点设置和父子关系的配置快照，不是 Activepieces UI 的原生导入包。
- 修改流程后应同步更新 README 中的修改入口、测试结果和已知限制；不要把尚未验证的运行结果写成成功证据。

