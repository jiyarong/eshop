module AITasks
  class SkuOperationActionEffectDiagnosisJob < ApplicationJob
    queue_as :default

    def perform(as_of_date: nil)
      Rails.logger.info("----暂时不自动跑运营诊断，需要手动触发----")
      # AITasks::SkuOperationActionEffectDiagnosis.run(as_of_date: as_of_date)
    end
  end
end
