module ErpAI
  class SkuPlannerRunner
    AGENT_CODE = "sku_planner".freeze

    class ScopedToolExecutor
      def initialize(user:, sku:, plan_date: nil)
        @sku = sku
        @executor = ErpAI::ToolExecutor.new(mcp_clients: {}, current_user: user, event_date: plan_date)
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

    def self.run(sku_code: nil, user: nil, client: DefaultClient.new, context_builder: ErpAI::SkuPlannerContextBuilder, as_of_date: nil, period_start: nil, rerun: true)
      new(sku_code: sku_code, user: user, client: client, context_builder: context_builder, as_of_date: as_of_date, period_start: period_start, rerun: rerun).run
    end

    def initialize(sku_code: nil, user: nil, client: DefaultClient.new, runner_factory: nil, context_builder: ErpAI::SkuPlannerContextBuilder, as_of_date: nil, period_start: nil, rerun: true)
      @sku_code = sku_code
      @user = user
      @context_builder = context_builder
      @as_of_date = as_of_date&.to_date
      @period_start = period_start&.to_date&.beginning_of_week(:monday)
      @rerun = rerun
      @runner_factory = runner_factory || ->(agent:, user:, sku:, plan_date:) {
        ErpAI::AgentRunner.new(
          agent: agent,
          user: user,
          client: client,
          tool_executor: ScopedToolExecutor.new(user: user, sku: sku, plan_date: plan_date),
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

      plan_date = planner_date
      planning_period_start = @period_start || Ec::SkuOperationPlan.period_for(plan_date)
      historical_context = context_builder.call(sku: sku, period_start: planning_period_start)
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
        当前计划周期：#{planning_period_start.iso8601} 至 #{(planning_period_start + 6.days).iso8601}
        可用 Listing（scope_id 使用内部 id）：#{listings.to_json}

        下方是该 SKU 最新的非 info 通用诊断事件。info 事件已排除；warning 和 critical 表示诊断紧迫程度，仅供经营判断参考。
        以下是最近周期的历史 Plan / Evaluation Context。历史记录只用于识别已验证、无效、未执行或数据不足的方向，不得机械复制上一周期计划：
        #{historical_context.to_json}
        根据这些事件制定本周期值得执行的运营计划。只使用上方列出的 Listing 内部 id；没有足够依据时不调用 save_sku_plan。
      PROMPT

      sku.with_lock do
        plans = sku.sku_operation_plans
        existing_cycle = Ec::SkuPlanningCycle.current_for(sku: sku, period_start: planning_period_start)
        # Legacy plans predate PlanningCycle. Remove only those on the first
        # migrated run; subsequent runs retain every prior revision.
        plans.where(plan_date: plan_date, planning_cycle_id: nil).delete_all if existing_cycle.nil?
        planning_cycle = Ec::SkuPlanningCycleLock.acquire(
          sku: sku,
          period_start: planning_period_start,
          rerun: @rerun && existing_cycle.present?,
          status: "generating",
          diagnosis_event_ids: events.map(&:id),
          context_version: historical_context.fetch(:context_version)
        )
        existing_plan_ids = plans.pluck(:id)

        conversation = @runner_factory.call(agent: agent, user: user, sku: sku, plan_date: plan_date).ask(
          question: question,
          module_name: "sku_planner",
          business_object_type: "Ec::Sku",
          business_object_id: sku.id.to_s,
          data_summary: data_summary
        )
        generated_plan_ids = plans.where(plan_date: plan_date).where.not(id: existing_plan_ids).pluck(:id)
        plans.where(id: generated_plan_ids).update_all(planning_cycle_id: planning_cycle.id)
        planning_cycle.update!(status: "active", planner_conversation: conversation)
        plans.where(planning_cycle_id: nil).or(
          plans.where.not(planning_cycle_id: planning_cycle.id)
        ).latest.update_all(is_latest: false)
        if conversation.respond_to?(:context) && conversation.respond_to?(:update!)
          conversation.update!(context: conversation.context.merge(
            "history_plan_ids" => historical_context.fetch(:history_plan_ids),
            "context_version" => historical_context.fetch(:context_version),
            "planning_period_start" => planning_period_start.iso8601,
            "planning_period_end" => (planning_period_start + 6.days).iso8601,
            "input_summary" => {
              "diagnosis_event_ids" => events.map(&:id),
              "history_plan_ids" => historical_context.fetch(:history_plan_ids),
              "cycle" => historical_context.fetch(:cycle)
            }
          ))
        end
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

    attr_reader :context_builder

    def planner_date
      @as_of_date || Time.current.in_time_zone(Ec::SkuOperationPlan::TIME_ZONE).to_date
    end

    def execution_user
      User.joins(:roles).where(active: true, roles: { code: "super_admin" }).first || raise("No super admin available for SKU planner")
    end
  end
end
