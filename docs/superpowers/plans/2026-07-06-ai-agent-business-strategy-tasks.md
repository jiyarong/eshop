# AI Agent Business Strategy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the MVP business loop from `docs/20260706-AI-Agent策略.md`: operation event -> SKU business profile -> Grade/Stage diagnosis -> monitoring review.

**Architecture:** Keep deterministic metrics in Rails services and use AI only for explanations, review wording, and recommendations. Treat the six "Agents" as bounded Rails capabilities: records, query services, rule services, background jobs, and optional AI report generation, not six independent chatbots. MVP ships the first four capabilities; alerts and Copilot stay as phase 2.

**Tech Stack:** Rails 8, ActiveRecord, ERB + Turbo/Hotwire, Rails I18n, Solid Queue jobs, existing `Agent` / `Conversation` AI infrastructure, Minitest.

---

## Assumptions And Success Criteria

- MVP scope is the first four modules from the strategy document: operation events, SKU business profile, Grade/Stage diagnosis, and monitoring review.
- No automated price, ad, replenishment, or clearance execution is included.
- Financial, ROI, order attribution, and inventory calculations remain deterministic Rails code.
- AI output is stored as structured JSON and always traceable to a SKU, event, task, and metric context.
- HTML pages use existing Rails views and I18n; JSON endpoints remain available where introduced.
- Order-to-SKU attribution must join through `ec_sku_products` with platform/store constraints.
- Business thresholds for Grade/Stage need owner confirmation before production enablement.

## File Structure

- Modify: `app/models/ec/sku.rb`
  - Add business Grade/Stage enum-like validations and associations to operation events.
- Create: `app/models/ec/operation_event.rb`
  - Stores semantic operation actions, intent, expected effect, observe window, and tags.
- Create: `app/models/ec/monitoring_task.rb`
  - Tracks post-event observation windows and review status.
- Create: `app/models/ec/ai_analysis_report.rb`
  - Stores structured AI or rule-generated analysis reports.
- Create: `app/services/ec/order_item_sku_product_join.rb`
  - Centralizes the required order item -> SKU product binding SQL.
- Create: `app/services/ec/sku_business_profile_query.rb`
  - Produces the structured SKU business context JSON.
- Create: `app/services/ec/sku_strategy_diagnosis.rb`
  - Applies deterministic Grade/Stage/health/main-constraint rules to the profile.
- Create: `app/services/ec/monitoring_task_factory.rb`
  - Creates observation tasks from operation events.
- Create: `app/jobs/ec/monitoring_task_review_job.rb`
  - Generates due monitoring reports.
- Modify: `app/controllers/reports_controller.rb`
  - Add SKU strategy tab data loading.
- Create: `app/controllers/erp/operation_events_controller.rb`
  - Manual operation event entry.
- Modify: `config/routes.rb`
  - Add operation event routes and strategy report routes.
- Modify: `config/locales/zh.yml`, `config/locales/en.yml`, `config/locales/ru.yml`
  - Add all visible labels.
- Create/modify: `app/views/reports/*`, `app/views/erp/operation_events/*`
  - Add strategy dashboard sections and event forms.
- Test: `test/models/ec/*`, `test/services/ec/*`, `test/controllers/*`
  - Cover persistence, deterministic metrics, rules, pages, and I18n-visible UI.

## MVP Milestones

1. Data foundation: semantic events, monitoring tasks, AI report persistence, business Grade/Stage fields.
2. Business profile: one deterministic JSON context per SKU, reusable by pages, rules, AI, and jobs.
3. Strategy diagnosis: rule-first Grade/Stage/health/main-constraint output, with manual confirmation.
4. Monitoring review: create observe tasks after events and generate structured review reports.
5. UI integration: SKU list/detail becomes an operation dashboard without replacing existing reports.
6. Phase 2 backlog: anomaly alerts and SKU Copilot.

---

### Task 0: Confirm Business Rule Thresholds

**Files:**
- Create: `docs/superpowers/specs/2026-07-06-ai-agent-business-rule-thresholds.md`

- [ ] **Step 1: Write the rule confirmation note**

Create the spec with this content:

```markdown
# AI Agent Business Rule Thresholds

## Grade Inputs

- S: annualized net profit threshold, ROI threshold, growth requirement, stock risk exception.
- A: annualized net profit threshold, ROI threshold, growth or stability requirement.
- B: validation threshold, minimum sales activity, low-cost operation condition.
- C: clearance/low-value threshold, loss threshold, resource stop condition.

## Stage Inputs

- NEW: validation age/window, minimum listing readiness, first sales signal.
- GRW: growth target, inventory readiness, ad/resource expansion condition.
- MAT: stable profit condition, acceptable volatility.
- CLR: clearance goal, target clear-out period, ad/resource limitation.

## Health Inputs

- Green: conforms to current Grade/Stage target.
- Yellow: one risk needing weekly attention.
- Red: immediate action required.

## Main Constraint Categories

- inventory
- product_competitiveness
- advertising_efficiency
- price_competitiveness
- platform_difference
- clearance_execution
- data_gap
```

- [ ] **Step 2: Capture the decision**

Ask the business owner to fill the thresholds before enabling automatic suggestions in production. Until then, implementation uses named constants in `Ec::SkuStrategyDiagnosis` and labels them as MVP defaults in code comments and tests.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-06-ai-agent-business-rule-thresholds.md
git commit -m "docs: capture AI business rule thresholds"
```

---

### Task 1: Add Business Event And Review Tables

**Files:**
- Modify: `db/schema.rb` via Rails migrations only
- Create: `app/models/ec/operation_event.rb`
- Create: `app/models/ec/monitoring_task.rb`
- Create: `app/models/ec/ai_analysis_report.rb`
- Modify: `app/models/ec/sku.rb`
- Test: `test/models/ec/operation_event_test.rb`
- Test: `test/models/ec/monitoring_task_test.rb`
- Test: `test/models/ec/ai_analysis_report_test.rb`

- [ ] **Step 1: Generate migrations**

Run:

```bash
bin/rails generate migration AddBusinessStrategyFieldsToEcSkus business_grade:string business_stage:string business_grade_confirmed_at:datetime business_stage_confirmed_at:datetime business_state_confirmed_by_id:bigint
bin/rails generate migration CreateEcOperationEvents event_type:string sku_code:string platform:string store:references listing_id:string product_id:string platform_sku_id:string actor:references happened_at:datetime before_payload:jsonb after_payload:jsonb intent:text expected_effect:text observe_days:integer tags:jsonb source:string
bin/rails generate migration CreateEcMonitoringTasks operation_event:references sku_code:string status:string observe_starts_at:datetime observe_ends_at:datetime due_at:datetime metrics_before:jsonb metrics_after:jsonb result_payload:jsonb reviewed_at:datetime reviewed_by:references
bin/rails generate migration CreateEcAiAnalysisReports report_type:string sku_code:string operation_event:references monitoring_task:references status:string content:jsonb prompt_context:jsonb ai_model:string generated_at:datetime confirmed_at:datetime confirmed_by:references
```

Expected: four migration files are created under `db/migrate/`.

- [ ] **Step 2: Edit the generated migrations**

Set null/defaults/indexes:

```ruby
t.string :business_grade
t.string :business_stage
t.datetime :business_grade_confirmed_at
t.datetime :business_stage_confirmed_at
t.bigint :business_state_confirmed_by_id
t.index :business_grade
t.index :business_stage
```

```ruby
t.string :event_type, null: false
t.string :sku_code, null: false
t.string :platform
t.references :store, foreign_key: { to_table: :ec_stores }
t.string :listing_id
t.string :product_id
t.string :platform_sku_id
t.references :actor, foreign_key: { to_table: :users }
t.datetime :happened_at, null: false
t.jsonb :before_payload, null: false, default: {}
t.jsonb :after_payload, null: false, default: {}
t.text :intent
t.text :expected_effect
t.integer :observe_days, null: false, default: 7
t.jsonb :tags, null: false, default: []
t.string :source, null: false, default: "manual"
t.timestamps
t.index [:sku_code, :happened_at]
t.index [:event_type, :happened_at]
```

```ruby
t.references :operation_event, null: false, foreign_key: { to_table: :ec_operation_events }
t.string :sku_code, null: false
t.string :status, null: false, default: "open"
t.datetime :observe_starts_at, null: false
t.datetime :observe_ends_at, null: false
t.datetime :due_at, null: false
t.jsonb :metrics_before, null: false, default: {}
t.jsonb :metrics_after, null: false, default: {}
t.jsonb :result_payload, null: false, default: {}
t.datetime :reviewed_at
t.references :reviewed_by, foreign_key: { to_table: :users }
t.timestamps
t.index [:sku_code, :status, :due_at]
t.index [:status, :due_at]
```

```ruby
t.string :report_type, null: false
t.string :sku_code, null: false
t.references :operation_event, foreign_key: { to_table: :ec_operation_events }
t.references :monitoring_task, foreign_key: { to_table: :ec_monitoring_tasks }
t.string :status, null: false, default: "draft"
t.jsonb :content, null: false, default: {}
t.jsonb :prompt_context, null: false, default: {}
t.string :ai_model
t.datetime :generated_at, null: false
t.datetime :confirmed_at
t.references :confirmed_by, foreign_key: { to_table: :users }
t.timestamps
t.index [:sku_code, :report_type, :generated_at]
t.index [:status, :generated_at]
```

- [ ] **Step 3: Write model tests first**

Test examples:

```ruby
test "operation event requires semantic action fields" do
  event = Ec::OperationEvent.new(event_type: "price_change")

  assert_not event.valid?
  assert_includes event.errors[:sku_code], "can't be blank"
  assert_includes event.errors[:happened_at], "can't be blank"
end
```

```ruby
test "monitoring task computes due tasks by status and due_at" do
  task = Ec::MonitoringTask.create!(
    operation_event: @event,
    sku_code: @event.sku_code,
    status: "open",
    observe_starts_at: 7.days.ago,
    observe_ends_at: 1.day.ago,
    due_at: 1.day.ago
  )

  assert_includes Ec::MonitoringTask.due, task
end
```

```ruby
test "ai analysis report stores structured content" do
  report = Ec::AiAnalysisReport.create!(
    report_type: "monitoring_review",
    sku_code: @event.sku_code,
    operation_event: @event,
    content: { "summary" => "观察期达成预期" },
    generated_at: Time.current
  )

  assert_equal "观察期达成预期", report.content.fetch("summary")
end
```

- [ ] **Step 4: Run tests to verify failure**

Run:

```bash
bin/rails test test/models/ec/operation_event_test.rb test/models/ec/monitoring_task_test.rb test/models/ec/ai_analysis_report_test.rb
```

Expected: FAIL because models/tables do not exist yet.

- [ ] **Step 5: Implement models**

`app/models/ec/operation_event.rb`:

```ruby
module Ec
  class OperationEvent < ApplicationRecord
    self.table_name = "ec_operation_events"

    EVENT_TYPES = %w[
      price_change ad_budget_change ad_toggle ad_bid_change listing_optimization
      promotion_change warehouse_split replenishment purchase clearance
      grade_stage_change manual_note
    ].freeze

    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code
    belongs_to :store, class_name: "Ec::Store", optional: true
    belongs_to :actor, class_name: "User", optional: true
    has_many :monitoring_tasks, class_name: "Ec::MonitoringTask", dependent: :destroy
    has_many :ai_analysis_reports, class_name: "Ec::AiAnalysisReport", dependent: :nullify

    validates :event_type, inclusion: { in: EVENT_TYPES }
    validates :sku_code, :happened_at, presence: true
    validates :observe_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 60 }

    before_validation { self.sku_code = sku_code&.upcase }
  end
end
```

`app/models/ec/monitoring_task.rb`:

```ruby
module Ec
  class MonitoringTask < ApplicationRecord
    self.table_name = "ec_monitoring_tasks"

    STATUSES = %w[open reviewed cancelled].freeze

    belongs_to :operation_event, class_name: "Ec::OperationEvent"
    belongs_to :reviewed_by, class_name: "User", optional: true
    has_many :ai_analysis_reports, class_name: "Ec::AiAnalysisReport", dependent: :nullify

    validates :sku_code, :observe_starts_at, :observe_ends_at, :due_at, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :due, -> { where(status: "open").where("due_at <= ?", Time.current) }

    before_validation { self.sku_code = sku_code&.upcase }
  end
end
```

`app/models/ec/ai_analysis_report.rb`:

```ruby
module Ec
  class AiAnalysisReport < ApplicationRecord
    self.table_name = "ec_ai_analysis_reports"

    REPORT_TYPES = %w[strategy_diagnosis monitoring_review anomaly_alert copilot_answer].freeze
    STATUSES = %w[draft confirmed rejected].freeze

    belongs_to :operation_event, class_name: "Ec::OperationEvent", optional: true
    belongs_to :monitoring_task, class_name: "Ec::MonitoringTask", optional: true
    belongs_to :confirmed_by, class_name: "User", optional: true

    validates :report_type, inclusion: { in: REPORT_TYPES }
    validates :status, inclusion: { in: STATUSES }
    validates :sku_code, :generated_at, presence: true

    before_validation { self.sku_code = sku_code&.upcase }
  end
end
```

- [ ] **Step 6: Update `Ec::Sku` associations and validations**

Add:

```ruby
BUSINESS_GRADES = %w[S A B C].freeze
BUSINESS_STAGES = %w[NEW GRW MAT CLR].freeze

has_many :operation_events, class_name: "Ec::OperationEvent", foreign_key: :sku_code, primary_key: :sku_code
has_many :monitoring_tasks, class_name: "Ec::MonitoringTask", foreign_key: :sku_code, primary_key: :sku_code
has_many :ai_analysis_reports, class_name: "Ec::AiAnalysisReport", foreign_key: :sku_code, primary_key: :sku_code

validates :business_grade, inclusion: { in: BUSINESS_GRADES }, allow_blank: true
validates :business_stage, inclusion: { in: BUSINESS_STAGES }, allow_blank: true
```

- [ ] **Step 7: Run migration and tests**

Run:

```bash
bin/rails db:migrate
bin/rails test test/models/ec/operation_event_test.rb test/models/ec/monitoring_task_test.rb test/models/ec/ai_analysis_report_test.rb
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add db/migrate db/schema.rb app/models/ec/operation_event.rb app/models/ec/monitoring_task.rb app/models/ec/ai_analysis_report.rb app/models/ec/sku.rb test/models/ec/operation_event_test.rb test/models/ec/monitoring_task_test.rb test/models/ec/ai_analysis_report_test.rb
git commit -m "feat: add SKU business event records"
```

---

### Task 2: Centralize Order Item SKU Binding

**Files:**
- Create: `app/services/ec/order_item_sku_product_join.rb`
- Modify: `app/services/ec/inventory_velocity_metrics_query.rb`
- Modify: `app/services/ec/sku_inventory_overview.rb`
- Test: `test/services/ec/order_item_sku_product_join_test.rb`
- Test: existing affected service tests

- [ ] **Step 1: Write the join test**

```ruby
test "join SQL binds ozon by platform_sku_id and wb by product_id with store and platform" do
  sql = Ec::OrderItemSkuProductJoin.sql

  assert_includes sql, "ec_sku_products.store_id = ec_order_items.store_id"
  assert_includes sql, "ec_sku_products.platform = ec_order_items.platform"
  assert_includes sql, "ec_order_items.platform = 'ozon'"
  assert_includes sql, "ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id"
  assert_includes sql, "ec_order_items.platform = 'wb'"
  assert_includes sql, "ec_sku_products.product_id = ec_order_items.platform_sku_id"
  assert_not_includes sql, "offer_id"
end
```

- [ ] **Step 2: Run test to verify failure**

```bash
bin/rails test test/services/ec/order_item_sku_product_join_test.rb
```

Expected: FAIL because the service does not exist.

- [ ] **Step 3: Implement the shared service**

```ruby
module Ec
  class OrderItemSkuProductJoin
    def self.sql
      <<~SQL.squish
        INNER JOIN ec_sku_products
          ON ec_sku_products.store_id = ec_order_items.store_id
         AND ec_sku_products.platform = ec_order_items.platform
         AND (
           (ec_order_items.platform = 'ozon' AND ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id)
           OR
           (ec_order_items.platform = 'wb' AND ec_sku_products.product_id = ec_order_items.platform_sku_id)
         )
      SQL
    end
  end
end
```

- [ ] **Step 4: Replace duplicated private join SQL**

In `Ec::InventoryVelocityMetricsQuery` and `Ec::SkuInventoryOverview`, replace calls to the private `order_item_sku_product_join_sql` method with:

```ruby
.joins(Ec::OrderItemSkuProductJoin.sql)
```

Remove only the now-unused private join method in those files.

- [ ] **Step 5: Run focused tests**

```bash
bin/rails test test/services/ec/order_item_sku_product_join_test.rb test/controllers/reports_controller_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/ec/order_item_sku_product_join.rb app/services/ec/inventory_velocity_metrics_query.rb app/services/ec/sku_inventory_overview.rb test/services/ec/order_item_sku_product_join_test.rb
git commit -m "refactor: centralize SKU product order binding"
```

---

### Task 3: Build SKU Business Profile Query

**Files:**
- Create: `app/services/ec/sku_business_profile_query.rb`
- Test: `test/services/ec/sku_business_profile_query_test.rb`

- [ ] **Step 1: Write tests for output shape and attribution**

Test expectations:

```ruby
profile = Ec::SkuBusinessProfileQuery.new(
  sku_code: @sku.sku_code,
  date_to: Date.new(2026, 7, 6),
  time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
).call

assert_equal @sku.sku_code, profile.dig(:sku, :sku_code)
assert_equal @sku.business_grade, profile.dig(:strategy, :grade)
assert_equal @sku.business_stage, profile.dig(:strategy, :stage)
assert profile.key?(:windows)
assert profile.key?(:inventory)
assert profile.key?(:recent_events)
assert profile.key?(:open_monitoring_tasks)
assert profile.key?(:data_gaps)
```

Add a second test where an `Ec::OrderItem` has matching `sku_code` but no matching `Ec::SkuProduct`; assert the sale is not counted.

- [ ] **Step 2: Run test to verify failure**

```bash
bin/rails test test/services/ec/sku_business_profile_query_test.rb
```

Expected: FAIL because the service does not exist.

- [ ] **Step 3: Implement the minimal profile service**

The service should return:

```ruby
{
  sku: {
    sku_code: sku.sku_code,
    product_name: sku.product_name,
    product_name_ru: sku.product_name_ru,
    category_name: sku.sku_category&.name,
    owner_name: sku.owner_name,
    master_sku_code: sku.master_sku&.master_sku_code
  },
  strategy: {
    grade: sku.business_grade,
    stage: sku.business_stage
  },
  windows: {
    last_7_days: sales_window(7),
    last_28_days: sales_window(28),
    last_56_days: sales_window(56)
  },
  roi: roi_window(28),
  inventory: sku.inventory_overview.fetch(:summary),
  listing_bindings: listing_bindings,
  recent_events: recent_events,
  open_monitoring_tasks: open_monitoring_tasks,
  data_gaps: data_gaps
}
```

Use `Ec::OrderItemSkuProductJoin.sql` for all order quantity aggregation. Use `Ec::SkuPeriodRoiQuery` for ROI and profit where calculable. Do not call platform APIs or write data.

- [ ] **Step 4: Run focused tests**

```bash
bin/rails test test/services/ec/sku_business_profile_query_test.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/sku_business_profile_query.rb test/services/ec/sku_business_profile_query_test.rb
git commit -m "feat: build SKU business profile query"
```

---

### Task 4: Build Rule-First Strategy Diagnosis

**Files:**
- Create: `app/services/ec/sku_strategy_diagnosis.rb`
- Test: `test/services/ec/sku_strategy_diagnosis_test.rb`

- [ ] **Step 1: Write diagnosis tests**

Cover these cases:

```ruby
test "marks inventory shortage as red for S and A SKUs" do
  result = Ec::SkuStrategyDiagnosis.new(profile: profile_with(
    grade: "A",
    stage: "MAT",
    turnover_days: 5,
    annualized_net_profit_cny: BigDecimal("30000"),
    roi: BigDecimal("1.0")
  )).call

  assert_equal "red", result.fetch(:health_status)
  assert_equal "inventory", result.fetch(:main_constraint)
end
```

```ruby
test "does not recommend growth investment for C CLR SKU" do
  result = Ec::SkuStrategyDiagnosis.new(profile: profile_with(
    grade: "C",
    stage: "CLR",
    turnover_days: 180,
    annualized_net_profit_cny: BigDecimal("-1000"),
    roi: BigDecimal("-0.1")
  )).call

  assert_equal "CLR", result.fetch(:stage_suggestion)
  assert_not_includes result.fetch(:recommended_actions).join, "增加广告"
end
```

- [ ] **Step 2: Run tests to verify failure**

```bash
bin/rails test test/services/ec/sku_strategy_diagnosis_test.rb
```

Expected: FAIL because the service does not exist.

- [ ] **Step 3: Implement deterministic diagnosis output**

The `call` result must include:

```ruby
{
  summary: String,
  grade_suggestion: "S" | "A" | "B" | "C",
  stage_suggestion: "NEW" | "GRW" | "MAT" | "CLR",
  health_status: "green" | "yellow" | "red",
  main_constraint: "inventory" | "product_competitiveness" | "advertising_efficiency" | "price_competitiveness" | "platform_difference" | "clearance_execution" | "data_gap",
  evidence: Array,
  recommended_actions: Array,
  observe_days: Integer,
  risk: String
}
```

Use named constants for MVP thresholds:

```ruby
S_MIN_ANNUALIZED_PROFIT_CNY = BigDecimal("50000")
A_MIN_ANNUALIZED_PROFIT_CNY = BigDecimal("20000")
MIN_HEALTHY_TURNOVER_DAYS = BigDecimal("14")
MAX_CLEARANCE_TURNOVER_DAYS = BigDecimal("90")
DEFAULT_OBSERVE_DAYS = 7
```

Add a short comment that these constants are MVP defaults pending the threshold spec from Task 0.

- [ ] **Step 4: Run focused tests**

```bash
bin/rails test test/services/ec/sku_strategy_diagnosis_test.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/sku_strategy_diagnosis.rb test/services/ec/sku_strategy_diagnosis_test.rb
git commit -m "feat: add SKU strategy diagnosis rules"
```

---

### Task 5: Create Monitoring Tasks From Events

**Files:**
- Create: `app/services/ec/monitoring_task_factory.rb`
- Modify: `app/models/ec/operation_event.rb`
- Test: `test/services/ec/monitoring_task_factory_test.rb`

- [ ] **Step 1: Write factory tests**

```ruby
test "creates one open monitoring task using event observe days" do
  event = Ec::OperationEvent.create!(
    event_type: "price_change",
    sku_code: @sku.sku_code,
    happened_at: Time.zone.parse("2026-07-01 10:00"),
    intent: "验证涨价后利润",
    expected_effect: "利润提升",
    observe_days: 7
  )

  task = Ec::MonitoringTaskFactory.call(event)

  assert_equal event, task.operation_event
  assert_equal @sku.sku_code, task.sku_code
  assert_equal "open", task.status
  assert_equal event.happened_at, task.observe_starts_at
  assert_equal event.happened_at + 7.days, task.observe_ends_at
end
```

- [ ] **Step 2: Run test to verify failure**

```bash
bin/rails test test/services/ec/monitoring_task_factory_test.rb
```

Expected: FAIL because the factory does not exist.

- [ ] **Step 3: Implement factory**

```ruby
module Ec
  class MonitoringTaskFactory
    def self.call(operation_event)
      new(operation_event).call
    end

    def initialize(operation_event)
      @operation_event = operation_event
    end

    def call
      Ec::MonitoringTask.find_or_create_by!(operation_event: @operation_event) do |task|
        task.sku_code = @operation_event.sku_code
        task.status = "open"
        task.observe_starts_at = @operation_event.happened_at
        task.observe_ends_at = @operation_event.happened_at + @operation_event.observe_days.days
        task.due_at = task.observe_ends_at
      end
    end
  end
end
```

- [ ] **Step 4: Add model hook for manual MVP events**

In `Ec::OperationEvent`:

```ruby
after_commit :create_monitoring_task, on: :create

private

def create_monitoring_task
  Ec::MonitoringTaskFactory.call(self)
end
```

- [ ] **Step 5: Run focused tests**

```bash
bin/rails test test/services/ec/monitoring_task_factory_test.rb test/models/ec/operation_event_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/ec/monitoring_task_factory.rb app/models/ec/operation_event.rb test/services/ec/monitoring_task_factory_test.rb test/models/ec/operation_event_test.rb
git commit -m "feat: create monitoring tasks from operation events"
```

---

### Task 6: Add Manual Operation Event Entry

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/erp/operation_events_controller.rb`
- Create: `app/views/erp/operation_events/new.html.erb`
- Create: `app/views/erp/operation_events/_form.html.erb`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`
- Test: `test/controllers/erp/operation_events_controller_test.rb`

- [ ] **Step 1: Write controller tests**

Cover:

```ruby
test "manager can create manual operation event" do
  sign_in @manager

  assert_difference -> { Ec::OperationEvent.count }, 1 do
    post "/erp/operation_events", params: {
      ec_operation_event: {
        sku_code: @sku.sku_code,
        event_type: "price_change",
        happened_at: "2026-07-06 10:00",
        intent: "验证涨价",
        expected_effect: "利润提升",
        observe_days: 7
      }
    }, headers: { "Accept" => "text/html" }
  end

  assert_redirected_to report_sku_path(@sku.sku_code, tab: "strategy")
end
```

- [ ] **Step 2: Add routes**

Inside `namespace :erp`:

```ruby
resources :operation_events, only: [:new, :create]
```

- [ ] **Step 3: Implement controller**

Use `require_any_permission!(:manage_skus, :manage_finance)` or the closest existing permission pattern for ERP write actions. Assign `actor: current_user`, `source: "manual"`, and redirect back to SKU strategy tab.

- [ ] **Step 4: Implement the form**

Use only I18n text. Required fields:

- SKU code
- event type
- happened at
- intent
- expected effect
- observe days
- tags

- [ ] **Step 5: Run focused tests**

```bash
bin/rails test test/controllers/erp/operation_events_controller_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/erp/operation_events_controller.rb app/views/erp/operation_events config/locales/zh.yml config/locales/en.yml config/locales/ru.yml test/controllers/erp/operation_events_controller_test.rb
git commit -m "feat: add manual operation event entry"
```

---

### Task 7: Add Strategy Tab To SKU Detail

**Files:**
- Modify: `app/controllers/reports_controller.rb`
- Modify: `app/views/reports/sku_detail.html.erb`
- Create: `app/views/reports/_sku_strategy_tab.html.erb`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`
- Test: `test/controllers/reports_controller_test.rb`

- [ ] **Step 1: Write page tests**

```ruby
test "sku detail renders strategy tab with diagnosis and events" do
  Ec::OperationEvent.create!(
    event_type: "price_change",
    sku_code: @sku.sku_code,
    happened_at: Time.current,
    intent: "验证涨价",
    expected_effect: "利润提升",
    observe_days: 7
  )

  get "/reports/skus/#{@sku.sku_code}", params: { tab: "strategy" }, headers: { "Accept" => "text/html" }

  assert_response :success
  assert_select "a[aria-current='page']", I18n.t("reports.sku_detail.tabs.strategy")
  assert_select "[data-testid='sku-strategy-health']"
  assert_select "[data-testid='sku-operation-events']"
end
```

- [ ] **Step 2: Update tab list**

In `ReportsController::SKU_DETAIL_TABS`, add:

```ruby
strategy
```

- [ ] **Step 3: Load strategy data only for the tab**

Inside `load_sku_detail`:

```ruby
load_sku_strategy if @active_tab == "strategy"
```

Add:

```ruby
def load_sku_strategy
  @strategy_profile = Ec::SkuBusinessProfileQuery.new(
    sku_code: @sku.sku_code,
    date_to: user_today,
    time_zone: user_time_zone
  ).call
  @strategy_diagnosis = Ec::SkuStrategyDiagnosis.new(profile: @strategy_profile).call
  @operation_events = @sku.operation_events.order(happened_at: :desc).limit(20)
  @monitoring_tasks = @sku.monitoring_tasks.order(due_at: :desc).limit(20)
end
```

- [ ] **Step 4: Render strategy tab**

The partial displays:

- current Grade/Stage
- suggested Grade/Stage
- health status
- main constraint
- evidence
- recommended actions
- recent operation event timeline
- open monitoring tasks
- link to add manual operation event

All labels must use I18n.

- [ ] **Step 5: Run focused tests**

```bash
bin/rails test test/controllers/reports_controller_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/reports_controller.rb app/views/reports/sku_detail.html.erb app/views/reports/_sku_strategy_tab.html.erb config/locales/zh.yml config/locales/en.yml config/locales/ru.yml test/controllers/reports_controller_test.rb
git commit -m "feat: show SKU strategy diagnosis tab"
```

---

### Task 8: Generate Monitoring Review Reports

**Files:**
- Create: `app/jobs/ec/monitoring_task_review_job.rb`
- Create: `app/services/ec/monitoring_task_review_builder.rb`
- Modify: `config/recurring.yml`
- Test: `test/jobs/ec/monitoring_task_review_job_test.rb`
- Test: `test/services/ec/monitoring_task_review_builder_test.rb`

- [ ] **Step 1: Write builder tests**

```ruby
test "builds structured review report for a due task" do
  report_payload = Ec::MonitoringTaskReviewBuilder.new(@task).call

  assert_equal @task.sku_code, report_payload.fetch(:sku_code)
  assert_equal @task.operation_event.event_type, report_payload.fetch(:event_type)
  assert report_payload.key?(:before)
  assert report_payload.key?(:after)
  assert report_payload.key?(:conclusion)
  assert report_payload.key?(:recommended_next_step)
end
```

- [ ] **Step 2: Implement deterministic review builder**

Use `Ec::SkuBusinessProfileQuery` for current context and compare:

- event happened period length before event
- same length after event
- sales quantity
- net sales quantity
- ROI/profit when calculable
- inventory status

Return structured JSON. Do not require AI in this first pass.

- [ ] **Step 3: Implement job**

The job:

```ruby
Ec::MonitoringTask.due.find_each do |task|
  payload = Ec::MonitoringTaskReviewBuilder.new(task).call
  report = Ec::AiAnalysisReport.create!(
    report_type: "monitoring_review",
    sku_code: task.sku_code,
    operation_event: task.operation_event,
    monitoring_task: task,
    status: "draft",
    content: payload,
    generated_at: Time.current
  )
  task.update!(status: "reviewed", reviewed_at: Time.current, result_payload: payload)
end
```

- [ ] **Step 4: Add recurring job**

In `config/recurring.yml`, schedule the job daily. Follow existing environment-specific style in the file.

- [ ] **Step 5: Run focused tests**

```bash
bin/rails test test/services/ec/monitoring_task_review_builder_test.rb test/jobs/ec/monitoring_task_review_job_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/ec/monitoring_task_review_job.rb app/services/ec/monitoring_task_review_builder.rb config/recurring.yml test/jobs/ec/monitoring_task_review_job_test.rb test/services/ec/monitoring_task_review_builder_test.rb
git commit -m "feat: generate monitoring review reports"
```

---

### Task 9: Upgrade SKU List Into Strategy Dashboard

**Files:**
- Modify: `app/controllers/reports_controller.rb`
- Modify: `app/views/reports/skus.html.erb`
- Create: `app/services/ec/sku_strategy_dashboard_query.rb`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`
- Test: `test/services/ec/sku_strategy_dashboard_query_test.rb`
- Test: `test/controllers/reports_controller_test.rb`

- [ ] **Step 1: Write dashboard query test**

```ruby
rows = Ec::SkuStrategyDashboardQuery.new(
  date_to: Date.new(2026, 7, 6),
  time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
).call

row = rows.find { |item| item.fetch(:sku_code) == @sku.sku_code }
assert_equal @sku.business_grade, row.fetch(:grade)
assert_equal @sku.business_stage, row.fetch(:stage)
assert row.key?(:health_status)
assert row.key?(:main_constraint)
assert row.key?(:open_monitoring_task_count)
```

- [ ] **Step 2: Implement dashboard query**

For each active SKU, use `Ec::SkuBusinessProfileQuery` and `Ec::SkuStrategyDiagnosis`. Keep the returned row compact:

```ruby
{
  sku_code:,
  product_name:,
  owner_name:,
  grade:,
  stage:,
  health_status:,
  main_constraint:,
  sales_28d:,
  profit_28d_cny:,
  ad_spend_rate_28d:,
  turnover_days:,
  open_monitoring_task_count:,
  suggested_grade:,
  suggested_stage:
}
```

- [ ] **Step 3: Render compact columns**

Add columns to `/reports/skus`:

- Grade
- Stage
- Health
- Main constraint
- 28-day sales/profit
- turnover days
- open monitoring task count
- suggested Grade/Stage

All labels use I18n. Keep existing SKU links and basic columns.

- [ ] **Step 4: Run focused tests**

```bash
bin/rails test test/services/ec/sku_strategy_dashboard_query_test.rb test/controllers/reports_controller_test.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/sku_strategy_dashboard_query.rb app/controllers/reports_controller.rb app/views/reports/skus.html.erb config/locales/zh.yml config/locales/en.yml config/locales/ru.yml test/services/ec/sku_strategy_dashboard_query_test.rb test/controllers/reports_controller_test.rb
git commit -m "feat: add SKU strategy dashboard"
```

---

### Task 10: Add Manual Grade/Stage Confirmation

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/erp/sku_strategy_states_controller.rb`
- Modify: `app/views/reports/_sku_strategy_tab.html.erb`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`
- Test: `test/controllers/erp/sku_strategy_states_controller_test.rb`

- [ ] **Step 1: Write confirmation test**

```ruby
test "manager confirms suggested grade and stage" do
  sign_in @manager

  patch "/erp/skus/#{@sku.id}/strategy_state", params: {
    ec_sku: {
      business_grade: "A",
      business_stage: "MAT"
    }
  }, headers: { "Accept" => "text/html" }

  assert_redirected_to report_sku_path(@sku.sku_code, tab: "strategy")
  @sku.reload
  assert_equal "A", @sku.business_grade
  assert_equal "MAT", @sku.business_stage
  assert_not_nil @sku.business_grade_confirmed_at
  assert_not_nil @sku.business_stage_confirmed_at
end
```

- [ ] **Step 2: Add route**

Inside `namespace :erp`:

```ruby
patch "skus/:id/strategy_state" => "sku_strategy_states#update", as: :sku_strategy_state
```

- [ ] **Step 3: Implement controller**

The controller:

- requires SKU management permission
- permits only `business_grade` and `business_stage`
- stamps confirmed timestamps and user
- creates an `Ec::OperationEvent` with `event_type: "grade_stage_change"`

- [ ] **Step 4: Add form in strategy tab**

Show the current system suggestion and a small confirmation form. Do not auto-apply suggestions.

- [ ] **Step 5: Run focused tests**

```bash
bin/rails test test/controllers/erp/sku_strategy_states_controller_test.rb test/controllers/reports_controller_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/erp/sku_strategy_states_controller.rb app/views/reports/_sku_strategy_tab.html.erb config/locales/zh.yml config/locales/en.yml config/locales/ru.yml test/controllers/erp/sku_strategy_states_controller_test.rb
git commit -m "feat: confirm SKU grade and stage"
```

---

## Phase 2 Backlog

### Task 11: Add Anomaly Alert Rules

Build `Ec::SkuAnomalyScanner` and `Ec::AnomalyAlertJob` after MVP profile and diagnosis stabilize. Initial rules:

- S/A fast stockout risk
- MAT profit decline
- ad spend rate spike
- ad clicks without conversion
- CLR clearance progress too slow
- SKU not listed in expected platform/store

Verification:

```bash
bin/rails test test/services/ec/sku_anomaly_scanner_test.rb test/jobs/ec/anomaly_alert_job_test.rb
```

### Task 12: Add SKU Copilot Context Endpoint

Build a SKU-detail Copilot only after structured context and historical reports exist. The endpoint should retrieve `Ec::SkuBusinessProfileQuery`, recent `Ec::OperationEvent`, recent `Ec::AiAnalysisReport`, and confirmed Grade/Stage. It must not answer from raw tables directly.

Verification:

```bash
bin/rails test test/controllers/erp_ai/conversations_controller_test.rb test/services/ai/agent_runner_test.rb
```

---

## Final Verification

Run after MVP tasks:

```bash
bin/rails test test/models/ec/operation_event_test.rb \
  test/models/ec/monitoring_task_test.rb \
  test/models/ec/ai_analysis_report_test.rb \
  test/services/ec/order_item_sku_product_join_test.rb \
  test/services/ec/sku_business_profile_query_test.rb \
  test/services/ec/sku_strategy_diagnosis_test.rb \
  test/services/ec/monitoring_task_factory_test.rb \
  test/services/ec/monitoring_task_review_builder_test.rb \
  test/services/ec/sku_strategy_dashboard_query_test.rb \
  test/controllers/erp/operation_events_controller_test.rb \
  test/controllers/erp/sku_strategy_states_controller_test.rb \
  test/controllers/reports_controller_test.rb
```

Expected: all listed tests pass.

Do not run frontend build commands unless explicitly requested.
