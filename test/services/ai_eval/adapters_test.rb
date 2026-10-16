# frozen_string_literal: true

require "test_helper"

class AiEvalAdaptersTest < ActiveSupport::TestCase
  class Client
    attr_reader :requests
    def initialize(&response)
      @requests, @response = [], response
    end
    def complete(request)
      @requests << request
      @response.call(request, @requests.length)
    end
  end

  class RawJsonAgent
    def self.with(_params)
      new
    end

    def analyze
      self
    end

    def generate_now
      { message: { content: { effectiveness: "positive", confidence: "medium", summary: "Coverage improved" }.to_json } }
    end
  end

  def metadata
    { sku_code: "EVAL-SKU", as_of: "2026-10-15", time_zone: "Asia/Shanghai" }
  end

  def agent
    { model_id: "test-model", system_prompt: "Production prompt", temperature: 0.1 }
  end

  def rule
    { id: 7, prompt: "Evaluate stock only", context_keys: ["inventory"], allowed_event_types: ["stockout"] }
  end

  def documents
    { "unified_snapshot.json" => { "sku_code" => "EVAL-SKU",
      "period" => { "as_of" => "2026-10-15", "from" => "2026-10-05", "to" => "2026-10-11" },
      "categories" => { "inventory" => { "name" => "Inventory", "description" => "Stock summary", "markdown" => "book_stock=20" } } } }
  end

  def event_arguments
    { sku_code: "EVAL-SKU", sub_agent_id: 7, severity: "critical", event_type: "stockout",
      message: "Stock is low", simple_context: "book_stock=20" }
  end

  def fixed_event
    event_arguments.merge(id: 1, is_latest: true, created_at: "2026-10-15T03:00:00+08:00")
  end

  def plan_arguments
    { sku_code: "EVAL-SKU", target: "replenishment", operation: "increase", referer: [1], scope: "SKU", scope_id: "EVAL-SKU",
      priority: 1, message: "Order stock", reason: "Inventory low", baseline: "20 units", constraints: "Confirm capacity", expected_effect: "Restore coverage" }
  end

  def plan
    { id: 1, sku_code: "EVAL-SKU", planning_period_start: "2026-10-05", execution_deadline: "2026-10-12", lifecycle_status: "active" }
  end

  test "diagnosis uses production prompt and captures events with no business writes" do
    client = Client.new do |_request, index|
      index == 1 ? { tool_calls: [{ id: "event", name: "save_sku_event", arguments: event_arguments }] } : { content: "Saved" }
    end
    result = nil
    assert_no_difference ["Conversation.count", "Message.count", "Ec::AIDiagnosisEvent.count", "Ec::SkuOperationPlan.count"] do
      result = AiEval::DiagnosisAdapter.new(agent:, client:).call(documents:, metadata:, rule:)
    end
    assert_equal "completed", result[:status]
    assert_equal "critical", result.dig(:output, :events, 0, "severity")
    assert_equal ["save_sku_event"], client.requests.first[:tools].map { |tool| tool[:name] }
    assert_includes client.requests.first[:messages].first[:content], "Evaluate stock only"
    assert_includes client.requests.first[:context], "book_stock=20"
    assert_not client.requests.first.key?(:allow_raw_json)
    assert result[:rule_fingerprint].present?
  end

  test "out of scope tools and wrong SKU are blocked at the executor boundary" do
    [ ["erp_ai_request", { url: "/ai/sku" }], ["save_sku_event", event_arguments.merge(sku_code: "OTHER")] ].each do |name, arguments|
      client = Client.new { { tool_calls: [{ id: "bad", name:, arguments: }] } }
      result = AiEval::DiagnosisAdapter.new(agent:, client:).call(documents:, metadata:, rule:)
      assert_equal "blocked", result[:status]
      assert_equal 1, client.requests.length
      assert result.dig(:errors, 0, :message).present?
    end
  end

  test "diagnosis without saving is failed and unsupported listing replay is blocked" do
    client = Client.new { { content: "No event" } }
    assert_equal "failed", AiEval::DiagnosisAdapter.new(agent:, client:).call(documents:, metadata:, rule:)[:status]
    assert_equal "blocked", AiEval::DiagnosisAdapter.new(agent:, client:).call(documents:, metadata:, rule: rule.merge(context_keys: ["ozon_listing_content"]))[:status]
  end

  test "planner captures plans and rejects foreign references" do
    client = Client.new do |_request, index|
      index == 1 ? { tool_calls: [{ id: "plan", name: "save_sku_plan", arguments: plan_arguments }] } : { content: "Planned" }
    end
    result = AiEval::PlannerAdapter.new(agent:, client:).call(documents:, metadata:, events: [fixed_event])
    assert_equal "completed", result[:status]
    assert_equal [1], result.dig(:output, :plans, 0, "referer")
    assert_equal "2026-10-19", result.dig(:output, :plans, 0, "execution_deadline")
    invalid = Client.new { { tool_calls: [{ id: "bad", name: "save_sku_plan", arguments: plan_arguments.merge(referer: [999]) }] } }
    result = AiEval::PlannerAdapter.new(agent:, client: invalid).call(documents:, metadata:, events: [fixed_event])
    assert_equal "blocked", result[:status]
  end

  test "captured diagnosis IDs can flow directly into planner without persisted events" do
    diagnosis_client = Client.new do |_request, index|
      index == 1 ? { tool_calls: [{ id: "event", name: "save_sku_event", arguments: event_arguments }] } : { content: "Saved" }
    end
    diagnosis = AiEval::DiagnosisAdapter.new(agent:, client: diagnosis_client).call(documents:, metadata:, rule:)
    events = diagnosis.dig(:output, :events)
    planner_client = Client.new do |_request, index|
      index == 1 ? { tool_calls: [{ id: "plan", name: "save_sku_plan", arguments: plan_arguments.merge(referer: [events.first.fetch("id")]) }] } : { content: "Planned" }
    end
    result = AiEval::PlannerAdapter.new(agent:, client: planner_client).call(documents:, metadata:, events:)
    assert_equal "completed", result[:status]
    assert_equal [events.first.fetch("id")], result.dig(:output, :plans, 0, "referer")
  end

  test "planner cannot create a plan against an uncaptured Listing" do
    client = Client.new do
      { tool_calls: [{ id: "plan", name: "save_sku_plan", arguments: plan_arguments.merge(target: "price", scope: "LISTING", scope_id: "999") }] }
    end
    result = AiEval::PlannerAdapter.new(agent:, client:).call(documents:, metadata:, events: [fixed_event], listings: [{ id: "10" }])
    assert_equal "blocked", result[:status]
    assert_match(/Listing/, result.dig(:errors, 0, :message))
  end

  test "planner abstains for info events and blocks stale or cross SKU events" do
    client = Client.new { raise "must not call model" }
    result = AiEval::PlannerAdapter.new(agent:, client:).call(documents:, metadata:, events: [fixed_event.merge(severity: "info")])
    assert_equal "completed", result[:status]
    assert_empty result.dig(:output, :plans)
    assert_equal "blocked", AiEval::PlannerAdapter.new(agent:, client:).call(documents:, metadata:, events: [fixed_event.merge(sku_code: "OTHER")])[:status]
    assert_equal "blocked", AiEval::PlannerAdapter.new(agent:, client:).call(documents:, metadata:, events: [fixed_event.merge(created_at: "2026-10-11T00:00:00+08:00")])[:status]
  end

  test "plan evaluation without actions is inconclusive without a model call" do
    client = Client.new { raise "must not call model" }
    result = AiEval::PlanEvaluationAdapter.new(agent:, client:).call(documents:, metadata:, plan:, actions: [], metrics: {})
    assert_equal "completed", result[:status]
    assert_equal "not_started", result.dig(:output, :execution_status)
    assert_equal "inconclusive", result.dig(:output, :effectiveness)
    assert_equal "2026-10-12", result.dig(:output, :observation_to)
    assert_equal "insufficient_data", result.dig(:output, :evaluation_status)
  end

  test "plan evaluation uses fixed evidence and validates the model result" do
    actions = [{ id: 1, sku_code: "EVAL-SKU", plan_id: 1, operated_at: "2026-10-06T12:00:00+08:00" }]
    client = Client.new { { content: { effectiveness: "positive", confidence: "medium", summary: "Coverage improved" } } }
    result = AiEval::PlanEvaluationAdapter.new(agent:, client:).call(documents:, metadata:, plan:, actions:, metrics: { before: { sales: 1 }, after: { sales: 2 } })
    assert_equal "completed", result[:status]
    assert_equal "positive", result.dig(:output, :effectiveness)
    assert_empty client.requests.first[:tools]
    assert_equal true, client.requests.first[:allow_raw_json]
    invalid = Client.new { { content: '{"effectiveness":"excellent"}' } }
    assert_equal "blocked", AiEval::PlanEvaluationAdapter.new(agent:, client: invalid).call(documents:, metadata:, plan:, actions:, metrics: { observed: true })[:status]
  end

  test "plan evaluation accepts raw JSON through the production ActiveAgent client" do
    actions = [{ id: 1, sku_code: "EVAL-SKU", plan_id: 1, operated_at: "2026-10-06T12:00:00+08:00" }]
    client = ErpAI::ActiveAgentClient.new(agent_class: RawJsonAgent)
    result = AiEval::PlanEvaluationAdapter.new(agent:, client:).call(documents:, metadata:, plan:, actions:, metrics: { before: { sales: 1 }, after: { sales: 2 } })

    assert_equal "completed", result[:status]
    assert_equal "positive", result.dig(:output, :effectiveness)
    assert_equal 1, result[:trace].length
  end

  test "plan evaluation blocks future evidence at the known metrics boundaries before calling a model" do
    cases = [
      { observation_to: "2026-10-13" },
      { observation_period: { from: "2026-10-05", to: "2026-10-13" } },
      { observation_period: { provisional_profit_from: "2026-10-19" } },
      { inventory_snapshots_by_day: { "2026-10-13" => { snapshot_date: "2026-10-13" } } },
      { inventory_snapshots_by_day: { "2026-10-12" => { snapshot_date: "2026-10-13" } } },
      { inventory_snapshots_by_week: { "2026-10-12" => { snapshot_date: "2026-10-12" } } },
      { weekly_profit_by_week_and_store: { [Date.new(2026, 10, 12), 1] => { after_tax_profit: 1 } } },
      { funnel_by_day_and_platform: { [Date.new(2026, 10, 13), "ozon"] => { orders: 1 } } }
    ]
    client = Client.new { raise "must not call model" }
    cases.each do |metrics|
      result = AiEval::PlanEvaluationAdapter.new(agent:, client:).call(documents:, metadata:, plan:, actions: [], metrics:)
      assert_equal "blocked", result[:status], metrics.inspect
      assert_match(/future evidence/, result.dig(:errors, 0, :message))
    end
    assert_empty client.requests
  end

  test "plan evaluation blocks future diagnosis periods and timestamps in Shanghai time" do
    cases = [
      { current_week: { from: "2026-10-12", to: "2026-10-13", events: [] } },
      { previous_week: { from: "2026-10-13", to: "2026-10-13", events: [] } },
      { current_week: { events: [{ created_at: "2026-10-12T16:00:00Z" }] } }
    ]
    client = Client.new { raise "must not call model" }
    cases.each do |diagnosis_context|
      result = AiEval::PlanEvaluationAdapter.new(agent:, client:).call(documents:, metadata:, plan:, actions: [], metrics: {}, diagnosis_context:)
      assert_equal "blocked", result[:status]
      assert_match(/future evidence/, result.dig(:errors, 0, :message))
    end
    assert_empty client.requests
  end

  test "plan evaluation accepts past metrics and leaves dates in narrative text intact" do
    metrics = {
      observation_period: { from: "2026-10-05", to: "2026-10-12", provisional_profit_from: "2026-10-12" },
      weekly_profit_by_week_and_store: { [Date.new(2026, 10, 5), 1] => { after_tax_profit: 1 } },
      inventory_snapshots_by_week: { "2026-10-05" => { snapshot_date: "2026-10-11" } },
      inventory_snapshots_by_day: { "2026-10-12" => { snapshot_date: "2026-10-12" } },
      funnel_by_day_and_platform: { [Date.new(2026, 10, 12), "ozon"] => { orders: 1 } }
    }
    diagnosis_context = { current_week: { from: "2026-10-12", to: "2026-10-12", events: [
      { created_at: "2026-10-12T15:59:59Z", message: "Order expected to arrive 2026-12-01" }
    ] } }
    client = Client.new { raise "must not call model for an unexecuted plan" }
    result = AiEval::PlanEvaluationAdapter.new(agent:, client:).call(documents:, metadata:, plan:, actions: [], metrics:, diagnosis_context:)

    assert_equal "completed", result[:status]
    assert_equal "evaluated", result.dig(:output, :evaluation_status)
    assert_equal "inconclusive", result.dig(:output, :effectiveness)
    assert_empty client.requests
  end
end
