# SKU 快照克隆与 Agent 评测计划

## 实施进展（2026-10-15）

首版已落实在当前工作区，使用入口为 `/admin/ai_evals`。操作步骤与边界见 [使用与验收](02-使用与验收.md)。

| 阶段 | 已实现 | 后续事项 |
| --- | --- | --- |
| P0 | 真实原结构采集、不可变快照、Patch、整周日期平移、3 个场景草稿；JJ005-6 本地只读采集与模板物化通过 | 人工填写并批准各业务满分答案 |
| P1 | Diagnosis / Planner / Plan Evaluation 内存适配器、真实 Provider 调用入口、结构化评分、运行记录与版本 | Listing 图片上下文回放、语义 Judge、更多派生公式 |
| P2 | 文件/运行 Fixture Gateway、同指纹校验、Activepieces Run ID 与手工回传评分 | 部署后连接独立 Eval Flow；自动执行、读取 run 与步骤证据 |
| P3 | ERB 管理页、Web Agent 生成草稿、字段 diff、批准与新版本、异步运行、基线对比、人工复核 | 重复运行统计、成本汇总、更多编辑表单 |

测试数据库已迁移；未迁移 development、未部署、未调用付费真实模型、未修改或发布线上 Activepieces。下文保留整体目标；未实现的能力不能作为本次验收结论。

## 目标

建设一个统一的 AI Eval Hub，使用真实 SKU 的线上快照作为基线，通过 JSON Patch 做局部变异，在保持线上 API/Context 结构不变的前提下，评估：

- SKU Diagnosis Agent 和各诊断规则；
- SKU Planner Agent；
- SKU Operation Plan Evaluation Agent；
- Activepieces 中的 SKU 诊断、库存健康度和 Listing 诊断流程；
- 数据缺失、周期冲突、库存/利润边界和错误工具调用等安全行为。

测试运行必须支持真实模型线上调用，但默认不写入诊断事件、计划、ERP、平台 API 或消息系统。

## 已确认的设计原则

1. 测试数据以实际 SKU 为源，不重新定义一套业务 DTO。
2. 保存完整原始响应，变异通过 JSON Patch 或受控日期平移表达。
3. Rails Agent 和 Activepieces 使用同一份变异后的数据。
4. 满分答案使用结构化断言，由人工审核后锁定；自然语言只做辅助语义评分。
5. 输入窗口、执行窗口、观察窗口和未来 Oracle 数据严格隔离。
6. 数据集和 Oracle 版本不可原地修改，运行结果保存模型、Prompt、规则和 Flow 版本。

## 总体结构

```text
真实 SKU 只读采集
        ↓
不可变 Snapshot Pack
        ↓
JSON Patch / 日期平移 / 派生字段重算
        ↓
变异后的统一数据源
   ┌────┴──────────────┐
Rails Diagnosis/Planner  Activepieces Fixture Gateway
   └────┬──────────────┘
        ↓
结果规范化 → 断言评分 → 基线回归 → 人工复核
```

## 快照格式

快照包以真实响应为主，不做业务字段改名：

```text
script/ai_evals/snapshots/<sku_code>/<snapshot_date>/
  manifest.json
  unified_snapshot.json
  v3/base_context.json
  v3/inventory_context.json
  v3/lifecycle_context.json
  v3/profit_context.json
  v3/sales_funnel_context.json
  v3/advertising_context.json
  v3/orders_context.json
  v3/supply_orders_context.json
  v3/operation_actions_context.json
  v3/warehouse_recommendation_context.json
  v3/search_terms_context.json
  supplemental/listing_context.json
  supplemental/product_attributes.json
  supplemental/image_references.json
```

`unified_snapshot.json` 保留现有快照 categories 结构；`v3/*.json` 保留 HTTP 边界的真实结构，并作为 Rails/Activepieces 变异输入的同一真源。采集直接调用只读 Context Builder，不调用会保存和清理业务快照的 Fetcher。manifest 保存 checksum、来源环境、SKU、采集时间、时区和周期。

如果某个测试必须验证数据库 Query 或 Plan Evaluation 指标查询，再增加可选的 DB Snapshot Pack；第一版优先覆盖 Context/API 边界，避免复制无关的生产表。

## 案例格式

案例引用基线快照，并保存 Patch、日期策略、派生字段策略和 Oracle：

```yaml
case_key: jj005_6_stockout_critical
base_snapshot: JJ005-6/2026-10-10
version: 1
time_zone: Asia/Shanghai
date_mode:
  type: shift
  days: 7

patches:
  - op: replace
    target: v3/inventory_context.json
    path: /data/inventory/current_inventory_info/values/book_stock
    value: 20
    reason: 模拟即将断货
  - op: replace
    target: v3/inventory_context.json
    path: /data/inventory/current_inventory_info/values/incoming_quantity
    value: 0
    reason: 模拟无在途库存

derived_fields:
  mode: recompute
  paths:
    - /data/inventory/current_inventory_info/values/strict_forecast_cover_days
    - /data/inventory/current_inventory_info/values/turnover_days_with_procurement

windows:
  input: { from: -28d, to: -1d }
  plan: { from: 0d, to: 6d }
  observation: { from: 0d, to: 7d }

oracle:
  diagnosis: {}
  planner: {}
  activepieces: {}
```

支持字段替换、数组记录增删和受控日期平移。日期字段按允许列表识别；含自然周的快照仅允许 7 天整数倍平移。`preserve`、`recompute`、`inject_conflict` 明确控制派生字段是否同步。上面的 `windows` 是目标设计中的描述字段，首版尚未实现相对窗口表达式；实际输入沿用原 API 周期，Evaluation 对已知指标日期和动作截止日执行门禁。

## Web Agent 辅助编辑

Web Agent 只能生成 Patch、派生字段建议和 Oracle 草稿，不直接重写快照或写入业务系统。交互步骤：

1. 选择真实 SKU 快照。
2. 用自然语言描述场景，例如“模拟 14 天内断货，同时删除利润 P-1”。
3. 提交后立即返回，Agent 通过现有 default 后台队列生成字段路径、修改前后值、Patch、重算字段和预期影响；任务保存提交时的案例定义、场景及排队/生成/完成/失败状态。
4. 系统执行 schema、类型、枚举、SKU、日期、关联 ID 和依赖校验。
5. 页面点击“刷新进度”查看后台结果；完成后回填候选 JSON 并显示 diff，用户确认后保存为新案例版本。失败时保留原输入和错误，可重新提交；后台生成不修改原案例或批准 Oracle。
6. Agent 可生成 Oracle 草稿，但必须人工批准后才能用于评分。

Agent 的输入需要限制在当前快照、字段目录和业务规则中；不得凭空增加字段、Listing、诊断事件或动作。

## 运行模式

| 模式 | 模型 | 数据 | 首版 |
| --- | --- | --- | --- |
| `offline` | 模拟或本地 | 快照/Fixture | 测试代码注入 Client，未开放管理页 |
| `online_synthetic` | 真实模型 | 变异快照 | 已实现，可指定整周锚点 |
| `live_readonly` | 真实模型 | 线上 GET | 后续实现 |
| `historical_replay` | 真实模型 | 固定历史快照 | 已实现，保持案例固定日期 |

`online_synthetic` 是默认验收模式。`live_readonly` 只运行白名单 SKU，并保留 HTTP 调用证据。

## 运行状态

首版案例版本：`draft → approved → archived`。保存与批准时执行校验；批准版本不可解锁修改，编辑创建新草稿。

运行状态：`queued → materializing → diagnosis_running → planner_running → activepieces_running → scoring → passed/failed/blocked/error`。

- `blocked`：安全、结构或数据门禁失败，不进入普通业务评分。
- `failed`：完整执行结束，但业务断言失败。
- `error`：模型、网络、Activepieces 或基础设施错误。

## 评分规则

每条断言包含：`path`、`operator`、`expected`、`weight`、`severity`、`evidence`。已支持 `eq`、`one_of`、`include`、`exclude`、`exists`、`numeric_close`、`range`、`subset` 和安全子集 `jsonpath`。`semantic_fact` 尚未实现，使用时明确阻断，不返回虚假的满分。日期预期可显式设置 `shift_dates: true` 随运行锚点平移。

推荐适配器权重（在 Oracle 中显式配置 `category_weights`；留空按断言权重评分）：

| 适配器 | 结构身份 | 业务结论 | 证据 | 缺失数据 | 工具/动作 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Diagnosis | 15 | 40 | 20 | 15 | 10 |
| Planner | 15 | 35 | 20 | 10 | 20 |
| Activepieces | 15 | 35 | 25 | 15 | 10 |
| Plan Evaluation | 15 | 35 | 25 | 15 | 10 |

默认通过条件：总分不少于 90、所有 critical 断言通过、没有安全门禁失败。自然语言完整匹配不作为主要评分依据；关键业务字段和工具调用优先使用结构化结果评分。

以下情况直接阻断：错误 SKU/规则/Listing、Planner 引用其他 SKU 事件、无动作却判定 negative、缺失数据被当作零或健康、未来数据泄漏、Activepieces 未授权写入。

## 验收层次

### 案例数据验收

- Snapshot checksum 正确。
- Patch 可重复应用且结果稳定。
- 不引入线上不存在的字段。
- SKU、schema version、日期、时区、周期一致。
- `null`、空数组和 `available_metrics` 语义保持不变。
- 输入、计划、观察和 Oracle 窗口隔离。

### 执行安全验收

- Rails 工具调用进入 `EvaluationToolExecutor`，不写真实事件/计划。
- Activepieces Fixture 模式只读 Fixture Gateway。
- Live 模式仅允许 GET、白名单 SKU 和只读接口。
- 记录工具调用、HTTP 调用、Activepieces run ID、模型和 Prompt hash。

### 业务结果验收

- Diagnosis：严重级别、事件类型、证据和数据不足处理。
- Planner：目标、操作、范围、Listing、referer、周期和优先级。
- Plan Evaluation：动作状态、观察窗口、效果、置信度和证据。
- Activepieces：最终 status、Router 分支、metrics、alerts、evidence 和 null 语义。

### 基线回归验收

保存每次运行与基线的分数、断言、输出、延迟、Token、成本和 Activepieces run ID 差异。断言可由人工标记为真实缺陷、Oracle 需要更新、案例错误或可接受差异；更新 Oracle 必须生成新版本。

## 交互页面

建议采用 Rails ERB + Turbo：

- `/admin/ai_evals`：管理首页，采集、导入和最近记录。
- `/admin/ai_evals/snapshots/:id`：查看和校验快照，创建案例。
- `/admin/ai_evals/cases/:id`：编辑 Patch、预览 diff、批准 Oracle。
- `/admin/ai_evals/cases/:id/runs/new`：配置模式、适配器、规则和基线。首版使用对应内置 Agent 当前模型配置，重复次数和独立模型覆盖尚未开放。
- `/admin/ai_evals/runs/:id`：运行时间线、评分、Expected/Actual diff、证据、工具调用和回归结果。

## Activepieces 接入

创建独立的 Eval Flow，参数包含 `snapshot_id`、`case_key`、`source_mode` 和 `anchor_date`。Fixture 模式通过保持线上路径和响应信封的 Fixture Gateway 供数；现有生产草稿不直接改成测试分支。验收顺序为本地 Node 测试、`ap_validate_flow`、完整 `ap_test_flow`、`ap_get_run`。

## CLI 草案（Rake 命令尚未实现；可用命令见使用文档）

```sh
bin/rails ai_eval:capture SKU=JJ005-6 AS_OF=2026-10-10
bin/rails ai_eval:validate CASE=jj005_6_stockout_critical
bin/rails ai_eval:run CASE=jj005_6_stockout_critical MODE=online_synthetic
bin/rails ai_eval:report RUN_ID=...
```

## 分阶段实施

### P0：契约和基线

- Snapshot Pack manifest 和 checksum。
- JSON Patch、日期平移和 schema 校验。
- 一个真实 SKU、三个变异案例和人工 Oracle。

### P1：Rails Agent 评测

- EvaluationToolExecutor。
- Diagnosis、Planner、Plan Evaluation 适配器。
- 结构化断言评分和运行记录。

### P2：Activepieces 评测

- Fixture Gateway。
- 独立 Eval Flow。
- Activepieces 输出规范化和 run 结果评分。

### P3：交互和回归

- 快照/案例/运行管理页面。
- Web Agent Patch 生成和 diff 审核。
- 基线对比、人工复核和数据集版本发布。

## 首个端到端验收目标

以 `JJ005-6` 为基线，生成“模拟断货”案例，使用同一份变异快照运行 Diagnosis、Planner 和库存 Activepieces 流程，得到字段级评分、工具调用记录、Activepieces run ID 和基线差异；全过程不写入真实诊断事件、计划、ERP、平台 API 或消息系统。

