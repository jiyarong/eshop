# SKU 原结构快照与案例

数据来源使用现有 `Ec::SkuContextSnapshot.capture_for` 的只读 Context 查询。这里不调用会写 `Ec::Snapshot` 的 Fetcher、不调用平台同步、不运行 Agent，也不创建真实诊断事件或计划。

## 采集与编辑

```sh
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
RAILS_ENV=development bin/rails runner script/ai_evals/capture.rb JJ005-6 2026-10-15
```

命令读取当前应用环境数据库，写入 `snapshots/JJ005-6/2026-10-15/`，并尝试生成三个 YAML 草稿：断货、利润 P-1 缺失、CLR 清仓。目标目录或案例已存在时拒绝覆盖；修订应保存为新版本。采集日期控制现有 Query 的 `as_of`，不意味着可以从今天的数据库精确重建过去所有状态；manifest 中 `metadata.capture_semantics=current_database_as_of_queries` 明确这一限制。真正历史回放应保留当时采集的完整包。

现有 `script/activepieces/*/fixtures/JJ005-6.json` 是 2026-10-10 场景的 Data Mapper 输出，缺少完整原始 V3 响应，因此这里没有把它们伪装成新的原始 SKU 快照。请先采集或导入真实 raw snapshot，再生成案例。三个模板的 Oracle 断言留空，必须补充并人工审核后才能作为满分答案。

```ruby
snapshot = AiEval::Snapshot.load(Rails.root.join("script/ai_evals/snapshots/JJ005-6/2026-10-15"))
case_definition = AiEval::Case.load(Rails.root.join("script/ai_evals/cases/jj005_6_stockout.v1.yml"))
result = AiEval::Materializer.call(case_definition, snapshot: snapshot)
result.documents # V3 原结构与同源重建的 unified_snapshot.json
```

数据库 JSONB 中保存相同 `manifest` 和 `documents` 时，使用 `AiEval::Snapshot.from_documents(manifest:, documents:)` 获得等价校验。导入包对象格式为 `{ "manifest": {...}, "documents": { "v3/base_context.json": {...}, ... } }`。

## 原始结构与 Patch

V3 文件保留线上响应的 `data` 信封。`unified_snapshot.json` 保留现有 `categories.<section>.raw_json/markdown`，供 Rails 诊断使用。V3 是变异真源，统一快照在每次物化时从变异后的 V3 同步生成。Activepieces 应读取这些 V3 文件，通过现有 Data Mapper 处理；不另存一套新的业务 DTO。

```yaml
case_key: jj005_6_stockout
version: 1
base_snapshot: JJ005-6/2026-10-15
time_zone: Asia/Shanghai
date_mode: { type: none }
patches:
  - target: v3/inventory_context.json
    op: replace
    path: /data/inventory/current_inventory_info/values/book_stock
    value: 20
    reason: 模拟库存不足
derived_fields:
  mode: recompute
  paths:
    - /data/inventory/current_inventory_info/values/turnover_days
    - /data/inventory/current_inventory_info/values/turnover_days_with_procurement
    - /data/inventory/current_inventory_info/values/strict_forecast_cover_days
oracle:
  diagnosis: { assertions: [] }
```

支持 RFC 6902 的 `add/remove/replace/test/copy/move`。字段替换要求原路径存在；禁止新增快照中不存在的业务字段、改变字段类型或使用未知的 Listing/店铺/Product 关联 ID。数组可复制已有结构后添加记录；空数组没有结构样本，第一版拒绝从空数组构造新记录。`null` 保持缺失含义，不自动转成 0。

派生字段 `preserve` 保留显式 Patch 结果；`recompute` 第一版仅支持上述三项库存覆盖天数，两项周转天数复用 `Ec::InventoryReportRowMetricsBuilder`，严格预测覆盖天数采用线上 Detail Query 的同一公式。缺失依赖返回 `null`。未知公式明确拒绝，其他指标需显式 Patch；涉及生命周期、分店铺明细等相关字段时需一并修改。`inject_conflict` 可保留故意的身份/日期冲突，但 `result.metadata[:validation_errors]` 会记录门禁错误，执行器必须据此阻断正常评分。

## 时间规则

固定历史回放使用 `date_mode: {type: none}`。按周滚动可使用 `{type: shift, days: 7}`，也可在调用 `Materializer.call(..., anchor_date: Date.new(...))` 时指定运行锚点。为保持上海自然周的周一/周日边界，含 `week_starts_on`、周字段、`period_key` 或计划 cycle 的快照只允许 **7 天的整数倍平移**；非同星期的 anchor 会明确拒绝。

日期平移仅处理 `MaterializerDateShifter::FIELDS` 列出的字段、计划 cycle 的 start/end 和 `sales_amount_last_3_months` 的日期键；SKU、自由文本、`period_key` 标签不做字符串替换。V3 分类 markdown 自动重建。Supplemental Listing markdown 是原始不透明文本；其中包含日期时，第一版拒绝时间平移，需重新采集，避免旧日期证据与新锚点混用。图片仅保存原有附件引用，不在这里下载图片或创建永久外链。

## 校验与文件

- `manifest.json` 同时保存文件字节 SHA-256 和排序后的 JSON 内容 SHA-256。文件读取可发现文件被改动，JSONB 导入可容忍对象键顺序变化。
- manifest 和数据文件路径拒绝 `..`、绝对路径及越界 symlink；数据文件必须在 manifest 中列出。
- 所有 Context 的 schema version、SKU、时区和 `period.as_of` 必须一致；声明的 sections 必须与 V3 文件一致。
- `schemas/` 记录 v1 的编辑器/API 契约；运行时服务对关键必填项、Patch 和物化结果执行同样的约束，不依赖额外 JSON Schema gem。
- `supplemental/` 保存 Listing 文本、产品属性及图片附件引用；manifest metadata 保存当次 Listing、规则定义和 Planner 历史 Context，不包含 Provider 凭据。

```sh
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
bin/rails test test/services/ai_eval/snapshot_materializer_test.rb test/services/ai_eval/snapshot_capture_test.rb
```
