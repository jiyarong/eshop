module ErpAI
  class SkuPlannerRunner
    AGENT_CODE = "sku_planner".freeze

    class ScopedToolExecutor
      def initialize(user:, sku:)
        @sku = sku
        @executor = ErpAI::ToolExecutor.new(mcp_clients: {}, current_user: user)
      end

      def conversation_id=(conversation_id)
        @executor.conversation_id = conversation_id
      end

      def call(id:, name:, arguments:)
        args = arguments.to_h.stringify_keys
        return { tool_call_id: id, name: name, error: { code: "invalid_scope" } } unless name == "save_sku_plan"
        return { tool_call_id: id, name: name, error: { code: "invalid_scope" } } unless args["sku_code"].to_s.upcase == @sku.sku_code

        result = @executor.call(id: id, name: name, arguments: args)
        error = result[:error] || result.dig(:result, :error)
        raise "SKU planner tool failed: #{error}" if error

        result
      end
    end

    def self.run(sku_code: nil, user: nil, client: DefaultClient.new)
      new(sku_code: sku_code, user: user, client: client).run
    end

    def initialize(sku_code: nil, user: nil, client: DefaultClient.new, runner_factory: nil)
      @sku_code = sku_code
      @user = user
      @runner_factory = runner_factory || ->(agent:, user:, sku:) {
        ErpAI::AgentRunner.new(
          agent: agent,
          user: user,
          client: client,
          tool_executor: ScopedToolExecutor.new(user: user, sku: sku),
          tool_names: [ "save_sku_plan" ]
        )
      }
    end

    def run
      agent = Agent.ensure_fixed!(AGENT_CODE)
      return [] unless agent.enabled?

      user = @user || execution_user
      skus = diagnosis_skus
      skus.filter_map do |sku|
        run_sku(agent, user, sku)
      rescue StandardError => e
        Rails.logger.error("SKU planner failed for #{sku.sku_code}: #{e.class}: #{e.message}")
        nil
      end
    end

    private

    def diagnosis_skus
      scope = Ec::Sku
        .joins(ai_diagnoses: :events)
        .where(
          ec_ai_diagnosis: { type: Ec::GeneralDiagnosis.sti_name, is_latest: true }
        )
        .distinct
      scope = scope.where(sku_code: @sku_code) if @sku_code.present?
      scope.order(:sku_code).to_a
    end

    def run_sku(agent, user, sku)
      events = latest_events_for(sku)
      return if events.empty?

      data_summary = events.map do |event|
        {
          severity: event.severity,
          event_type: event.event_type,
          simple_context: event.simple_context,
          message: event.message,
          rule_name: event.sub_agent&.name
        }
      end.to_json
      question = <<~PROMPT
        当前 SKU：#{sku.sku_code}

        下方是该 SKU 通用诊断中所有 is_latest 事件。请仅基于这些事件制定运营操作计划。
        每条计划必须调用 save_sku_plan，target 只能是 price、advertising、listing_attribute、listing_image，operation 只能是 increase、open、close、modify、maintain，referer 必须填写对应的一个或多个 event_type，message 写清操作依据和具体执行详情。
        有明确依据时可以创建一条或多条计划；没有足够依据时可以不调用工具。不要处理其他 SKU，不要编造事件。
      PROMPT

      sku.with_lock do
        zone = Time.find_zone!("Asia/Shanghai")
        day_start = zone.now.beginning_of_day
        day_end = day_start + 1.day
        plans = sku.sku_operation_plans
        plans.where(created_at: day_start...day_end).delete_all

        conversation = @runner_factory.call(agent: agent, user: user, sku: sku).ask(
          question: question,
          module_name: "sku_planner",
          business_object_type: "Ec::Sku",
          business_object_id: sku.id.to_s,
          data_summary: data_summary
        )
        plans.where.not(created_at: day_start...day_end).latest.update_all(is_latest: false)
        conversation
      end
    end

    def latest_events_for(sku)
      Ec::AIDiagnosisEvent
        .joins(:ai_diagnosis)
        .where(
          ec_ai_diagnosis: { sku_id: sku.id, type: Ec::GeneralDiagnosis.sti_name, is_latest: true }
        )
        .includes(:sub_agent)
        .order(:position, :id)
        .to_a
    end

    def execution_user
      User.joins(:roles).where(active: true, roles: { code: "super_admin" }).first || raise("No super admin available for SKU planner")
    end
  end
end
