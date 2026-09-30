# SKU 多规则诊断与 Planner：Plan / Evaluation 体系实施方案

## 1. 汇报摘要

### 目标

建立一个按自然周运行的闭环：

```text
本周 Diagnosis -> 本周 Planner Plan -> 运营执行 -> 下周 Evaluation -> 下周 Planner 使用历史结果
```

需要解决两件事：

1. 下一周运行 Planner 时，自动评估上一周生成的 Plan，并持久化执行结果和效果判断。
2. 下一周 Planner 读取上一周以及更长周期的 Plan / Evaluation Context，避免重复无效动作，保留有效经验。

### 推荐结论

- 使用周一至周日作为统一自然周。
- 将“计划集合”抽象为 SKU 级 `Planning Cycle`。
- 将计划执行状态和效果评估状态分开管理。
- Evaluation 单独建表，保留原始指标、动作证据、AI 判断和评估版本。
- `is_latest` 仅用于当前页面展示，不承担历史生命周期职责。
- 用统一周度编排 Job 串联 Evaluation、Diagnosis 和 Planner。

## 2. 当前实现与主要缺口

### 当前实现

- `Ec::SkuOperationPlan` 已有 `status`、`plan_date`、`retain_until`、`is_latest`、`operation_actions`。
- `OperationAction` 已有 `plan_id`，部分 Listing 变更可以自动匹配计划。
- `SkuOperationActionEffectDiagnosis` 已有逐周利润、库存、漏斗指标和前后窗口计算。
- Planner 当前只读取最新非 `info` 诊断事件。
- Planner 提示词已经定义了历史 Evaluation 的使用原则。

### 主要问题

1. `plan_date` 是生成日期，不是计划执行周期。
2. `retain_until` 默认 48 小时，无法覆盖一周执行窗口。
3. 动作匹配只读取 `latest.active.retained` 计划，下一周生成新计划后，上一周计划可能无法接收晚到动作。
4. 现有 action 效果诊断按 SKU 聚合，没有直接绑定到 Plan。
5. 现有配置中 `sku_planner` 已被注释，Diagnosis 与 Planner 尚未形成可靠的周度流水线。

## 3. 目标生命周期模型

### 3.1 Planning Cycle 生命周期

一个 SKU 每个自然周对应一个计划集合：

```text
pending -> generating -> active -> closed -> evaluated
                         \-> failed
```

| 状态 | 含义 |
| --- | --- |
| `pending` | 等待生成 |
| `generating` | Planner 正在运行 |
| `active` | 本周计划可以执行 |
| `closed` | 执行窗口结束，不再自动匹配新动作 |
| `evaluated` | 已完成初次 Evaluation |
| `failed` | 生成或评估失败，可重试 |

### 3.2 Plan 条目状态

Plan 不使用一个字段表达所有含义，拆成三个维度：

```text
lifecycle_status: active / cancelled / expired
execution_status: not_started / partial / executed / not_applicable
evaluation_status: pending / insufficient_data / evaluated / failed
```

例如：

```text
lifecycle_status: active
execution_status: executed
evaluation_status: pending
```

表示动作已经执行，但还没有等到下一周的效果评估。

现有 `done` 可以兼容映射为 `execution_status=executed`，不应再表示整个 Plan 生命周期结束。

### 3.3 周期时间窗口

每个计划集合需要明确：

```text
period_start       # 周一
period_end         # 周日
execution_deadline # 周日 + 宽限期，例如 1~3 天
```

`retain_until` 仅作为动作自动匹配的宽限期，不能代替生命周期字段。

## 4. 数据模型设计

### 4.1 计划表扩展

在 `ec_ai_sku_operation_plans` 增加：

```text
planning_period_start :date
planning_period_end   :date
execution_deadline    :date
execution_status      :string
evaluation_status     :string
```

保留现有字段：

- `plan_date`：生成日期，兼容旧数据和页面展示；
- `is_latest`：当前展示指针；
- `status`：兼容现有 `active / done / ignored`；
- `plan_id`：通过 `ec_operation_actions.plan_id` 记录实际动作。

### 4.2 Evaluation 表

新增 `ec_ai_sku_operation_plan_evaluations`：

```text
plan_id
observation_from
observation_to
execution_status
effectiveness          # positive / negative / mixed / inconclusive
confidence             # high / medium / low
summary
metrics                # 原始指标与前后差异
evidence               # 动作、数据覆盖、限制条件
action_ids             # Evaluation 时实际观察到的动作快照
conversation_id
evaluator_version
status                 # pending / running / succeeded / failed
evaluated_at
```

建议增加唯一约束：

```text
unique(plan_id, observation_to)
```

这样既支持下一周初评，也支持第 2 或第 4 周延迟复评。

### 4.3 Planning Cycle 父表

第一阶段可以只在 Plan 上增加周期字段。长期建议新增 `ec_sku_planning_cycles`：

```text
sku_id
period_start
period_end
status
revision
planner_conversation_id
diagnosis_event_ids
context_version
```

约束：同一 SKU、同一周期只有一个当前 revision。重跑时保留旧 revision，避免删除历史 Plan。

## 5. Evaluation 方案

新增 `Ec::SkuOperationPlanEvaluationRunner`，按以下顺序执行：

1. 查询上一自然周的 Plan，不使用 `is_latest`。
2. 查询 `plan.operation_actions`，判断是否执行、部分执行或未执行。
3. 复用现有逐周指标查询，获取利润、销量、库存、广告、漏斗等数据。
4. 先计算确定性指标，再调用专用 Evaluation Agent 形成解释。
5. 将原始指标、证据、AI 结论、置信度和版本一次性写入 Evaluation 表。
6. 没有动作时记录 `not_started / not_executed`，数据不足时记录 `inconclusive`，不要把未执行误判为负面效果。

### Evaluation 结果建议

| 维度 | 示例 |
| --- | --- |
| 执行情况 | `executed`、`partial`、`not_executed` |
| 效果 | `positive`、`negative`、`mixed`、`inconclusive` |
| 置信度 | `high`、`medium`、`low` |
| 证据 | 关联 Action、观察周期、数据覆盖率、同期干扰 |

现有 `SkuOperationActionEffectDiagnosis` 的指标序列和窗口逻辑可以抽取为共享服务；存储结果应改为按 Plan 归档，不能继续只保存为 SKU 聚合诊断。

## 6. Planner 历史 Context

新增 `ErpAI::SkuPlannerContextBuilder`，输出结构化、限长的历史上下文：

```json
{
  "cycle": {"start": "2026-09-28", "end": "2026-10-04"},
  "prior_plans": [
    {
      "plan_id": 123,
      "cycle": "2026-09-21/2026-09-27",
      "target": "advertising",
      "operation": "decrease",
      "scope": "LISTING",
      "lifecycle_status": "active",
      "execution_status": "executed",
      "effectiveness": "negative",
      "confidence": "medium",
      "summary": "...",
      "metrics": {}
    }
  ]
}
```

### Context 取值策略

- 默认传最近 4 个周期。
- 最近 8~12 个周期中额外保留负面、不确定、未执行和重复计划。
- 当前 Diagnosis 和当前经营事实始终优先。
- 历史 Evaluation 用于调整边界和判断，不自动复制上一周 Plan。
- Conversation `context` 保存 `history_plan_ids`、`context_version`、当前周期和输入摘要，方便审计和复现。

不使用 `Ec::SkuContextSnapshot` 保存长期 Plan 历史；该快照当前保留期只有 10 天。Plan / Evaluation 应使用自身业务表保存。

## 7. 周度流水线

```text
数据同步完成
    |
    v
评估上一周期 Plan
    |
    v
执行本周期多规则 Diagnosis
    |
    v
构建历史 Plan / Evaluation Context
    |
    v
生成本周期 Planner Plan
    |
    v
运营执行并记录 OperationAction
    |
    +------> 下一周 Evaluation
```

建议新增按 SKU、按周期幂等的周度编排 Job：

1. 计算 `period_start`、`period_end`。
2. 运行上一周期 Evaluation。
3. 等待当前周期所有 Diagnosis Rule 完成。
4. 构建当前 Diagnosis + 历史 Evaluation Context。
5. 运行 Planner。
6. 写入当前 Cycle 和 Plan。

不能只依赖相邻 cron 时间，因为 Diagnosis 和 Planner 都是异步任务；应通过 Job 链或周期级状态确认 Diagnosis 完成后再运行 Planner。

## 8. 分阶段实施计划

### 阶段一：周期和数据结构

- 增加 Plan 周期字段。
- 创建 Evaluation 表、模型、关联和索引。
- 回填旧 Plan 的自然周字段。
- 增加周期边界及时区测试。

**验收：** 任意 Plan 可以明确回答“属于哪一周、何时允许执行、当前是否等待评估”。

### 阶段二：执行归属和 Evaluation

- 调整 `OperationActionPlanMatcher`，允许历史周期 Plan 接收动作。
- 延长动作匹配宽限期。
- 补齐补货、分仓等计划类型的动作归属。
- 抽取现有逐周指标逻辑。
- 实现 Evaluation Runner 和幂等写入。

**验收：** 下一周运行后，上一周每条 Plan 都有明确的执行状态；有动作的 Plan 有指标和效果结论。

### 阶段三：Planner 历史 Context

- 实现 `SkuPlannerContextBuilder`。
- 将历史计划、动作和 Evaluation 压缩为结构化 Context。
- 保存 Conversation 输入版本和引用 ID。
- 更新 Planner 提示词和 Runner。

**验收：** Planner 可以看到上一周期结果，并能区分“有效、无效、未执行、数据不足”。

### 阶段四：周度编排与恢复运行

- 增加统一周度 Pipeline Job。
- 恢复 Planner recurring 配置。
- 增加失败重试、周期锁和幂等保护。
- 首期启用单 SKU或小范围灰度。

**验收：** 连续运行 4 周不重复生成周期、不丢失历史 Plan，失败任务可安全重试。

### 阶段五：页面和运营闭环

- 在 Plan 详情页增加执行状态、Evaluation 状态、效果摘要和证据。
- 增加周期历史视图。
- 所有展示文案继续使用 Rails I18n。

**验收：** 运营可以从一个 Plan 看到计划、动作、结果和下一步建议的完整链路。

## 9. 主要风险与控制措施

| 风险 | 控制措施 |
| --- | --- |
| 新周期覆盖旧周期 | 使用周期字段和 revision，禁止删除历史 Plan |
| 计划执行但未关联 Action | 扩展 Matcher，未自动匹配时允许人工关联 |
| 数据尚未稳定就评估 | 以自然周结束和数据覆盖率作为 Evaluation 门槛 |
| AI 把相关性当因果 | 保存原始指标、同期动作和置信度，提示词要求保守表达 |
| 历史 Context 过长 | 近期完整记录 + 长期异常摘要，设置 token 上限 |
| Planner 早于 Diagnosis 完成 | 使用 Pipeline Job 或周期级完成状态，不依赖 cron 顺序 |

## 10. 最终建议

第一版采用以下最小闭环：

1. Plan 增加自然周字段和执行/评估状态。
2. 新增独立 Evaluation 表。
3. 抽取现有逐周指标逻辑，完成下一周初评。
4. 增加历史 Context Builder，默认传最近 4 周并保留长期异常。
5. 用统一周度 Job 串联 Evaluation、Diagnosis、Planner。

Planning Cycle 父表、延迟复评和结构化 `success_metrics` 可以作为第二阶段增强，避免第一版引入过多抽象。

## 11. 未完成项执行计划提示词

执行状态见第 12 节；下方保留原始验收要求，继续执行时先核对已完成记录。

以下提示词用于交给新的 Agent 执行剩余工作。它以当前代码和本计划为基础，不要重复实现已经存在的 Plan、Evaluation、Planning Cycle、历史 Context 或页面功能。

```text
你负责完成本仓库 SKU Diagnosis -> Plan -> Action -> Evaluation 闭环的剩余工作。

先阅读并遵守：
- 根目录 AGENTS.md；
- docs/sku_plan_evaluation_implementation_plan.md；
- 当前工作区已有修改，不得回滚或覆盖其他 Agent 的改动。

## 业务时间约束

- 所有日期和周期使用 Asia/Shanghai。
- 重要利润数据在每周一 18:00 后才稳定可用。
- 自动 Diagnosis、Evaluation、Planner 必须统一在每周二凌晨执行；目标触发时间为周二 03:30 Asia/Shanghai。
- 周二 Pipeline 处理的当前日期是周二：先评估上一自然周，再运行当前周期 Diagnosis，确认规则完成后生成当前周期 Planner Plan。
- 不允许继续使用周一 07:00 触发闭环，也不允许让自动评估早于上一计划的 execution_deadline。

## 先确认现状

检查以下实现，不要重复造轮子：
- ErpAI::SkuDiagnosisRunner
- ErpAI::SkuPlannerRunner
- Ec::SkuOperationPlan
- Ec::SkuPlanningCycle 与 Ec::SkuPlanningCycleLock
- Ec::SkuOperationPlanEvaluationRunner
- AITasks::SkuPlanningPipelineJob
- Ec::OperationActionPlanMatcher
- ErpAI::SkuPlannerContextBuilder
- config/recurring.yml

## 必须完成的改动

### 1. 统一自动调度

- 将 sku_planning_pipeline 调整为每周二 03:30 Asia/Shanghai。
- 选择唯一的自动编排入口：Pipeline 内部已经同步执行 Evaluation、Diagnosis、Diagnosis gate、Planner，因此不要再用独立 recurring 任务重复执行同一批 Diagnosis。保留 SkuDiagnosisJob 供页面和人工调用；如保留自动入口，必须证明不会与 Pipeline 重复写入。
- 不为 SkuPlannerJob 或 SkuOperationPlanEvaluationJob 增加并行 recurring；它们分别保留为人工 Planner 和人工重新评估入口。
- 更新所有 schedule 测试，明确验证周二 03:30、没有周一旧入口、没有库存健康/动作效果/等级巡检的隐式 recurring。

### 2. 加入数据就绪保护

- Pipeline 在 Evaluation 前检查上一周利润报表及其依赖数据已经达到可用条件；数据不足时使用 Active Job 有限重试或明确的等待状态，不得直接把缺数写成 negative。
- 不要只依赖两个 cron 的先后顺序。将数据就绪判断写成可测试的服务或明确的查询条件，并记录失败原因。
- 检查周一 18:00 之后的利润数据同步与报表刷新是否已经完成；如果仍可能晚到，调整重试窗口或把触发时间延后，但最终必须保持在周二凌晨执行。

### 3. 让自动 Evaluation 真正调用 Evaluation Agent

- Pipeline 调用 Ec::SkuOperationPlanEvaluationRunner 时必须传入 Agent.ensure_fixed!("sku_plan_evaluation") 和 ErpAI::DefaultClient.new。
- 保留当前规则：没有动作时执行状态为 not_started/not_applicable，效果为 inconclusive，不调用 AI 让模型猜测负面效果。
- 有动作时保存 Evaluation Conversation、原始 metrics、evidence、action_ids、evaluator_version、confidence 和 effectiveness。
- 保持按 plan_id + observation_to 幂等，失败可重试并保留 failed 记录。

### 4. 修正执行截止日和观察窗口

- 周二自动评估时，上一周期的 execution_deadline 已经过去，必须能看到截止日前发生的全部 OperationAction。
- 核对 metrics 的 to_date、observation_to 和 execution_deadline 的关系；如果动作宽限期属于评估范围，指标观察窗口也要覆盖同一业务范围，不能出现动作算入评估但指标停在周日的矛盾。
- 完成评估后正确推进 Plan 的 lifecycle_status、evaluation_status 和 Planning Cycle 状态；历史周期不能因为 is_latest 变化而丢失或继续被错误匹配。

### 5. 补齐 Action 归属

- 在不发明新 operation_type 的前提下，检查现有动作记录器实际记录的分仓、入库、补货事件。
- 为 warehouse_distribution 增加正确的目标/操作匹配，或明确现有动作类型无法表达该计划并补齐最小必要的记录字段。
- 添加历史周期、Listing scope、SKU scope、截止日和宽限期的 Matcher 测试。

### 6. 修复 Diagnosis 周期语义

- 周二 Pipeline 必须执行当天适用的 daily 和 weekly Diagnosis Rule。
- Diagnosis gate 必须检查所有启用且适用于 SKU 的规则，不能因为 gate 与 Runner 使用了错误日期而漏掉 weekly 规则。
- 保持 manual 规则只在明确传入 rule_ids 时执行。

## 验收标准

1. config/recurring.yml 只有一个周二 03:30 的闭环自动入口；周一 07:00 不再触发。
2. 以周二日期运行 Pipeline 时，调用顺序严格为 Evaluation -> Diagnosis -> completion gate -> Planner。
3. 自动 Evaluation 在有动作时创建 sku_plan_evaluation Conversation；无动作时为 inconclusive。
4. 上一周期 execution_deadline 之前和宽限期内的动作都能正确归属并进入 Evaluation evidence。
5. weekly Diagnosis Rule 在周二自动执行，Planner 只有在全部适用规则完成后才能运行。
6. warehouse_distribution、replenishment、price、advertising、listing_attribute、listing_image 的已支持动作都有归属测试；无法自动归属的类型必须明确记录为未匹配。
7. 连续运行同一周期两次不会重复创建当前 revision 或重复 Evaluation 行；人工 rerun 才创建新 revision。
8. 所有新增展示文案继续使用 Rails I18n。

## 验证命令

执行 Rails 命令前初始化 rbenv：

    eval "$(/opt/homebrew/bin/rbenv init - zsh)"

至少运行：

    bin/rails zeitwerk:check
    bin/rails test test/jobs/ai_tasks/sku_planning_pipeline_job_test.rb test/jobs/ai_tasks/sku_operation_plan_evaluation_job_test.rb
    bin/rails test test/services/ec/sku_operation_plan_evaluation_runner_test.rb test/services/ec/sku_planning_cycle_lock_test.rb
    bin/rails test test/services/ec/listing_change_recorder_test.rb test/services/ec/sku_batch_action_recorder_test.rb
    bin/rails test test/services/erp_ai/sku_diagnosis_runner_test.rb test/services/erp_ai/sku_planner_runner_test.rb test/services/erp_ai/sku_planner_context_builder_test.rb
    git diff --check

最终报告必须列出：实际自动执行时间、数据就绪判断、Evaluation Agent 是否被自动调用、未匹配动作类型、测试结果和仍存在的风险。
```

## 12. 本次实施记录（2026-09-29）

### 已完成

- 唯一自动入口为周二 03:30 Asia/Shanghai 的 Pipeline；独立 Diagnosis recurring 已移除，人工 Diagnosis、Planner、Evaluation Job 保留。
- 利润源刷新调整到周一 18:00 后：Ozon Performance 18:00、WB 18:10、Ozon accrual 18:30；Google Sheets 报表导出为 20:00。页面报表直接查询本地数据，Pipeline 不依赖导出成功或相邻 cron 的顺序。
- 数据就绪服务核对精确本地周汇率、各活跃店铺的同步完成记录、成功步骤与上一周至周一的日期覆盖。Ozon 配置 Performance 凭据时同时要求广告同步完成；WB 已有销售而尚无周结算报表时等待。零活动的成功响应允许通过。未就绪记录具体原因，并每 30 分钟重试，最多 5 次。
- WB SyncTask 新增 results，WB / Ozon / Performance 同步保存覆盖区间和完成时间；已修正仓储下载重试耗尽、Ozon 冲正补全和分仓 API 失败被吞掉后误报成功的问题。
- Pipeline 自动传入固定 Evaluation Agent 和 DefaultClient。有动作且利润可用时保存 Conversation、原始指标、动作证据、同期其他动作、效果与置信度；AI 失败保留输入与 Conversation，并在同一 Evaluation 行上重试。无动作或缺少利润时保持 inconclusive。
- 新计划默认宽限期为 1 天，截止周一结束；历史截止日保留，不做缩短截止日的数据迁移。自动评估只选择截止日已过去的计划，并补跑更早仍未完成完整窗口的计划。
- 动作、日库存、漏斗和观察范围利润查询均覆盖 observation_to；人工提前评估截止到上海时区上一完整日，完成后仍会在截止日后自动补评。尚无完整日时人工页面不入队。
- Matcher 支持价格/广告预算的增加与降低、广告开关、Listing 属性/图片修改、采购数量增加和有正 SKU 数量的已知发运状态及入库量增加。历史非 latest、SKU/Listing 范围、计划创建时点和宽限期边界均已补测试。
- 周二 Diagnosis 同时执行 daily 与 weekly；gate 核对当前周期与本次运行产生的最新规则事件，排除 advise，修复 Array 与 Set 运算错误；manual 仍需显式 rule_ids。
- 自动 Planner 同周期重试复用当前 revision，已完成周期不重复生成；人工 rerun 创建新 revision，旧 Plan / Conversation 保留。历史回填 Diagnosis 不会仅因生成时间较晚而成为最新事件。
- Planner 的共同入口 `SkuPlannerRunner` 在读取历史 Context 前自动执行到期历史计划的 Evaluation，人工入口与直接调用同样生效。没有待评估历史时直接规划，已成功完成完整窗口的评估不重复执行；数据未就绪或 Evaluation 失败时暂停 Planner，人工 Job 有限重试。新生成计划须待执行窗口结束后再评估。

### 明确不自动匹配

- manual_note、未知或取消的发运状态、无正数量的发运事件；
- 入库数量减少/到货消减，不能据此推断计划主动降低分仓；
- replenishment / warehouse_distribution 的 decrease、无实际字段变更的 maintain。

这些动作或计划缺乏确定的执行语义，保留未匹配状态，不增加新 operation_type，也不把建议事件当成运营执行。

### 部署与后续验收

- 新迁移 `20260929111007_add_results_to_raw_wb_sync_tasks.rb` 需在部署环境执行；本次仅迁移测试数据库。
- WB 观察窗延伸到周一，但利润源仍按已发布结算报表归集；指标中记录 published_settlement_reports 与 provisional_profit_from，周一完整日利润尚不能确认。Ozon 使用 daily_accruals。
- 平台成功返回空数据但稍后补发、WB 仓储 T+2/T+3 修订仍是外部数据风险；源完成记录和已有销售核对不能证明所有平台数据永不修订。
- 生产需先以单 SKU 灰度确认真实 Agent 调用与源数据可用性，再完成连续 4 周验收。本地测试不等于真实平台同步、外部 AI 或四周生产验证。

### 验证结果

- Planner 前置历史评估补充验证（人工 Job、周度 Pipeline、Planner、历史 Context、Evaluation、数据就绪和周期锁）：50 runs / 227 assertions，0 failures / 0 errors，覆盖评估结果先进入 Planner Context、成功结果不重复评估、开放执行窗口跳过、评估失败阻止生成及后台重试。
- 闭环 Job、Evaluation、数据就绪、周期锁、指标查询、Matcher、Diagnosis、Planner、历史 Context、调度及 WB/Ozon 同步相关测试：120 runs / 584 assertions，0 failures / 0 errors。
- 新增人工重新评估入口测试：2 runs / 9 assertions，0 failures / 0 errors。名称过滤使用 `-i '/plan_reevaluation/'`。
- `bin/rails zeitwerk:check`、Ruby 语法检查、`git diff --check` 均通过；Rails 验证使用 `SKIP_JS_BUILD=1`。
- 完整 `test/controllers/reports_controller_test.rb`：83 runs / 1092 assertions，17 failures / 0 errors；失败集中在其他报表页面的标签、抽屉、利润趋势及登录重定向断言，新增两个重新评估测试通过。整文件尚未全绿，本次未扩展修改这些页面。
