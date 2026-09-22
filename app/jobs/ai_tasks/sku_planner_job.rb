module AITasks
  class SkuPlannerJob < ApplicationJob
    queue_as :default

    def perform(sku_code: nil)
      ErpAI::SkuPlannerRunner.run(sku_code: sku_code)
    end
  end
end
