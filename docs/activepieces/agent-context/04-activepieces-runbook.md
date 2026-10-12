# Activepieces 操作 Runbook

外部 Agent 应按阶段执行，并在每个阶段留下可检查的结果。

## 1. 发现当前状态

```text
ap_list_flows
ap_flow_structure(flow_id)
ap_read_step_settings(flow_id, step_name)
ap_read_step_code(flow_id, step_name)   # 仅 CODE 步骤
```

先确认流程 ID、状态、发布状态、测试环境、真实步骤名、父子关系和分支位置。禁止只根据 README 或旧快照修改流程。

## 2. 研究组件

配置新组件前：

```text
ap_research_pieces
ap_get_piece_props
ap_resolve_property_options
ap_resolve_property_chain
```

动态下拉字段必须使用返回的 `value`，不能使用显示标签。新流程可以用 `ap_build_flow` 创建触发器和顺序步骤；Router、分支和复杂关系仍需使用 `ap_add_step`、`ap_add_branch`、`ap_update_branch` 逐步配置。

## 3. 设计后再修改

修改前先记录：

- 要修改的真实步骤名和原因。
- 输入来源和输出字段路径。
- 缺失值、HTTP 错误和数据冲突的处理。
- 允许的外部副作用。
- 本地规则测试和流程测试命令。

已有流程使用 `ap_update_step` 或 `ap_update_trigger`。不要删除重建，以免丢失样本数据。

## 4. 同步代码和快照

本地 `.mjs` 修改后，用 `ap_update_step` 将源码同步到对应 CODE 步骤。然后更新相关 README、测试样本和 `flow-definition.json`，使本地审查材料能反映实际画布状态。

## 5. 验证顺序

```text
ap_validate_flow
ap_test_flow
ap_get_run(run_id)
```

`ap_validate_flow` 的结果只能说明结构校验情况。必须检查完整运行的关键输出、分支、错误和最终证据。单步测试成功不能代替完整流程验收。

当前已知限制：`ap_validate_flow` 可能把 `{{variables[...]}}` 中的 `variables` 误认为步骤名。若完整测试确认鉴权成功，应保留正确变量引用，同时记录该误报；不能因此把 token 硬编码。

## 6. 发布边界

默认只修改未发布、停用草稿并在 TESTING 环境测试。只有任务明确要求时才执行发布、启用、定时器修改、Provider 修改、ERP 写入或平台写接口。

