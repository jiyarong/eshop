module ErpAI
  class DiagnosisResultsController < ActionController::API
    include ErpAI::RequestAuthenticatable

    class InvalidPayload < StandardError; end

    def create
      attributes = diagnosis_attributes
      sku = Ec::Sku.find_by!(sku_code: attributes.delete(:sku_code))
      type = attributes.delete(:type)
      if type == "RestockingDiagnosis" && !Ec::SkuInventoryHealthSubmissionLock.acquire(sku.id)
        response.set_header("Retry-After", Ec::SkuInventoryHealthSubmissionLock::TTL.to_i.to_s)
        render json: { error: "SKU submission is locked; retry after 5 seconds" }, status: :too_many_requests
        return
      end

      result = Ec::AIDiagnosisSubmission.create!(
        type: type,
        sku: sku,
        submitted_by: @current_user,
        **attributes
      )

      render json: {
        data: {
          id: result.id,
          type: result.type,
          sku: sku.sku_code,
          grade: sku.current_marketing_state&.grade,
          analyzed_at: result.analyzed_at,
          submitted_by: @current_user.display_name,
          submitted_at: result.created_at,
          event_count: result.events.size
        }
      }, status: :created
    rescue InvalidPayload, ArgumentError => e
      render json: { error: e.message }, status: :bad_request
    rescue ActiveRecord::RecordNotFound
      render json: { error: "SKU not found" }, status: :not_found
    end

    private

    def diagnosis_attributes
      payload = request.request_parameters
      invalid_payload!("payload must be an object") unless payload.respond_to?(:deep_stringify_keys)
      payload = payload.deep_stringify_keys
      invalid_payload!("payload must be an object") if payload.key?("_json")

      {
        type: required_string(payload["type"], "type"),
        sku_code: required_string(payload["sku"], "sku").strip.upcase,
        analyzed_at: parsed_analyzed_at(payload["analyzed_at"]) || Time.current,
        data: diagnosis_data(payload),
        events: normalized_events(payload["events"])
      }
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

    def diagnosis_data(payload)
      return hash_value(payload["data"], "data") if payload.key?("data")

      hash_value(payload["classification"], "classification")
        .merge(hash_value(payload["metrics"], "metrics"))
    end

    def required_string(value, field_name)
      invalid_payload!("#{field_name} is required") if value.blank?

      value.to_s
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

    def invalid_payload!(message)
      raise InvalidPayload, message
    end
  end
end
