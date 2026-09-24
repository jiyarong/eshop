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
          id: event.id,
          severity: event.severity,
          event_type: event.event_type,
          simple_context: event.simple_context,
          details: event.details,
          message: event.message,
          rule_name: event.sub_agent&.name
        }
      end.to_json
      listings = sku.sku_products.order(:id).pluck(:id, :platform, :store_id, :product_id).map do |id, platform, store_id, product_id|
        { id: id.to_s, platform: platform, store_id: store_id, product_id: product_id }
      end
      question = <<~PROMPT
        当前 SKU：#{sku.sku_code}
        可用 Listing（scope_id 使用内部 id）：#{listings.to_json}

        下方是该 SKU 最新的非 info 通用诊断事件。info 事件已排除；warning 和 critical 表示诊断紧迫程度，仅供经营判断参考。
        根据这些事件制定本周期值得执行的运营计划。只使用上方列出的 Listing 内部 id；没有足够依据时不调用 save_sku_plan。
      PROMPT

      sku.with_lock do
        plan_date = Time.current.in_time_zone("Asia/Shanghai").to_date
        plans = sku.sku_operation_plans
        plans.where(plan_date: plan_date).delete_all

        conversation = @runner_factory.call(agent: agent, user: user, sku: sku).ask(
          question: question,
          module_name: "sku_planner",
          business_object_type: "Ec::Sku",
          business_object_id: sku.id.to_s,
          data_summary: data_summary
        )
        plans.where.not(plan_date: plan_date).latest.update_all(is_latest: false)
        conversation
      end
    end

    def latest_events_for(sku)
      Ec::AIDiagnosisEvent
        .joins(:ai_diagnosis)
        .where(
          ec_ai_diagnosis: { sku_id: sku.id, type: Ec::GeneralDiagnosis.sti_name, is_latest: true }
        )
        .where.not(severity: "info")
        .includes(:sub_agent)
        .order(:position, :id)
        .to_a
    end

    def execution_user
      User.joins(:roles).where(active: true, roles: { code: "super_admin" }).first || raise("No super admin available for SKU planner")
    end
  end
end
