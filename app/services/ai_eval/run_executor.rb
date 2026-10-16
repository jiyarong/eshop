module AiEval
  class RunExecutor
    AGENT_CODES = { "diagnosis" => "sku_diagnosis", "planner" => "sku_planner", "plan_evaluation" => "sku_plan_evaluation" }.freeze

    def self.call(**options)
      new(**options).call
    end

    def initialize(run:, client: ErpAI::DefaultClient.new, adapters: {})
      @run, @client, @adapters = run, client, adapters
    end

    def call
      claimed = run.with_lock do
        next false unless run.status == "queued"
        run.update!(status: "materializing", started_at: Time.current)
        true
      end
      return run unless claimed

      materialized = run.case_record.materialize(anchor_date: run.settings["anchor_date"])
      metadata = materialized.metadata.deep_symbolize_keys.merge(
        sku_code: materialized.sku_code, as_of: materialized.snapshot_date.iso8601,
        time_zone: materialized.metadata.fetch(:time_zone)
      )
      fingerprint = SnapshotManifest.content_checksum(materialized.documents)
      run.update!(materialized_documents: materialized.documents, trace: {
        materialization: { fingerprint: fingerprint, as_of: metadata[:as_of], time_zone: metadata[:time_zone], sku_code: metadata[:sku_code],
          validation_errors: metadata[:validation_errors] }
      })
      selected = run.settings.fetch("adapters")
      if metadata[:validation_errors].present?
        self.class.score!(run)
        return run
      end
      @fixed_inputs = MaterializerDateShifter.new.call(run.case_record.definition.slice("planner_input", "evaluation_input"),
        days: (materialized.snapshot_date - materialized.snapshot.snapshot_date).to_i)
      AGENT_CODES.each_key do |name|
        next unless selected.include?(name)
        run.update!(status: "#{name}_running")
        result = execute(name, materialized.documents, metadata)
        store_result(name, result)
        if result[:status].to_s == "error"
          run.update!(status: "error", error: I18n.t("ai_eval.errors.adapter_failed", adapter: name), finished_at: Time.current)
          return run
        end
        if result[:status].to_s != "completed"
          self.class.score!(run)
          return run
        end
      end
      if selected.include?("activepieces")
        run.update!(status: "awaiting_activepieces")
      else
        self.class.score!(run)
      end
      run
    rescue StandardError => exception
      run.update!(status: "error", error: "#{exception.class}: #{exception.message}".gsub(/Bearer\s+\S+/i, "Bearer [REDACTED]").truncate(2000), finished_at: Time.current)
      run
    end

    def self.score!(run)
      run.update!(status: "scoring")
      oracle = run.case_record.oracle_for(as_of: run.trace.dig("materialization", "as_of") || run.case_record.reference_date)
      scores = run.settings.fetch("adapters").to_h do |name|
        contract = oracle.fetch(name)
        trace = run.trace.fetch(name, {})
        gates = Array(trace["gates"])
        gates += [{ name: "materialization_valid", passed: run.trace.dig("materialization", "validation_errors").blank? }]
        gates += [{ name: "execution_completed", passed: trace["status"] == "completed" }]
        score = Scoring.call(
          actual: run.outputs.fetch(name, {}), assertions: contract.fetch("assertions"),
          threshold: contract.fetch("threshold", 90), category_weights: contract.fetch("category_weights", {}),
          gates: gates, baseline: run.baseline&.scores&.dig(name),
          dataset_version: run.dataset_version, oracle_version: run.oracle_version
        )
        [name, score]
      end
      statuses = scores.values.map { |score| score[:status] }
      status = statuses.include?("blocked") ? "blocked" : (statuses.all? { |value| value == "passed" } ? "passed" : "failed")
      run.update!(scores: scores, status: status, finished_at: Time.current)
      run
    end

    private

    attr_reader :run, :client, :adapters

    def execute(name, documents, metadata)
      adapter = adapters[name] || build_adapter(name)
      case name
      when "diagnosis"
        rules = selected_rules(documents)
        return { status: "blocked", output: { events: [] }, gates: [{ name: "diagnosis_rules", passed: false }] } if rules.empty?
        results = rules.map { |rule| adapter.call(documents: documents, metadata: metadata, rule: rule) }
        {
          status: results.all? { |value| value[:status].to_s == "completed" } ? "completed" : (results.any? { |value| value[:status].to_s == "error" } ? "error" : "blocked"),
          output: { events: results.flat_map { |value| Array(value.dig(:output, :events) || value.dig(:output, "events")) } },
          trace: results.map { |value| value.except(:output) }, gates: results.flat_map { |value| Array(value[:gates]) }
        }
      when "planner"
        generated = run.outputs.dig("diagnosis", "events")
        input = @fixed_inputs.fetch("planner_input", {})
        source = run.settings.fetch("planner_source", generated ? "generated" : "fixed")
        events = source == "generated" ? generated : input["events"]
        return { status: "blocked", output: {}, gates: [{ name: "planner_events", passed: false }] } unless events.is_a?(Array)
        adapter.call(documents: documents, metadata: metadata, events: events,
          historical_context: metadata[:planner_context] || {})
      when "plan_evaluation"
        input = @fixed_inputs.fetch("evaluation_input")
        adapter.call(documents: documents, metadata: metadata, **input.slice("plan", "actions", "metrics", "diagnosis_context", "concurrent_actions").symbolize_keys)
      end
    end

    def selected_rules(documents)
      scope = Ec::SkuDiagnosisRule.where(enabled: true).order(:id)
      if run.settings["rule_ids"].present?
        ids = run.settings["rule_ids"].map(&:to_i).uniq
        rules = scope.where(id: ids).to_a
        return [] unless rules.map(&:id).sort == ids.sort
        return rules
      end
      base = documents.dig("v3/base_context.json", "data", "base") || {}
      state = Ec::SkuMarketingState.new(grade: base["current_grade"], stage: base["current_stage"]&.downcase)
      sku = Ec::Sku.new
      sku.current_marketing_state = state
      scope.select { |rule| rule.applies_to_sku?(sku) }
    end

    def build_adapter(name)
      agent = Agent.find_by!(code: AGENT_CODES.fetch(name))
      raise ArgumentError, I18n.t("ai_eval.errors.agent_disabled") unless agent.enabled?
      klass = { "diagnosis" => DiagnosisAdapter, "planner" => PlannerAdapter, "plan_evaluation" => PlanEvaluationAdapter }.fetch(name)
      klass.new(agent: agent, client: client)
    end

    def store_result(name, result)
      run.update!(outputs: run.outputs.merge(name => result.fetch(:output, {})),
        trace: run.trace.merge(name => result.except(:output)))
    end
  end
end
