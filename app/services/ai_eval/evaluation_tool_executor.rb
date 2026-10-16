# frozen_string_literal: true

module AiEval
  class EvaluationToolExecutor
    attr_reader :allowed_tools, :captures, :violations

    def initialize(sku_code:, as_of:, allowed_tools:, rule_id: nil, listings: [], events: [])
      @sku_code, @as_of, @allowed_tools, @rule_id = sku_code, Date.iso8601(as_of.to_s), allowed_tools, rule_id
      @listings = listings.map { |listing| listing.to_h.deep_stringify_keys }
      @events = events.map { |event| event.to_h.deep_stringify_keys }
      @captures, @violations = [], []
      raise ArgumentError, "unsupported tool allowlist" if (allowed_tools - %w[save_sku_event save_sku_plan]).any?
    end

    def call(id:, name:, arguments:)
      raise ArgumentError, "tool is not allowed" unless allowed_tools.include?(name)
      args = arguments.is_a?(String) ? JSON.parse(arguments) : arguments
      raise ArgumentError, "tool arguments must be an object" unless args.is_a?(Hash)
      args = args.deep_stringify_keys
      definition = ErpAI::ToolRegistry.default_tools.find { |tool| tool.fetch(:name) == name }
      validate_schema!(args, definition.fetch(:parameters).deep_stringify_keys)
      raise ArgumentError, "tool SKU does not match case" unless args["sku_code"] == @sku_code
      capture = name == "save_sku_event" ? event(args) : plan(args)
      captures.reject! { |item| item["capture_key"] == capture["capture_key"] }
      captures << capture
      { tool_call_id: id, name:, result: capture.except("capture_key").merge("success" => true) }
    rescue ArgumentError, JSON::ParserError => error
      violation = { code: "invalid_eval_tool_call", tool: name, message: error.message }
      violations << violation
      { tool_call_id: id, name:, error: violation }
    end

    private

    def event(args)
      raise ArgumentError, "rule ID does not match case" unless args["sub_agent_id"] == @rule_id && @rule_id.is_a?(Integer)
      raise ArgumentError, "invalid severity" unless %w[info warning critical].include?(args["severity"])
      require_text!(args, %w[event_type message simple_context])
      fingerprint = ModelSession.fingerprint(sku_code: @sku_code, rule_id: @rule_id, as_of: @as_of.iso8601)
      id = fingerprint[0, 12].to_i(16)
      args.merge("id" => id, "event_id" => id, "is_latest" => true,
        "created_at" => "#{@as_of.iso8601}T03:00:00+08:00", "capture_key" => fingerprint)
    end

    def plan(args)
      require_text!(args, %w[message reason baseline constraints expected_effect scope_id])
      raise ArgumentError, "priority must be a positive integer" unless args["priority"].positive?
      references = args.fetch("referer")
      valid = @events.select { |item| item["sku_code"] == @sku_code && item["is_latest"] == true && %w[warning critical].include?(item["severity"]) }
        .map { |item| item["id"] }
      raise ArgumentError, "referer must use current case diagnosis events" if references.empty? || (references - valid).any?
      unless Ec::SkuOperationPlan::TARGET_SCOPES.fetch(args["target"]).include?(args["scope"])
        raise ArgumentError, "scope is invalid for target"
      end
      if args["scope"] == "SKU"
        raise ArgumentError, "scope_id does not match SKU" unless args["scope_id"] == @sku_code
      else
        allowed_ids = @listings.map { |listing| listing.fetch("id").to_s }
        raise ArgumentError, "scope_id is not a Listing of this SKU" unless allowed_ids.include?(args["scope_id"])
      end
      period_start = @as_of.beginning_of_week(:monday)
      attributes = args.merge("planning_period_start" => period_start.iso8601)
      fingerprint = Ec::SkuOperationPlan.fingerprint_for(attributes)
      id = fingerprint[0, 12].to_i(16)
      attributes.merge("id" => id, "plan_id" => id, "plan_date" => @as_of.iso8601,
        "planning_period_end" => (period_start + 6).iso8601, "execution_deadline" => (period_start + 7).iso8601,
        "lifecycle_status" => "active", "execution_status" => "not_started", "evaluation_status" => "pending",
        "fingerprint" => fingerprint, "capture_key" => fingerprint)
    end

    def require_text!(args, keys)
      raise ArgumentError, "required text is blank" unless keys.all? { |key| args[key].is_a?(String) && args[key].strip.present? }
    end

    def validate_schema!(value, schema)
      types = Array(schema["type"])
      valid = types.any? do |type|
        case type
        when "object" then value.is_a?(Hash)
        when "array" then value.is_a?(Array)
        when "string" then value.is_a?(String)
        when "integer" then value.is_a?(Integer)
        when "null" then value.nil?
        else false
        end
      end
      raise ArgumentError, "tool argument has wrong type" unless valid
      raise ArgumentError, "tool argument is outside enum" if schema["enum"] && !schema["enum"].include?(value)
      if value.is_a?(Hash)
        properties = schema.fetch("properties", {})
        raise ArgumentError, "required tool argument missing" if (schema.fetch("required", []) - value.keys).any?
        raise ArgumentError, "unknown tool argument" if schema["additionalProperties"] == false && (value.keys - properties.keys).any?
        value.each { |key, child| validate_schema!(child, properties[key]) if properties[key] }
      elsif value.is_a?(Array)
        raise ArgumentError, "tool array is too short" if schema["minItems"] && value.length < schema["minItems"]
        value.each { |item| validate_schema!(item, schema["items"]) } if schema["items"]
      elsif value.is_a?(String) && schema["minLength"] && value.length < schema["minLength"]
        raise ArgumentError, "tool string is too short"
      end
    end
  end
end
