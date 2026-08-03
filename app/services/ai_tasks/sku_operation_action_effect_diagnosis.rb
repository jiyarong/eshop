module AITasks
  class SkuOperationActionEffectDiagnosis
    AGENT_CODE = "sku_operation_action_tracker".freeze
    DIAGNOSIS_KIND = "operation_action_effect".freeze
    TIME_ZONE = "Asia/Shanghai".freeze
    TARGET_OFFSETS = [ 7, 14, 30 ].freeze
    RECENT_ACTION_DAYS = 30
    OBSERVATION_DAYS = 7
    EFFECTIVENESS_VALUES = %w[positive negative mixed inconclusive].freeze
    CONFIDENCE_VALUES = %w[high medium low].freeze
    ACTION_METRIC_FOCUS = {
      "sku_adv_on_off" => %w[views add_to_cart funnel_orders sales_quantity revenue conversion],
      "sku_inbound_change" => %w[views add_to_cart funnel_orders sales_quantity stock conversion],
      "listing_content" => %w[views add_to_cart funnel_orders sales_quantity conversion],
      "listing_specification" => %w[views add_to_cart funnel_orders sales_quantity conversion],
      "listing_pricing" => %w[views add_to_cart funnel_orders sales_quantity revenue conversion],
      "manual_note" => %w[views add_to_cart funnel_orders sales_quantity revenue conversion]
    }.freeze

    def self.run(as_of_date: nil, client: ErpAI::DefaultClient.new, user: nil)
      new(as_of_date: as_of_date, client: client, user: user).run
    end

    def initialize(as_of_date:, client:, user:)
      @time_zone = Time.find_zone!(TIME_ZONE)
      @as_of_date = (as_of_date || Time.current.in_time_zone(@time_zone).to_date).to_date
      @client = client
      @user = user
    end

    def run
      candidate_skus.filter_map do |sku|
        next if diagnosed_today?(sku)

        diagnose_sku(sku)
      rescue StandardError => error
        Rails.logger.error(
          "[AITasks::SkuOperationActionEffectDiagnosis] SKU #{sku.sku_code}: #{error.class}: #{error.message}"
        )
        nil
      end
    end

    private

    attr_reader :as_of_date, :client, :time_zone

    def candidate_skus
      Ec::Sku.where(id: target_action_scope.select(:ec_sku_id)).order(:sku_code)
    end

    def target_action_scope
      predicates = target_dates.map { "operated_at BETWEEN ? AND ?" }.join(" OR ")
      bounds = target_dates.flat_map do |date|
        [ time_for_date(date).beginning_of_day, time_for_date(date).end_of_day ]
      end
      Ec::OperationAction.where(predicates, *bounds)
    end

    def target_dates
      @target_dates ||= TARGET_OFFSETS.map { |offset| as_of_date - offset.days }
    end

    def diagnose_sku(sku)
      actions = recent_actions_for(sku)
      target_actions = actions.select { |action| target_dates.include?(action_date(action)) }
      return if target_actions.empty?

      metrics = metrics_for(sku)
      evaluations = target_actions.map { |action| evaluate_action(action, metrics) }
      recent_actions = actions.map { |action| serialize_action(action) }
      ai_result = analyze(sku, evaluations, recent_actions)
      persist_diagnosis(sku, ai_result, evaluations, recent_actions)
    end

    def recent_actions_for(sku)
      sku.operation_actions
        .includes(:sku_product, :store, :operated_by_user)
        .where(operated_at: recent_action_range)
        .order(:operated_at, :id)
        .to_a
    end

    def recent_action_range
      time_for_date(as_of_date - RECENT_ACTION_DAYS.days).beginning_of_day..
        time_for_date(analysis_cutoff_date).end_of_day
    end

    def metrics_for(sku)
      Ec::SkuOperationActionMetricsQuery.new(
        sku: sku,
        from_date: as_of_date - (RECENT_ACTION_DAYS + OBSERVATION_DAYS).days,
        to_date: analysis_cutoff_date,
        time_zone: time_zone
      ).call
    end

    def evaluate_action(action, metrics)
      date = action_date(action)
      platform = action.sku_product.platform
      before = window_metrics(
        metrics,
        from_date: date - OBSERVATION_DAYS.days,
        to_date: date - 1.day,
        platform: platform
      )
      after = window_metrics(
        metrics,
        from_date: date + 1.day,
        to_date: [ date + OBSERVATION_DAYS.days, analysis_cutoff_date ].min,
        platform: platform
      )

      {
        action: serialize_action(action),
        expected_metrics: ACTION_METRIC_FOCUS.fetch(action.operation_type),
        before: before,
        after: after,
        changes: metric_changes(before.fetch(:metrics), after.fetch(:metrics))
      }
    end

    def window_metrics(metrics, from_date:, to_date:, platform:)
      return empty_window(from_date, to_date) if to_date < from_date

      dates = (from_date..to_date).to_a
      sales = metrics.fetch(:sales_by_day_and_platform)
      funnel = metrics.fetch(:funnel_by_day_and_platform)
      platform_sales = dates.sum { |date| sales.fetch([ date, platform ], 0) }
      all_sales = dates.sum do |date|
        sales.sum { |date_and_platform, quantity| date_and_platform.first == date ? quantity : 0 }
      end
      funnel_totals = Hash.new(0.to_d)
      funnel_days = 0

      dates.each do |date|
        day_metrics = funnel.fetch([ date, platform ], {})
        funnel_days += 1 if day_metrics.fetch(:source_rows, 0).positive?
        day_metrics.each do |metric, value|
          next if metric == :source_rows

          funnel_totals[metric] += value.to_d
        end
      end

      days_count = dates.size
      metric_values = {
        sales_quantity_sku_daily: decimal(all_sales, days_count),
        sales_quantity_platform_daily: decimal(platform_sales, days_count)
      }
      funnel_totals.each do |metric, total|
        metric_values["#{metric}_daily".to_sym] = decimal(total, days_count)
      end
      metric_values[:view_to_cart_pct] = percent(funnel_totals[:add_to_cart], funnel_totals[:views])
      metric_values[:cart_to_order_pct] = percent(funnel_totals[:funnel_orders], funnel_totals[:add_to_cart])
      metric_values[:view_to_order_pct] = percent(funnel_totals[:funnel_orders], funnel_totals[:views])

      {
        from_date: from_date.iso8601,
        to_date: to_date.iso8601,
        days_count: days_count,
        funnel_coverage_days: funnel_days,
        metrics: metric_values
      }
    end

    def empty_window(from_date, to_date)
      {
        from_date: from_date.iso8601,
        to_date: to_date.iso8601,
        days_count: 0,
        funnel_coverage_days: 0,
        metrics: {}
      }
    end

    def metric_changes(before, after)
      (before.keys | after.keys).each_with_object({}) do |metric, result|
        before_value = before[metric]
        after_value = after[metric]
        next if before_value.nil? || after_value.nil?

        result[metric] = {
          before: before_value,
          after: after_value,
          delta: round_number(after_value - before_value),
          delta_pct: before_value.to_d.zero? ? nil : round_number((after_value - before_value) / before_value.to_d * 100)
        }
      end
    end

    def analyze(sku, evaluations, recent_actions)
      agent = Agent.ensure_fixed!(AGENT_CODE)
      response = client.complete(
        model: agent.model_id,
        temperature: agent.temperature.to_f,
        thinking_enabled: agent.thinking_enabled?,
        system_prompt: agent.system_prompt,
        context: "",
        messages: [
          {
            role: "user",
            content: {
              task: "诊断目标 action 的效果，并把其他近期 action 作为混杂因素",
              as_of_date: as_of_date.iso8601,
              analysis_cutoff_date: analysis_cutoff_date.iso8601,
              sku: sku.sku_code,
              target_offsets_days: TARGET_OFFSETS,
              target_action_evaluations: evaluations,
              recent_actions: recent_actions
            }.to_json
          }
        ],
        tools: []
      )
      normalize_ai_result(response.fetch(:content))
    end

    def normalize_ai_result(content)
      payload = content.is_a?(Hash) ? content.deep_stringify_keys : parse_json_content(content)
      effectiveness = payload["effectiveness"].to_s
      confidence = payload["confidence"].to_s
      raise ArgumentError, "invalid AI effectiveness" unless effectiveness.in?(EFFECTIVENESS_VALUES)
      raise ArgumentError, "invalid AI confidence" unless confidence.in?(CONFIDENCE_VALUES)
      raise ArgumentError, "AI summary is required" if payload["summary"].blank?
      raise ArgumentError, "AI events must be an array" unless payload["events"].is_a?(Array)

      payload
    end

    def parse_json_content(content)
      text = content.to_s
      json = text[/```(?:json)?\s*(.*?)(?:```|\z)/m, 1] || text
      JSON.parse(json.strip)
    end

    def persist_diagnosis(sku, ai_result, evaluations, recent_actions)
      diagnosis = nil
      sku.with_lock do
        return if diagnosed_today?(sku)

        diagnosis = sku.operation_action_diagnoses.create!(
          submitted_by: diagnosis_user,
          analyzed_at: time_for_date(as_of_date).noon,
          data: {
            diagnosis_kind: DIAGNOSIS_KIND,
            observation_date: as_of_date.iso8601,
            analysis_cutoff_date: analysis_cutoff_date.iso8601,
            target_offsets_days: TARGET_OFFSETS,
            summary: ai_result.fetch("summary"),
            effectiveness: ai_result.fetch("effectiveness"),
            confidence: ai_result.fetch("confidence"),
            action_evaluations: evaluations,
            recent_actions: recent_actions
          }
        )
        diagnosis.events.create!(diagnosis_events(ai_result, evaluations))
      end
      diagnosis
    end

    def diagnosis_events(ai_result, evaluations)
      ai_events = ai_result.fetch("events").filter_map do |event|
        next unless event.is_a?(Hash)

        normalized = event.deep_stringify_keys
        action_id = Integer(normalized["action_id"], exception: false)
        [ action_id, normalized ] if action_id
      end.to_h

      evaluations.each_with_index.map do |evaluation, position|
        action = evaluation.fetch(:action)
        ai_event = ai_events.fetch(action.fetch(:id), {})
        effect = ai_event["effect"].to_s
        effect = "inconclusive" unless effect.in?(EFFECTIVENESS_VALUES)
        {
          event_type: "operation_action_effect",
          severity: normalized_severity(ai_event["severity"], effect),
          scope: action.fetch(:operation_type),
          message: ai_event["message"].presence || "该 action 暂无足够数据形成可靠结论。",
          details: evaluation.merge(
            ai_effect: effect,
            recommendations: Array(ai_event["recommendations"]).map(&:to_s)
          ),
          position: position
        }
      end
    end

    def normalized_severity(value, effect)
      return value if value.to_s.in?(%w[info warning critical])

      effect == "negative" ? "warning" : "info"
    end

    def diagnosed_today?(sku)
      sku.operation_action_diagnoses
        .where(analyzed_at: time_for_date(as_of_date).all_day)
        .where("data ->> 'diagnosis_kind' = ?", DIAGNOSIS_KIND)
        .exists?
    end

    def serialize_action(action)
      {
        id: action.id,
        operation_type: action.operation_type,
        operated_at: action.operated_at.in_time_zone(time_zone).iso8601,
        days_ago: (as_of_date - action_date(action)).to_i,
        platform: action.sku_product.platform,
        store: action.store.store_name,
        record_by_system: action.record_by_system,
        operator: action.operated_by_user.display_name,
        diff_result: action.diff_result
      }
    end

    def diagnosis_user
      @diagnosis_user ||= @user || User.where(active: true)
        .joins(:roles)
        .where(roles: { code: "super_admin" })
        .order(:id)
        .first || User.where(active: true).order(:id).first || raise("No active user available for AI diagnosis")
    end

    def action_date(action)
      action.operated_at.in_time_zone(time_zone).to_date
    end

    def analysis_cutoff_date
      @analysis_cutoff_date ||= as_of_date.beginning_of_week(:monday) - 1.day
    end

    def decimal(value, divisor)
      round_number(value.to_d / divisor)
    end

    def percent(numerator, denominator)
      return nil unless denominator.to_d.positive?

      round_number(numerator.to_d / denominator.to_d * 100)
    end

    def round_number(value)
      value.to_d.round(4).to_f
    end

    def time_for_date(date)
      time_zone.local(date.year, date.month, date.day)
    end
  end
end
