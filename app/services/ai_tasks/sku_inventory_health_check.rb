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

      ErpAI::AgentRunner.new(agent: agent, user: User.take).ask(question: question)
    end

    private

    attr_reader :sku_code

    def question
      previous_week = 1.week.ago
      "分析#{sku_code} 并写入events，上个自然周日期范围：#{previous_week.beginning_of_week.to_date}~#{previous_week.end_of_week.to_date}"
    end
  end
end
