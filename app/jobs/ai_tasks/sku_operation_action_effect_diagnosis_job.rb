module AITasks
  class SkuOperationActionEffectDiagnosisJob < ApplicationJob
    queue_as :default

    def perform(as_of_date: nil)
      AITasks::SkuOperationActionEffectDiagnosis.run(as_of_date: as_of_date)
    end
  end
end
