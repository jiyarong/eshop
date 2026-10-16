# frozen_string_literal: true

module AiEval
  class PlanEvaluationAdapter
    def initialize(agent:, client: ErpAI::DefaultClient.new)
      @agent, @client = agent, client
    end

    def call(documents:, metadata:, plan:, actions:, metrics:, diagnosis_context: {}, concurrent_actions: [])
      metadata = ModelSession.metadata(metadata)
      plan = plan.to_h.deep_stringify_keys
      raise ArgumentError, "plan does not belong to case SKU" unless plan["sku_code"] == metadata.fetch(:sku_code)
      as_of = Date.iso8601(metadata.fetch(:as_of))
      observation_from = Date.iso8601(plan.fetch("planning_period_start"))
      observation_to = [Date.iso8601(plan.fetch("execution_deadline")), as_of - 1].min
      raise ArgumentError, "there is no complete observation day" if observation_to < observation_from
      actions = scoped_actions(actions, metadata:, plan:, observation_from:, observation_to:, bound: true)
      concurrent_actions = scoped_actions(concurrent_actions, metadata:, plan:, observation_from:, observation_to:, bound: false)
      metrics = metrics.to_h.deep_stringify_keys
      diagnosis_context = diagnosis_context.to_h.deep_stringify_keys
      validate_evidence_dates!(metrics, diagnosis_context, observation_to)
      execution_status = if plan["lifecycle_status"] == "cancelled" || plan["status"] == "ignored"
        "not_applicable"
      elsif actions.empty?
        "not_started"
      elsif plan["execution_status"] == "partial"
        "partial"
      else
        "executed"
      end
      available = evidence_available?(metrics, diagnosis_context)
      evidence = { execution_status:, observation_from: observation_from.iso8601, observation_to: observation_to.iso8601,
        metrics:, diagnosis_context:, action_ids: actions.map { |action| action["id"] },
        evaluation_status: metrics_available?(metrics) ? "evaluated" : "insufficient_data" }
      if %w[not_started not_applicable].include?(execution_status) || !available
        key = %w[not_started not_applicable].include?(execution_status) ? execution_status : "insufficient_data"
        output = evidence.merge(effectiveness: "inconclusive", confidence: "low",
          summary: I18n.t("erp.sku_operation_plan_evaluation.summary.#{key}"))
        return { status: "completed", output:, trace: [], metadata:,
          gates: [{ name: "evaluation_input", passed: true }],
          fingerprint: ModelSession.fingerprint(plan:, actions:, evidence:), prompt_boundary: "production_fixed_evaluation_context" }
      end
      request_context = evidence.except(:action_ids, :evaluation_status).merge(plan:, actions:, concurrent_actions:).to_json
      system_prompt = [ModelSession.read(@agent, :system_prompt).presence || I18n.t("erp.sku_operation_plan_evaluation.system_prompt"),
        Ec::SkuOperationPlanEvaluationRunner::DIAGNOSIS_CONTEXT_PROMPT].join("\n\n")
      executor = EvaluationToolExecutor.new(sku_code: metadata.fetch(:sku_code), as_of: metadata.fetch(:as_of), allowed_tools: [])
      result = ModelSession.new(agent: @agent, client: @client).call(question: request_context, context: "", executor:, system_prompt:, allow_raw_json: true)
      if result[:status] == "completed"
        content = result.dig(:output, :content)
        payload = content.is_a?(Hash) ? content.deep_stringify_keys : JSON.parse(content.to_s.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, ""))
        raise ArgumentError, "evaluation result must be an object" unless payload.is_a?(Hash)
        raise ArgumentError, "invalid effectiveness" unless Ec::SkuOperationPlanEvaluationRunner::EFFECTIVENESS_VALUES.include?(payload["effectiveness"])
        raise ArgumentError, "invalid confidence" unless Ec::SkuOperationPlanEvaluationRunner::CONFIDENCE_VALUES.include?(payload["confidence"])
        raise ArgumentError, "summary must be non-empty" unless payload["summary"].is_a?(String) && payload["summary"].present?
        result[:output] = evidence.merge(payload.slice("effectiveness", "confidence", "summary").symbolize_keys)
      end
      result.merge(metadata:, prompt_boundary: "production_fixed_evaluation_context")
    rescue KeyError, ArgumentError, JSON::ParserError => error
      { status: "blocked", output: {}, metadata:, trace: result&.fetch(:trace, []) || [], gates: [{ name: "evaluation_input_or_result", passed: false }],
        errors: [{ code: "invalid_evaluation_input_or_result", message: error.message }] }
    end

    private

    def scoped_actions(actions, metadata:, plan:, observation_from:, observation_to:, bound:)
      Array(actions).map { |action| action.to_h.deep_stringify_keys }.select do |action|
        raise ArgumentError, "action does not belong to case SKU" unless action["sku_code"] == metadata.fetch(:sku_code)
        raise ArgumentError, "action does not reference case plan" if bound && action["plan_id"].to_s != plan.fetch("id").to_s
        date = Time.iso8601(action.fetch("operated_at")).in_time_zone("Asia/Shanghai").to_date
        date.between?(observation_from, observation_to)
      end
    end

    def evidence_available?(metrics, diagnosis_context)
      metrics_available?(metrics) || diagnosis_context.dig("current_week", "events").present? || diagnosis_context.dig("previous_week", "events").present?
    end

    def metrics_available?(metrics)
      profit = metrics["observation_profit_by_store"] || metrics["weekly_profit_by_week_and_store"]
      metrics.present? && (profit.nil? || profit.values.any? { |row| row.is_a?(Hash) && row["after_tax_profit"].is_a?(Numeric) })
    end

    # These paths come from SkuOperationActionMetricsQuery and the production
    # evaluation request/diagnosis context. Business text and unknown fields are
    # left intact; a date mentioned in an action recommendation is not evidence.
    def validate_evidence_dates!(metrics, diagnosis_context, cutoff)
      %w[observation_from observation_to from_date to_date].each do |field|
        assert_not_future!(metrics[field], cutoff, "metrics.#{field}")
      end
      %w[from to provisional_profit_from].each do |field|
        assert_not_future!(metrics.dig("observation_period", field), cutoff, "metrics.observation_period.#{field}")
      end
      {
        "weekly_profit_by_week_and_store" => [true, 6],
        "inventory_snapshots_by_week" => [false, 6],
        "inventory_snapshots_by_day" => [false, 0],
        "funnel_by_day_and_platform" => [true, 0]
      }.each do |field, (composite, period_days)|
        metrics.fetch(field, {}).to_h.each do |key, row|
          date = series_date(key, composite:)
          assert_not_future!((date + period_days).iso8601, cutoff, "metrics.#{field}[#{key}]") if date
          assert_not_future!(row["snapshot_date"], cutoff, "metrics.#{field}[#{key}].snapshot_date") if row.is_a?(Hash)
        end
      end
      %w[current_week previous_week].each do |week|
        period = diagnosis_context.fetch(week, {})
        %w[from to].each { |field| assert_not_future!(period[field], cutoff, "diagnosis_context.#{week}.#{field}") }
        Array(period["events"]).each do |event|
          assert_not_future!(event["created_at"], cutoff, "diagnosis_context.#{week}.events.created_at")
        end
      end
    end

    def assert_not_future!(value, cutoff, path)
      return if value.nil?
      text = value.to_s
      date = Time.find_zone!("Asia/Shanghai").iso8601(text).to_date
      raise ArgumentError, "future evidence at #{path}: #{value} exceeds observation_to #{cutoff}" if date > cutoff
    rescue Date::Error
      raise ArgumentError, "invalid evidence date at #{path}"
    end

    def series_date(key, composite:)
      text = key.to_s
      return Date.iso8601(text) if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      return unless composite
      # Rails JSON stringifies [Date, store/platform] keys using Date#inspect.
      # JSON-array and ISO tuple forms also occur in hand-edited fixture files.
      match = text.match(/\A\[([A-Za-z]{3}, \d{2} [A-Za-z]{3} \d{4}), /)
      return Date.strptime(match[1], "%a, %d %b %Y") if match
      match = text.match(/\A\["?(\d{4}-\d{2}-\d{2})"?,/)
      Date.iso8601(match[1]) if match
    end
  end
end
