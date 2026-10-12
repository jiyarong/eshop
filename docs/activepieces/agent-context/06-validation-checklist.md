# 验收清单

## 修改前

- [ ] 已确认目标 Flow ID、环境、发布状态和副作用边界。
- [ ] 已读取当前 `ap_flow_structure`。
- [ ] 已读取将修改步骤的完整 settings；CODE 步骤已读取源码。
- [ ] 已确认每个输入字段的来源、类型、空值语义和日期口径。
- [ ] 已确认没有把密钥、生产数据或平台写接口加入任务。

## 修改后结构检查

- [ ] HTTP 方法、URL、查询参数、鉴权变量和响应路径正确。
- [ ] 步骤引用使用 `step_name['output']` 格式。
- [ ] 动态选项使用 API 返回的 `value`。
- [ ] 新增分支可见且父子关系正确。
- [ ] 缺失值不会被静默转换成零或成功状态。
- [ ] 复杂规则仍按职责拆分，没有无依据的大型 CODE 节点。
- [ ] `ap_validate_flow` 的错误已区分真实错误和项目变量误报。

## 本地回归

根据流程执行对应测试：

```sh
node --test script/activepieces/sku_inventory_health/health.test.mjs
node --test script/activepieces/ozon_listing_diagnosis/diagnosis.test.mjs
```

没有对应测试时，至少应提供脱敏 fixture、输入边界和期望输出，不应只报告“节点执行成功”。

## Activepieces 验收

- [ ] 已运行 `ap_validate_flow`。
- [ ] 已运行完整 `ap_test_flow`，不是只测单个步骤。
- [ ] 已用 `ap_get_run` 查看关键 HTTP、Mapper、Router、CODE 和最终报告输出。
- [ ] 最终报告中的必填字段非空，状态、分支和数值有证据。
- [ ] 数据不足时输出明确的降级状态，未生成伪造建议。
- [ ] 流程没有发生未授权写入、发布、启用或消息发送。

## 交付记录

交付时应记录：Flow URL、测试环境、运行 ID、修改步骤、测试命令、关键输出、失败项、已知限制和是否需要人工发布。不要只提供截图或“测试通过”一句话。

