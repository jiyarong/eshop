module Ec
  class OperationTaskGenerator
    LOW_AVAILABLE_THRESHOLD = 5

    def initialize(sku_code:)
      @sku_code = sku_code.to_s.upcase
    end

    def call
      tasks = []
      tasks << create_replenish_task if low_available_inventory?
      tasks.compact
    end

    private

    attr_reader :sku_code

    def inventory_total
      @inventory_total ||= Ec::InventoryTotal.find_by(sku_code: sku_code)
    end

    def low_available_inventory?
      inventory_total && inventory_total.total_available < LOW_AVAILABLE_THRESHOLD
    end

    def create_replenish_task
      Ec::OperationTask.find_or_create_by!(
        task_type: "replenish",
        status: "open",
        sku_code: sku_code,
        title: "#{sku_code} 库存不足，检查补货"
      ) do |task|
        task.priority = "high"
        task.reason = "总可售库存低于 #{LOW_AVAILABLE_THRESHOLD}。"
        task.suggested_action = "检查近 30 天动销、采购周期和在途库存，确认是否需要补货。"
      end
    end
  end
end
