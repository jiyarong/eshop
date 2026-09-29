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
