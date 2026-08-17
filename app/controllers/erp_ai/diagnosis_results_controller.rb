module ErpAI
  class DiagnosisResultsController < ActionController::API
    include ErpAI::RequestAuthenticatable

    class InvalidPayload < StandardError; end

    EVENT_SEVERITIES = {
      "grade_downgrade_alert" => "red",
      "grade_recovery_observation" => "yellow",
      "grade_recovery_confirmed" => "info",
      "grade_upgrade_candidate" => "yellow",
      "grade_initial_assignment_candidate" => "yellow",
      "grade_stockout_protected" => "yellow",
      "grade_drift_warning" => "yellow",
      "grade_weekly_profit_drop" => "red",
      "grade_weekly_profit_rise" => "info",
      "grade_under_observation" => "info",
      "grade_stable" => "info",
      "grade_data_insufficient" => "yellow"
    }.freeze

    DEFAULT_HISTORY_LIMIT = 3
    MAX_HISTORY_LIMIT = 10

    def index
      invalid!("unsupported diagnosis type") unless params.require(:type) == "GradeInspect"
      sku = Ec::Sku.find_by!(sku_code: params.require(:sku).to_s.strip.upcase)
      diagnoses = sku.grade_inspects
        .includes(:events)
        .recent_first
        .limit(history_limit)

      render json: {
        data: {
          type: "GradeInspect",
          sku: sku.sku_code,
          diagnoses: diagnoses.map { |diagnosis| serialized_diagnosis(diagnosis) }
        }
      }
    rescue ActionController::ParameterMissing => error
      render json: { error: "#{error.param} is required" }, status: :bad_request
    rescue InvalidPayload => error
      render json: { error: error.message }, status: :bad_request
    rescue ActiveRecord::RecordNotFound
      render json: { error: "SKU not found" }, status: :not_found
    end

    def create
      payload = request.request_parameters.deep_stringify_keys
      validate_payload!(payload)
      sku = Ec::Sku.find_by!(sku_code: payload.fetch("sku").to_s.strip.upcase)
      data = payload.fetch("data")
      validate_grade_state!(sku, data)

      diagnosis, created = persist_result(sku, payload, data)
      render json: {
        data: {
          id: diagnosis.id,
          type: diagnosis[:type],
          sku: sku.sku_code,
          analyzed_at: diagnosis.analyzed_at,
          submitted_by: @current_user.display_name,
          submitted_at: diagnosis.created_at,
          event_count: diagnosis.events.size,
          created: created
        }
      }, status: created ? :created : :ok
    rescue InvalidPayload => error
      render json: { error: error.message }, status: :bad_request
    rescue ActiveRecord::RecordNotFound
      render json: { error: "SKU not found" }, status: :not_found
    end

    private

    def validate_payload!(payload)
      invalid!("payload must be an object") unless payload.is_a?(Hash)
      invalid!("unsupported diagnosis type") unless payload["type"] == "GradeInspect"
      invalid!("sku is required") if payload["sku"].blank?
      invalid!("data must be an object") unless payload["data"].is_a?(Hash)
      invalid!("events must be a non-empty array") unless payload["events"].is_a?(Array) && payload["events"].any?
      invalid!("source must be WSU-DEEP") unless payload.dig("data", "source") == "WSU-DEEP"
      invalid!("currency must be CNY") unless payload.dig("data", "currency") == "CNY"
      parsed_analyzed_at(payload["analyzed_at"])
      analysis_cutoff_date(payload.fetch("data"))
      normalized_events(payload.fetch("events"))
    end

    def validate_grade_state!(sku, data)
      current_grade = data["current_grade"].presence
      expected_grade = sku.current_marketing_state&.grade
      invalid!("current Grade does not match") unless current_grade == expected_grade

      candidate_grade = data["confirmed_candidate_grade"].presence
      if candidate_grade && !candidate_grade.in?(Ec::SkuMarketingState::GRADES)
        invalid!("invalid confirmed candidate Grade")
      end
      %w[grade_change_recommended downgrade_precondition_met downgrade_suppressed].each do |field|
        invalid!("#{field} must be boolean") unless data[field].in?([ true, false ])
      end
      recovery_status = data["recovery_status"].to_s
      invalid!("invalid recovery status") unless recovery_status.in?(%w[none observing confirmed failed])
      if data["grade_change_recommended"] && (candidate_grade.nil? || candidate_grade == current_grade)
        invalid!("recommended Grade change requires a different candidate")
      end
      if recovery_status.in?(%w[observing confirmed]) && (data["grade_change_recommended"] || !data["downgrade_suppressed"])
        invalid!("recovery must suppress a Grade change")
      end
    end

    def persist_result(sku, payload, data)
      created = false
      events = normalized_events(payload.fetch("events"))
      diagnosis = sku.with_lock do
        existing = sku.grade_inspects.find_by("data ->> 'analysis_cutoff_date' = ?", analysis_cutoff_date(data).iso8601)
        if existing
          existing.events.create!(events) if existing.events.empty?
          next existing
        end

        created = true
        result = sku.grade_inspects.create!(
          submitted_by: @current_user,
          analyzed_at: parsed_analyzed_at(payload["analyzed_at"]) || Time.current,
          data: data.merge(
            "diagnosis_kind" => "grade_inspect",
            "analysis_cutoff_date" => analysis_cutoff_date(data).iso8601
          )
        )
        result.events.create!(events)
        result
      end
      [ diagnosis, created ]
    end

    def serialized_diagnosis(diagnosis)
      {
        id: diagnosis.id,
        analyzed_at: diagnosis.analyzed_at,
        created_at: diagnosis.created_at,
        data: diagnosis.data,
        events: diagnosis.events.map do |event|
          {
            event_type: event.event_type,
            severity: event.severity,
            scope: event.scope,
            message: event.message,
            details: event.details
          }
        end
      }
    end

    def history_limit
      limit = Integer(params.fetch(:limit, DEFAULT_HISTORY_LIMIT))
      invalid!("limit must be between 1 and #{MAX_HISTORY_LIMIT}") unless limit.between?(1, MAX_HISTORY_LIMIT)

      limit
    rescue ArgumentError, TypeError
      invalid!("limit must be between 1 and #{MAX_HISTORY_LIMIT}")
    end

    def normalized_events(events)
      events.map.with_index do |event, position|
        invalid!("each event must be an object") unless event.is_a?(Hash)

        event_type = event["event_type"].to_s
        expected_severity = EVENT_SEVERITIES[event_type]
        invalid!("invalid Grade event type") unless expected_severity
        invalid!("invalid severity for #{event_type}") unless event["severity"] == expected_severity
        invalid!("event message is required") if event["message"].blank?
        invalid!("event details must be an object") unless event["details"].is_a?(Hash)
        {
          event_type: event_type,
          severity: expected_severity,
          scope: event["scope"].presence_in(%w[grade profit]) || default_scope_for(event_type),
          message: event["message"],
          details: event["details"],
          position: position
        }
      end
    end

    def analysis_cutoff_date(data)
      latest_observation = Array(data["weekly_observations"]).first
      observation_to_date = latest_observation["to_date"] if latest_observation.is_a?(Hash)
      value = data["analysis_cutoff_date"] || observation_to_date
      date = Date.iso8601(value.to_s)
      invalid!("analysis_cutoff_date must be a Sunday") unless date.sunday?
      date
    rescue Date::Error
      invalid!("latest weekly observation must end on an ISO 8601 Sunday")
    end

    def parsed_analyzed_at(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      invalid!("analyzed_at must be an ISO 8601 timestamp")
    end

    def default_scope_for(event_type)
      event_type.start_with?("grade_weekly_profit_") ? "profit" : "grade"
    end

    def invalid!(message)
      raise InvalidPayload, message
    end
  end
end
