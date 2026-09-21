module AITasks
  class SkuDiagnosisJob < ApplicationJob
    queue_as :default

    def perform(as_of_date: nil, sku_code: nil, rule_ids: nil, summary: false, force: false)
      ErpAI::SkuDiagnosisRunner.run(
        as_of_date: as_of_date,
        sku_code: sku_code,
        rule_ids: rule_ids
      )
    end
  end
end
