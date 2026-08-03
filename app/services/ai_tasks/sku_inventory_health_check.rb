module AITasks
  class SkuInventoryHealthCheck
    AGENT_CODE = "sku-inventory-health-check-web".freeze

    def self.run(sku_code:)
      new(sku_code:).run
    end

    def initialize(sku_code:)
      @sku_code = sku_code
    end

    def run
      agent = Agent.find_by!(code: AGENT_CODE)
      user = User.find_by(email: 'admin@qq.com')||User.first
      ErpAI::AgentRunner.new(agent: agent, user: user).ask(question: question, data_summary: data_summary)
    end

    private

    attr_reader :sku_code

    def question
      previous_week = 1.week.ago
      "分析#{sku_code} 并写入events，上个自然周日期范围：#{previous_week.beginning_of_week.to_date}~#{previous_week.end_of_week.to_date}"
    end

    def data_summary
      sku = Ec::Sku.find_by!(sku_code: sku_code)
      previous_diagnosis = Ec::RestockingDiagnosis.where(sku_id: sku.id, is_latest: true).take
      events = previous_diagnosis&.events
      result = []
      if events.present?
        pre_event = "上次诊断信息：#{previous_diagnosis.created_at.to_s} #{previous_diagnosis.data.map { |k, v| "#{k}: #{v}" }.join(", ")}"
        pre_event << "\n事件：#{events.map { |event| "#{event.event_type}(#{event.severity}): #{event.message}" }.join(", ")}"
      else
        pre_event = "无上次诊断结果"
      end

      recent_operator_actions =  Ec::OperationAction.where(ec_sku_id: sku.id, record_by_system: false).where("created_at >= ?", 1.week.ago).order(created_at: :desc).limit(5)
      # 暂无需要关注的自动记录操作类型，暂时注释掉
      # OPERATION_TYPES = %w[
      #   listing_content
      #   listing_pricing
      #   listing_specification
      #   sku_adv_on_off
      #   sku_inbound_change
      # ].freeze
      # recent_auto_record_actions =  Ec::OperationAction.where(ec_sku_id: sku.id, record_by_system: true, operation_type: []).where("created_at >= ?", 1.week.ago).order(created_at: :desc).limit(5)
      

      operation_actions = recent_operator_actions.map do |action|
        "操作类型: #{action.operation_type}, 操作人: #{action.operated_by_user.display_name}, 操作时间: #{action.operated_at}, 变更内容: #{action.diff_result}"
      end
      result << pre_event if pre_event.present?
      result << "最近一周人工操作记录：#{operation_actions.join("; ")}" if operation_actions.present?

      result.join("\n")
    end
  end
end
