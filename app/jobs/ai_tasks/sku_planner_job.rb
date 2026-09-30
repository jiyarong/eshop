module AITasks
  class SkuPlannerJob < ApplicationJob
    queue_as :default

    retry_on Ec::SkuPlanningDataReadiness::NotReady, wait: 30.minutes, attempts: 5
    retry_on ErpAI::SkuPlannerRunner::EvaluationFailed, wait: 5.minutes, attempts: 3

    def perform(sku_code: nil)
      ErpAI::SkuPlannerRunner.run(sku_code: sku_code)
    end
  end
end
