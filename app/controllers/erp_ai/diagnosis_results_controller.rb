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

    STRICT_GRADE_DATA_KEYS = %w[
      source currency weekly_observations analysis_cutoff_date recovery_status
      downgrade_precondition_met downgrade_suppressed
    ].freeze
    DEFAULT_HISTORY_LIMIT = 3
    MAX_HISTORY_LIMIT = 10

    def index
      invalid_payload!("unsupported diagnosis type") unless params.require(:type) == "GradeInspect"
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
      payload = normalized_payload
      if strict_grade_payload?(payload)
        result, created = persist_strict_grade_result(payload)
      else
        result = persist_standard_result(payload)
        return if performed?

        created = true
      end

      render json: {
        data: {
          id: result.id,
          type: result.type,
          sku: result.sku.sku_code,
          grade: result.sku.current_marketing_state&.grade,
          analyzed_at: result.analyzed_at,
          submitted_by: @current_user.display_name,
          submitted_at: result.created_at,
          event_count: result.events.size,
          created: created
        }
      }, status: created ? :created : :ok
    rescue InvalidPayload, ArgumentError => error
      render json: { error: error.message }, status: :bad_request
    rescue ActiveRecord::RecordNotFound
      render json: { error: "SKU not found" }, status: :not_found
    end

    private

    def normalized_payload
      payload = request.request_parameters
      invalid_payload!("payload must be an object") unless payload.respond_to?(:deep_stringify_keys)
      payload = payload.deep_stringify_keys
      invalid_payload!("payload must be an object") if payload.key?("_json")
      payload
    end

    def strict_grade_payload?(payload)
      data = payload["data"]
      data.is_a?(Hash) && (data.keys & STRICT_GRADE_DATA_KEYS).any?
    end

    def persist_standard_result(payload)
      attributes = diagnosis_attributes(payload)
      sku = Ec::Sku.find_by!(sku_code: attributes.delete(:sku_code))
      type = attributes.delete(:type)
      if type == "RestockingDiagnosis" && !Ec::SkuInventoryHealthSubmissionLock.acquire(sku.id)
        response.set_header("Retry-After", Ec::SkuInventoryHealthSubmissionLock::TTL.to_i.to_s)
        render json: { error: "SKU submission is locked; retry after 5 seconds" }, status: :too_many_requests
        return
      end

      Ec::AIDiagnosisSubmission.create!(
        type: type,
        sku: sku,
        submitted_by: @current_user,
        **attributes
      )
    end

    def diagnosis_attributes(payload)
      {
        type: required_string(payload["type"], "type"),
        sku_code: required_string(payload["sku"], "sku").strip.upcase,
        analyzed_at: parsed_analyzed_at(payload["analyzed_at"]) || Time.current,
        data: diagnosis_data(payload),
        events: normalized_events(payload["events"])
      }
    end

    def persist_strict_grade_result(payload)
      validate_strict_grade_payload!(payload)
      sku = Ec::Sku.find_by!(sku_code: payload.fetch("sku").to_s.strip.upcase)
      data = payload.fetch("data")
      validate_grade_state!(sku, data)
      created = false
      events = normalized_grade_events(payload.fetch("events"))

      diagnosis = sku.with_lock do
        existing = sku.grade_inspects.find_by(
          "data ->> 'analysis_cutoff_date' = ?",
          analysis_cutoff_date(data).iso8601
        )
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

    def validate_strict_grade_payload!(payload)
      invalid_payload!("unsupported diagnosis type") unless payload["type"] == "GradeInspect"
      invalid_payload!("sku is required") if payload["sku"].blank?
      invalid_payload!("data must be an object") unless payload["data"].is_a?(Hash)
      invalid_payload!("events must be a non-empty array") unless payload["events"].is_a?(Array) && payload["events"].any?
      invalid_payload!("source must be WSU-DEEP") unless payload.dig("data", "source") == "WSU-DEEP"
      invalid_payload!("currency must be CNY") unless payload.dig("data", "currency") == "CNY"
      parsed_analyzed_at(payload["analyzed_at"])
      analysis_cutoff_date(payload.fetch("data"))
      normalized_grade_events(payload.fetch("events"))
    end

    def validate_grade_state!(sku, data)
      current_grade = data["current_grade"].presence
      expected_grade = sku.current_marketing_state&.grade
      invalid_payload!("current Grade does not match") unless current_grade == expected_grade

      candidate_grade = data["confirmed_candidate_grade"].presence
      if candidate_grade && !candidate_grade.in?(Ec::SkuMarketingState::GRADES)
        invalid_payload!("invalid confirmed candidate Grade")
      end
      %w[grade_change_recommended downgrade_precondition_met downgrade_suppressed].each do |field|
        invalid_payload!("#{field} must be boolean") unless data[field].in?([ true, false ])
      end
      recovery_status = data["recovery_status"].to_s
      invalid_payload!("invalid recovery status") unless recovery_status.in?(%w[none observing confirmed failed])
      if data["grade_change_recommended"] && (candidate_grade.nil? || candidate_grade == current_grade)
        invalid_payload!("recommended Grade change requires a different candidate")
      end
      if recovery_status.in?(%w[observing confirmed]) && (data["grade_change_recommended"] || !data["downgrade_suppressed"])
        invalid_payload!("recovery must suppress a Grade change")
      end
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
      invalid_payload!("limit must be between 1 and #{MAX_HISTORY_LIMIT}") unless limit.between?(1, MAX_HISTORY_LIMIT)
      limit
    rescue ArgumentError, TypeError
      invalid_payload!("limit must be between 1 and #{MAX_HISTORY_LIMIT}")
    end

    def normalized_events(events)
      invalid_payload!("events must be a non-empty array") unless events.is_a?(Array) && events.any?

      events.each_with_index.map do |event, position|
        invalid_payload!("each event must be an object") unless event.is_a?(Hash)

        event_type = event["event_type"].presence || event["type"].presence
        severity = event["severity"].presence
        message = event["message"].presence
        invalid_payload!("event_type, severity and message are required") unless event_type && severity && message

        {
          event_type: event_type.to_s,
          severity: severity.to_s,
          scope: event["scope"],
          message: message.to_s,
          details: hash_value(event["details"], "event details"),
          position: position
        }.compact
      end
    end

    def normalized_grade_events(events)
      events.map.with_index do |event, position|
        invalid_payload!("each event must be an object") unless event.is_a?(Hash)

        event_type = event["event_type"].to_s
        expected_severity = EVENT_SEVERITIES[event_type]
        invalid_payload!("invalid Grade event type") unless expected_severity
        invalid_payload!("invalid severity for #{event_type}") unless event["severity"] == expected_severity
        invalid_payload!("event message is required") if event["message"].blank?
        invalid_payload!("event details must be an object") unless event["details"].is_a?(Hash)
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

    def diagnosis_data(payload)
      return hash_value(payload["data"], "data") if payload.key?("data")

      hash_value(payload["classification"], "classification")
        .merge(hash_value(payload["metrics"], "metrics"))
    end

    def required_string(value, field_name)
      invalid_payload!("#{field_name} is required") if value.blank?
      value.to_s
    end

    def analysis_cutoff_date(data)
      latest_observation = Array(data["weekly_observations"]).first
      observation_to_date = latest_observation["to_date"] if latest_observation.is_a?(Hash)
      value = data["analysis_cutoff_date"] || observation_to_date
      date = Date.iso8601(value.to_s)
      invalid_payload!("analysis_cutoff_date must be a Sunday") unless date.sunday?
      date
    rescue Date::Error
      invalid_payload!("latest weekly observation must end on an ISO 8601 Sunday")
    end

    def parsed_analyzed_at(value)
      return if value.blank?
      Time.iso8601(value.to_s)
    rescue ArgumentError
      invalid_payload!("analyzed_at must be an ISO 8601 timestamp")
    end

    def hash_value(value, field_name)
      return {} if value.nil?
      return value if value.is_a?(Hash)

      invalid_payload!("#{field_name} must be an object")
    end

    def default_scope_for(event_type)
      event_type.start_with?("grade_weekly_profit_") ? "profit" : "grade"
    end

    def invalid_payload!(message)
      raise InvalidPayload, message
    end
  end
end
