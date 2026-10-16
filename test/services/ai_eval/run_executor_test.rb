require "test_helper"

class AiEvalRunExecutorTest < ActiveSupport::TestCase
  setup do
    period = { from: "2026-10-05", to: "2026-10-11", as_of: "2026-10-10", time_zone: "Asia/Shanghai", week_starts_on: "monday" }
    document = { data: { schema_version: 3, sku_code: "EVAL-ONLY", period: period, base: { current_grade: "B", current_stage: "GRW" } } }.deep_stringify_keys
    unified = { schema_version: 3, sku_code: "EVAL-ONLY", period: period,
      categories: { base: { name: "Base", description: "SKU attributes", markdown: "Grade B", raw_json: document } } }.deep_stringify_keys
    documents = { "v3/base_context.json" => document, "unified_snapshot.json" => unified }
    manifest = {
      format_version: 1, snapshot_type: "sku_context", sku_code: "EVAL-ONLY", snapshot_date: "2026-10-10",
      time_zone: "Asia/Shanghai", source_environment: "test", files: documents.to_h { |path, content|
        [path, { sha256: Digest::SHA256.hexdigest(JSON.generate(content)), content_sha256: AiEval::SnapshotManifest.content_checksum(content) }]
      }
    }
    @snapshot = AiEval::SnapshotRecord.create!(name: "Evaluation boundary", sku_code: "EVAL-ONLY", snapshot_date: "2026-10-10", manifest: manifest, documents: documents)
    @case = AiEval::CaseRecord.create!(snapshot: @snapshot, case_key: "root-eval-#{SecureRandom.hex(3)}", definition: {
      "patches" => [], "oracle" => { "diagnosis" => { "assertions" => [{ "id" => "severity", "path" => "$.events[0].severity", "operator" => "eq", "expected" => "critical", "severity" => "critical" }] } }
    })
    @case.approve!(user: nil)
    @rule = Ec::SkuDiagnosisRule.create!(name: "Eval boundary", prompt: "Stock", frequency: "manual", enabled: true)
    @runs = []
  end

  teardown do
    @runs.reverse_each(&:destroy!)
    @case&.destroy!
    @snapshot&.destroy!
    @rule&.destroy!
  end

  test "executes a captured result and scores it without creating business records" do
    run = create_run
    adapter = Object.new
    adapter.define_singleton_method(:call) { |**| { status: "completed", output: { events: [{ severity: "critical" }] } } }
    before = [Ec::AIDiagnosisEvent.count, Ec::SkuOperationPlan.count, Conversation.count, Message.count]
    AiEval::RunExecutor.call(run: run, adapters: { "diagnosis" => adapter })
    assert_equal "passed", run.reload.status
    assert_equal 100, run.scores.dig("diagnosis", "score")
    assert_equal before, [Ec::AIDiagnosisEvent.count, Ec::SkuOperationPlan.count, Conversation.count, Message.count]
    assert_equal 64, run.trace.dig("materialization", "fingerprint").length
  end

  test "does not run a later adapter when diagnosis is blocked" do
    @case.next_version!(definition: @case.definition.merge("oracle" => @case.oracle.merge("planner" => @case.oracle["diagnosis"]))).tap do |draft|
      @case.destroy!
      @case = draft
      @case.approve!(user: nil)
    end
    run = create_run(adapters: %w[diagnosis planner])
    blocked = Object.new
    blocked.define_singleton_method(:call) { |**| { status: "blocked", output: {} } }
    planner = Object.new
    planner.define_singleton_method(:call) { |**| raise "must not execute" }
    AiEval::RunExecutor.call(run: run, adapters: { "diagnosis" => blocked, "planner" => planner })
    assert_equal "blocked", run.reload.status
    assert_not run.trace.key?("planner")
  end

  test "approved cases and snapshots retain the input version" do
    assert_raises(ActiveRecord::RecordInvalid) { @case.update!(definition: {}) }
    assert_raises(ActiveRecord::RecordInvalid) { @snapshot.update!(documents: {}) }
    @case.reload
    assert_equal "approved", @case.status
    assert_raises(ActiveRecord::RecordInvalid) { @case.update!(status: "draft") }
    @case.reload
    assert_predicate @case.next_version!, :persisted?
    @case.snapshot.cases.where.not(id: @case.id).destroy_all
  end

  test "empty and unsupported oracles cannot be approved" do
    draft = @case.next_version!(definition: { "oracle" => { "diagnosis" => { "assertions" => [] } } })
    assert_raises(ArgumentError) { draft.approve!(user: nil) }
  ensure
    draft&.destroy!
  end

  test "real adapters pass captured event IDs into planner without business writes" do
    add_oracle("planner", [{ "id" => "operation", "path" => "$.plans[0].operation", "operator" => "eq", "expected" => "increase" }])
    @rule.update!(context_keys: ["base"])
    agent = { model_id: "eval-model", system_prompt: "Use the evidence", temperature: 0.1 }
    requests = []
    client = Object.new
    rule_id = @rule.id
    client.define_singleton_method(:complete) do |request|
      requests << request
      case requests.length
      when 1
        { tool_calls: [{ id: "d", name: "save_sku_event", arguments: { sku_code: "EVAL-ONLY", sub_agent_id: rule_id,
          severity: "critical", event_type: "stockout", message: "Stock low", simple_context: "Inventory evidence" } }] }
      when 2, 4 then { content: "Completed" }
      when 3
        event_id = JSON.parse(request.fetch(:context)).first.fetch("id")
        { tool_calls: [{ id: "p", name: "save_sku_plan", arguments: { sku_code: "EVAL-ONLY", target: "replenishment",
          operation: "increase", referer: [event_id], scope: "SKU", scope_id: "EVAL-ONLY", priority: 1,
          message: "Replenish", reason: "Low stock", baseline: "Current stock", constraints: "Capacity", expected_effect: "Restore stock" } }] }
      end
    end
    run = create_run(adapters: %w[diagnosis planner])
    assert_no_difference ["Ec::AIDiagnosisEvent.count", "Ec::SkuOperationPlan.count", "Conversation.count", "Message.count"] do
      AiEval::RunExecutor.call(run: run, adapters: {
        "diagnosis" => AiEval::DiagnosisAdapter.new(agent: agent, client: client),
        "planner" => AiEval::PlannerAdapter.new(agent: agent, client: client)
      })
    end
    assert_equal "passed", run.reload.status, run.trace.inspect
    event = run.outputs.dig("diagnosis", "events", 0)
    assert_equal event["id"], event["event_id"]
    assert_equal [event["id"]], run.outputs.dig("planner", "plans", 0, "referer")
    assert_equal 4, requests.length
  end

  test "weekly anchors and historical dates are validated before enqueueing" do
    run = AiEval::RunRecord.new(case_record: @case, settings: { "mode" => "online_synthetic", "adapters" => ["diagnosis"], "anchor_date" => "2026-10-15" })
    assert_not run.valid?
    run.settings["anchor_date"] = "2026-10-17"
    assert_predicate run, :valid?
    run.settings["mode"] = "historical_replay"
    assert_not run.valid?
    run.settings["anchor_date"] = "2026-10-10"
    assert_predicate run, :valid?
  end

  test "date assertions opt into anchor shifting and run settings remain immutable" do
    add_oracle("planner", [{ "id" => "deadline", "path" => "$.plans[0].execution_deadline", "operator" => "eq",
      "expected" => "2026-10-12", "shift_dates" => true }])
    run = create_run(adapters: ["planner"], anchor_date: "2026-10-17")
    oracle = @case.oracle_for(as_of: "2026-10-17")
    assert_equal "2026-10-19", oracle.dig("planner", "assertions", 0, "expected")
    assert_equal "2026-10-12", @case.oracle.dig("planner", "assertions", 0, "expected")
    assert_raises(ActiveRecord::RecordInvalid) { run.update!(settings: run.settings.merge("anchor_date" => "2026-10-24")) }
    run.reload
    assert_equal "2026-10-17", run.settings["anchor_date"]
  end

  private

  def add_oracle(name, assertions)
    draft = @case.next_version!(definition: @case.definition.merge("oracle" => @case.oracle.merge(name => { "assertions" => assertions })))
    @case.destroy!
    @case = draft
    @case.approve!(user: nil)
  end

  def create_run(adapters: ["diagnosis"], **settings)
    @runs << AiEval::RunRecord.create!(case_record: @case, settings: {
      "mode" => "online_synthetic", "adapters" => adapters, "rule_ids" => [@rule.id]
    }.merge(settings.stringify_keys))
    @runs.last
  end
end
