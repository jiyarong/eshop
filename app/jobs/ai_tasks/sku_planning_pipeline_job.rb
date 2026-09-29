module AITasks
  class SkuPlanningPipelineJob < ApplicationJob
    queue_as :default

    def perform(as_of_date: nil, sku_code: nil)
      date = as_of_date.presence || Time.current.in_time_zone(ErpAI::SkuDiagnosisRunner::TIME_ZONE).to_date
      Ec::SkuOperationPlanEvaluationRunner.run(as_of_date: date, sku_code: sku_code)
      ErpAI::SkuDiagnosisRunner.run(as_of_date: date, sku_code: sku_code)
      ErpAI::SkuPlannerRunner.run(sku_code: sku_code)
    end
  end
end
