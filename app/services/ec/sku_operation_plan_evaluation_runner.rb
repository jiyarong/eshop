module Ec
  class SkuOperationPlanEvaluationRunner
    TIME_ZONE = "Asia/Shanghai".freeze
    EVALUATOR_VERSION = "deterministic_v1".freeze
    EFFECTIVENESS_VALUES = %w[positive negative mixed inconclusive].freeze
    CONFIDENCE_VALUES = %w[high medium low].freeze

    def self.run(as_of_date: nil, period_start: nil, sku_code: nil, metrics_provider: nil, evaluator: nil, client: nil, user: nil)
      new(
        as_of_date: as_of_date,
        period_start: period_start,
        sku_code: sku_code,
        metrics_provider: metrics_provider,
        evaluator: evaluator,
        client: client,
        user: user
      ).run
    end

    def initialize(
      as_of_date: nil,
      period_start: nil,
      sku_code: nil,
      metrics_provider: nil,
      metrics_query_class: Ec::SkuOperationActionMetricsQuery,
      evaluator: nil,
      client: nil,
      evaluator_version: EVALUATOR_VERSION,
      user: nil
    )
      @time_zone = Time.find_zone!(TIME_ZONE)
      @as_of_date = (as_of_date || Time.current.in_time_zone(@time_zone).to_date).to_date
      @period_start = period_start&.to_date&.beginning_of_week(:monday)
      @sku_code = sku_code
      @metrics_provider = metrics_provider
      @metrics_query_class = metrics_query_class
      @evaluator = evaluator
      @client = client
      @evaluator_version = evaluator_version
      @user = user
    end

    def run
      plans.filter_map do |plan|
        evaluate_plan(plan)
      rescue StandardError => error
        Rails.logger.error(
          "[Ec::SkuOperationPlanEvaluationRunner] plan #{plan.id}: #{error.class}: #{error.message}"
        )
        mark_failed(plan)
        nil
      end
    end

    private

    attr_reader :as_of_date, :period_start, :sku_code, :metrics_provider, :metrics_query_class, :evaluator, :client,
      :evaluator_version, :time_zone, :user

    def plans
      scope = SkuOperationPlan.where(planning_period_start: previous_period_start)
      scope = scope.where(sku_id: Sku.where(sku_code: sku_code)) if sku_code.present?
      scope.includes(:operation_actions, :evaluations).order(:sku_id, :id)
    end

    def evaluate_plan(plan)
      actions = observed_actions(plan)
      metrics = metrics_for(plan)
      execution_status = execution_status_for(plan, actions)
      result = result_for(plan, actions, metrics, execution_status)
      evaluation = persist_evaluation(plan, actions, metrics, execution_status, result)
      evaluation
    end

    def observed_actions(plan)
      from = time_for_date(plan.planning_period_start).beginning_of_day
      to = time_for_date(plan.execution_deadline).end_of_day
      plan.operation_actions.where(operated_at: from..to).order(:operated_at, :id).to_a
    end

    def execution_status_for(plan, actions)
      return "not_applicable" if plan.lifecycle_status == "cancelled" || plan.status == "ignored"
      return "not_started" if actions.empty?
      return "partial" if plan.execution_status == "partial"

      "executed"
    end

    def metrics_for(plan)
      if metrics_provider
        arguments = {
          plan: plan,
          from_date: plan.planning_period_start - 4.weeks,
          to_date: observation_to
        }
        return metrics_provider.arity == 1 ? (metrics_provider.call(arguments) || {}) : (metrics_provider.call(**arguments) || {})
      end

      metrics_query_class.new(
        sku: plan.sku,
        from_date: plan.planning_period_start - 4.weeks,
        to_date: observation_to,
        time_zone: time_zone
      ).call
    rescue StandardError => error
      Rails.logger.warn(
        "[Ec::SkuOperationPlanEvaluationRunner] metrics unavailable for plan #{plan.id}: " \
        "#{error.class}: #{error.message}"
      )
      {}
    end

    def result_for(plan, actions, metrics, execution_status)
      context = {
        plan: plan,
        actions: actions,
        metrics: metrics,
        execution_status: execution_status,
        observation_from: plan.planning_period_start,
        observation_to: observation_to
      }
      if execution_status.in?(%w[not_started not_applicable])
        return {
          effectiveness: "inconclusive",
          confidence: "low",
          summary: execution_status == "not_started" ?
            I18n.t("erp.sku_operation_plan_evaluation.summary.not_started") :
            I18n.t("erp.sku_operation_plan_evaluation.summary.not_applicable")
        }
      end

      if evaluator
        evaluated = evaluator.arity == 1 ? evaluator.call(context) : evaluator.call(**context)
        return normalize_result(evaluated)
      end

      return normalize_result(evaluate_with_client(context)) if client

      diagnosed_result = existing_action_diagnosis_result(plan, actions)
      return diagnosed_result if diagnosed_result

      deterministic_result = deterministic_result(metrics)
      return deterministic_result if deterministic_result

      {
        effectiveness: "inconclusive",
        confidence: "low",
        summary: I18n.t("erp.sku_operation_plan_evaluation.summary.insufficient_data")
      }
    end

    def deterministic_result(metrics)
      values = metrics.to_h.deep_stringify_keys
      before = values["before"].to_h
      after = values["after"].to_h
      metric = %w[after_tax_profit pre_tax_profit net_sales_quantity sales_quantity profit].find do |key|
        before[key].is_a?(Numeric) && after[key].is_a?(Numeric)
      end
      return unless metric

      before_value = before.fetch(metric).to_d
      after_value = after.fetch(metric).to_d
      return if before_value == after_value

      effectiveness = after_value > before_value ? "positive" : "negative"
      {
        effectiveness: effectiveness,
        confidence: "low",
        summary: I18n.t("erp.sku_operation_plan_evaluation.summary.deterministic_#{effectiveness}")
      }
    end

    def evaluate_with_client(context)
      response = client.complete({
        model: "sku_plan_evaluation",
        temperature: 0.1,
        thinking_enabled: false,
        system_prompt: I18n.t(
          "erp.sku_operation_plan_evaluation.system_prompt",
          default: "请基于计划、动作证据和原始指标保守判断计划效果，只返回 JSON：effectiveness、confidence、summary。未执行动作不得判为负面。"
        ),
        context: "",
        messages: [ { role: "user", content: context.deep_stringify_keys.to_json } ],
        tools: []
      })
      payload = response[:content] || response["content"]
      payload = parse_json_content(payload) unless payload.is_a?(Hash)
      payload
    end

    def parse_json_content(content)
      text = content.to_s
      json = text[/```(?:json)?\s*(.*?)(?:```|\z)/m, 1] || text
      JSON.parse(json.strip)
    end

    def existing_action_diagnosis_result(plan, actions)
      action_ids = actions.map(&:id).to_set
      return if action_ids.empty?

      diagnoses = OperationActionDiagnosis.where(sku_id: plan.sku_id)
        .includes(:events).order(analyzed_at: :desc, id: :desc).to_a
      rows = diagnoses.flat_map do |diagnosis|
        evaluations = Array(diagnosis.data["action_evaluations"] || diagnosis.data[:action_evaluations])
        evaluations.filter_map do |evaluation|
          action_id = evaluation.dig("action", "id") || evaluation.dig(:action, :id)
          next unless action_ids.include?(action_id.to_i)

          event = diagnosis.events.find do |item|
            detail = item.details || {}
            detail_action_id = detail.dig("action", "id") || detail.dig(:action, :id)
            detail_action_id.to_i == action_id.to_i
          end
          { evaluation: evaluation, diagnosis: diagnosis, event: event }
        end
      end
      return if rows.empty?

      effects = rows.filter_map do |row|
        row.fetch(:event)&.details&.fetch("ai_effect", nil) ||
          row.fetch(:evaluation)["ai_effect"] || row.fetch(:evaluation)[:ai_effect] ||
          row.fetch(:evaluation)["effectiveness"] || row.fetch(:evaluation)[:effectiveness]
      end.map(&:to_s).select { |value| value.in?(EFFECTIVENESS_VALUES) }.uniq
      return if effects.empty?

      effectiveness = effects.one? ? effects.first : "mixed"
      confidence = rows.filter_map do |row|
        row.fetch(:diagnosis).data["confidence"] || row.fetch(:diagnosis).data[:confidence] ||
          row.fetch(:evaluation)["confidence"] || row.fetch(:evaluation)[:confidence]
      end.map(&:to_s).find { |value| value.in?(CONFIDENCE_VALUES) } || "low"
      {
        effectiveness: effectiveness,
        confidence: confidence,
        summary: I18n.t(
          "erp.sku_operation_plan_evaluation.summary.from_action_diagnosis",
          default: "已复用运营动作效果诊断结果。"
        )
      }
    end

    def normalize_result(result)
      result = result.to_h.stringify_keys
      effectiveness = result["effectiveness"].to_s
      confidence = result["confidence"].to_s
      raise ArgumentError, "invalid evaluation effectiveness" unless effectiveness.in?(EFFECTIVENESS_VALUES)
      raise ArgumentError, "invalid evaluation confidence" unless confidence.in?(CONFIDENCE_VALUES)
      raise ArgumentError, "evaluation summary is required" if result["summary"].blank?

      {
        effectiveness: effectiveness,
        confidence: confidence,
        summary: result["summary"].to_s,
        conversation_id: Integer(result["conversation_id"], exception: false)
      }
    end

    def persist_evaluation(plan, actions, metrics, execution_status, result)
      evaluation = plan.evaluations.find_or_initialize_by(observation_to: observation_to)
      evaluation.assign_attributes(
        observation_from: plan.planning_period_start,
        execution_status: execution_status,
        effectiveness: result.fetch(:effectiveness),
        confidence: result.fetch(:confidence),
        summary: result.fetch(:summary),
        metrics: metrics,
        evidence: {
          planning_period_start: plan.planning_period_start.iso8601,
          planning_period_end: plan.planning_period_end.iso8601,
          execution_deadline: plan.execution_deadline.iso8601,
          action_count: actions.size,
          data_available: metrics.present?
        },
        action_ids: actions.map(&:id),
        conversation_id: result[:conversation_id],
        evaluator_version: evaluator_version,
        status: "succeeded",
        evaluated_at: Time.current
      )
      evaluation.save!

      plan_attributes = {
        execution_status: execution_status,
        evaluation_status: metrics.present? || actions.empty? ? "evaluated" : "insufficient_data"
      }
      plan_attributes[:lifecycle_status] = "expired" if as_of_date > plan.execution_deadline && plan.lifecycle_status == "active"
      plan.update!(plan_attributes)
      evaluation
    end

    def mark_failed(plan)
      evaluation = plan.evaluations.find_or_initialize_by(observation_to: observation_to)
      evaluation.assign_attributes(
        observation_from: plan.planning_period_start,
        execution_status: plan.execution_status,
        effectiveness: "inconclusive",
        confidence: "low",
        summary: I18n.t("erp.sku_operation_plan_evaluation.summary.failed", default: "计划效果评估失败，等待重试。"),
        evaluator_version: evaluator_version,
        status: "failed",
        evaluated_at: nil
      )
      evaluation.save!
      plan.update_columns(evaluation_status: "failed")
      evaluation
    rescue StandardError => error
      Rails.logger.error("[Ec::SkuOperationPlanEvaluationRunner] failed to persist failure: #{error.message}")
      nil
    end

    def previous_period_start
      @previous_period_start ||= period_start || (as_of_date.beginning_of_week(:monday) - 1.week)
    end

    def observation_to
      previous_period_start + 6.days
    end

    def time_for_date(date)
      time_zone.local(date.year, date.month, date.day)
    end
  end
end
