# frozen_string_literal: true

module AiEval
  class DiagnosisAdapter
    def initialize(agent:, client: ErpAI::DefaultClient.new)
      @agent, @client = agent, client
    end

    def call(documents:, metadata:, rule:)
      metadata = ModelSession.metadata(metadata)
      rule_id = ModelSession.read(rule, :id)
      prompt = ModelSession.read(rule, :prompt)
      configuration = ModelSession.read(rule, :configuration, {}).to_h.stringify_keys
      keys = Array(ModelSession.read(rule, :context_keys, configuration["context_keys"]))
      raise ArgumentError, "rule ID, prompt and context keys are required" unless rule_id.is_a?(Integer) && prompt.present? && keys.any?
      snapshot = documents.fetch("unified_snapshot.json").deep_stringify_keys
      raise ArgumentError, "snapshot SKU does not match case" unless snapshot.fetch("sku_code") == metadata.fetch(:sku_code)
      raise ArgumentError, "snapshot date does not match case" unless snapshot.dig("period", "as_of") == metadata.fetch(:as_of)
      platforms = keys.filter_map { |key| { "ozon_listing_content" => "ozon", "wb_listing_content" => "wb" }[key] }
      raise ArgumentError, "listing image/content replay is not captured by this adapter" if platforms.any?
      sections = keys.map do |key|
        category = snapshot.fetch("categories").fetch(key)
        ["**#{category.fetch('name')}**", category["description"].presence || Ec::SkuContextSnapshot.context_descriptions.fetch(key.to_sym),
          category.fetch("markdown").strip].filter_map { |value| value.to_s.strip.presence }.join("\n\n")
      end
      period = snapshot.fetch("period")
      summary = ["SKU：#{snapshot.fetch('sku_code')}",
        "数据周期：#{period.fetch('from')} 至 #{period.fetch('to')}；快照日期：#{period.fetch('as_of')}", sections.join("\n\n---\n\n")].join("\n\n")
      question = ErpAI::SkuEvaluationPrompts.diagnosis(sku_code: metadata.fetch(:sku_code), rule_id:, rule_prompt: prompt,
        event_types: Array(ModelSession.read(rule, :allowed_event_types, configuration["allowed_event_types"])))
      executor = EvaluationToolExecutor.new(sku_code: metadata.fetch(:sku_code), as_of: metadata.fetch(:as_of),
        allowed_tools: ["save_sku_event"], rule_id:)
      system_prompt = [ModelSession.read(@agent, :system_prompt), ErpAI::SkuDiagnosisRunner::SIMPLE_CONTEXT_SYSTEM_PROMPT].join("\n\n")
      result = ModelSession.new(agent: @agent, client: @client).call(question:, context: summary, executor:, system_prompt:)
      events = executor.captures.map { |event| event.except("capture_key").merge("rule_name" => ModelSession.read(rule, :name)) }
      result[:output] = result.fetch(:output).merge(events:)
      if result[:status] == "completed" && events.empty?
        result[:status] = "failed"
        result[:errors] = [{ code: "missing_diagnosis_event" }]
      end
      result.merge(metadata:, rule_fingerprint: ModelSession.fingerprint(id: rule_id, prompt:, context_keys: keys, configuration:),
        prompt_boundary: "production_question_and_rule_context")
    rescue KeyError, ArgumentError => error
      { status: "blocked", output: {}, metadata:, trace: [], gates: [{ name: "diagnosis_input", passed: false }],
        errors: [{ code: "invalid_diagnosis_input", message: error.message }] }
    end
  end
end
