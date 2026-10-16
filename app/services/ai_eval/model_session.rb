# frozen_string_literal: true

require "digest"

module AiEval
  # Uses the production provider and tool definitions, with messages kept only in
  # memory. It never constructs a production AgentRunner or ToolExecutor.
  class ModelSession
    def self.read(object, key, default = nil)
      return object.fetch(key.to_s) { object.fetch(key.to_sym, default) } if object.is_a?(Hash)
      object.respond_to?(key) ? object.public_send(key) : default
    end

    def self.fingerprint(value)
      canonical = lambda do |item|
        case item
        when Hash then item.stringify_keys.sort.to_h.transform_values { |child| canonical.call(child) }
        when Array then item.map { |child| canonical.call(child) }
        else item
        end
      end
      Digest::SHA256.hexdigest(canonical.call(value).to_json)
    end

    def self.metadata(metadata)
      values = metadata.to_h.symbolize_keys
      raise ArgumentError, "sku_code is required" if values[:sku_code].blank?
      raise ArgumentError, "time_zone must be Asia/Shanghai" unless values[:time_zone] == "Asia/Shanghai"
      values.merge(as_of: Date.iso8601(values.fetch(:as_of).to_s).iso8601)
    end

    def initialize(agent:, client: ErpAI::DefaultClient.new, max_tool_rounds: ErpAI::AgentRunner::DEFAULT_MAX_TOOL_ROUNDS)
      @agent, @client, @max_tool_rounds = agent, client, max_tool_rounds
    end

    def call(question:, context:, executor:, system_prompt: nil, images: [], allow_raw_json: false)
      trace = []
      system_prompt ||= self.class.read(@agent, :system_prompt)
      model = self.class.read(@agent, :model_id)
      raise ArgumentError, "agent model and system prompt are required" if model.blank? || system_prompt.blank?
      raise ArgumentError, "max_tool_rounds must be positive" unless @max_tool_rounds.is_a?(Integer) && @max_tool_rounds.positive?
      content = images.empty? ? question : [{ type: "text", text: question }, *images]
      messages = [{ role: "user", content: }]
      tools = ErpAI::ToolRegistry.default_tools.select { |tool| executor.allowed_tools.include?(tool.fetch(:name)) }
      request_base = {
        model:, temperature: self.class.read(@agent, :temperature, 0.1).to_f,
        thinking_enabled: self.class.read(@agent, :thinking_enabled?, self.class.read(@agent, :thinking_enabled, false)),
        thinking_level: self.class.read(@agent, :thinking_level), system_prompt:, context:, tools:
      }
      request_base[:allow_raw_json] = true if allow_raw_json
      fingerprint = self.class.fingerprint(request_base.merge(question:, images:))
      (@max_tool_rounds + 1).times do |round|
        request = request_base.merge(messages: messages.deep_dup)
        response = @client.complete(request).to_h.deep_symbolize_keys
        trace << { round:, request:, response: response.deep_dup }
        calls = Array(response[:tool_calls])
        if calls.empty?
          raise ArgumentError, "model response has no content or tool calls" if response[:content].blank?
          return { status: "completed", output: { content: response[:content], captures: executor.captures.deep_dup }, trace:, fingerprint:,
            gates: [{ name: "tool_isolation", passed: true }] }
        end
        raise ArgumentError, "model exceeded tool round limit" if round >= @max_tool_rounds
        messages << { role: "assistant", content: { tool_calls: calls }.to_json }
        calls.each do |call|
          result = executor.call(id: call[:id], name: call[:name], arguments: call[:arguments])
          trace.last[:tool_results] ||= []
          trace.last[:tool_results] << result.deep_dup
          messages << { role: "user", content: "工具调用结果：#{result.to_json}" }
          if executor.violations.any?
            return { status: "blocked", output: { captures: executor.captures.deep_dup }, trace:, fingerprint:,
              gates: [{ name: "tool_isolation", passed: false }], errors: executor.violations.deep_dup }
          end
        end
      end
    rescue StandardError => error
      { status: "error", output: {}, trace:, fingerprint:, gates: [{ name: "model_execution", passed: false }],
        errors: [{ code: error.class.name, message: error.message }] }
    end
  end
end
