# frozen_string_literal: true

module AiEval
  class PlannerAdapter
    def initialize(agent:, client: ErpAI::DefaultClient.new)
      @agent, @client = agent, client
    end

    def call(documents:, metadata:, events:, listings: nil, historical_context: {})
      metadata = ModelSession.metadata(metadata)
      listings = Array(listings || metadata[:listings]).map { |listing| listing.to_h.deep_stringify_keys }
      events = events.map { |event| event.to_h.deep_stringify_keys }
      raise ArgumentError, "events must belong to the case SKU" if events.any? { |event| event["sku_code"] != metadata.fetch(:sku_code) }
      raise ArgumentError, "event severity is invalid" if events.any? { |event| !%w[info warning critical].include?(event["severity"]) }
      as_of = Date.iso8601(metadata.fetch(:as_of))
      events = events.select { |event| %w[warning critical].include?(event["severity"]) && event["scope"] != "advise" }
      events.each do |event|
        raise ArgumentError, "event ID, current pointer and sub-rule are required" unless event["id"].is_a?(Integer) && event["id"].positive? && event["is_latest"] == true && event["sub_agent_id"].present?
        date = Time.iso8601(event.fetch("created_at")).in_time_zone("Asia/Shanghai").to_date
        raise ArgumentError, "event is outside current planning week" unless date.between?(as_of.beginning_of_week(:monday), as_of)
      end
      raise ArgumentError, "duplicate event IDs" unless events.map { |event| event["id"] }.uniq.length == events.length
      raise ArgumentError, "multiple latest events for one sub-rule" unless events.map { |event| event["sub_agent_id"] }.uniq.length == events.length
      if events.empty?
        return { status: "completed", output: { plans: [], content: nil }, trace: [], metadata:,
          gates: [{ name: "planner_input", passed: true }],
          fingerprint: ModelSession.fingerprint(events: [], metadata:), prompt_boundary: "production_question_and_fixed_history" }
      end
      summary = events.map do |event|
        event.slice("id", "severity", "event_type", "simple_context", "details", "message", "rule_name").tap do |item|
          item["simple_context"] = [event["message"], event["details"].presence&.to_json].compact.join("\n\n") if item["simple_context"].blank?
        end
      end.to_json
      question = ErpAI::SkuEvaluationPrompts.planner(sku_code: metadata.fetch(:sku_code), period_start: as_of.beginning_of_week(:monday),
        listings:, historical_context:)
      executor = EvaluationToolExecutor.new(sku_code: metadata.fetch(:sku_code), as_of: metadata.fetch(:as_of),
        allowed_tools: ["save_sku_plan"], listings:, events:)
      result = ModelSession.new(agent: @agent, client: @client).call(question:, context: summary, executor:)
      result[:output] = result.fetch(:output).merge(plans: executor.captures.map { |plan| plan.except("capture_key") })
      result.merge(metadata:, prompt_boundary: "production_question_and_fixed_history")
    rescue KeyError, ArgumentError => error
      { status: "blocked", output: {}, metadata:, trace: [], gates: [{ name: "planner_input", passed: false }],
        errors: [{ code: "invalid_planner_input", message: error.message }] }
    end
  end
end
