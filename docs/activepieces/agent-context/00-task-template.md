# Activepieces 任务增量模板

将本文件复制一份作为每次任务的输入。稳定规则在其他 context 文件中维护，任务文件只描述本次要做的事情。

```yaml
workflow:
  existing_flow_id: ""
  existing_flow_url: ""
  name: ""
  environment: TESTING
  published: false

objective:
  - ""

scope:
  include:
    - ""
  exclude:
    - ""

trigger:
  type: manual
  sample_data: {}

inputs:
  sku_code: ""
  parameters: {}

data_sources:
  - name: ""
    method: GET
    path: ""
    query_params: {}
    response_path: "body.data"
    required_fields: []

output_contract:
  required_fields: []
  statuses: []
  evidence_fields: []

side_effect_policy:
  allowed:
    - read_erp_api
    - modify_disabled_draft
    - run_testing
  forbidden:
    - publish
    - enable
    - write_erp_data
    - platform_api_write
    - send_message

acceptance:
  local_commands: []
  activepieces_checks:
    - ap_validate_flow
    - ap_test_flow
    - ap_get_run

known_constraints:
  - ""
```

提交给 Agent 的任务说明还应明确：

- 是创建新流程还是修改已有草稿。
- 是否允许修改触发器、项目变量、Provider、连接和环境状态。
- 是否允许执行真实 API、写入 ERP、发消息或调用平台写接口。
- 失败时应该停止流程、返回 `insufficient_data`，还是允许继续到报告节点。
- 哪些输出字段必须有来源和计算证据。

