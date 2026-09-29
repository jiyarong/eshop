module AITasks
  class SkuDiagnosisJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 4,
      key: ->(*) { "sku_diagnoses" },
      duration: 1.hour

    def perform(as_of_date: nil, sku_code: nil, rule_ids: nil, summary: false, force: false)
      return enqueue_batch(as_of_date: as_of_date, rule_ids: rule_ids) if sku_code.blank?

      ErpAI::SkuDiagnosisRunner.run(
        as_of_date: as_of_date,
        sku_code: sku_code,
        rule_ids: rule_ids
      )
    end

    private

    def enqueue_batch(as_of_date:, rule_ids:)
      diagnosis_date = as_of_date.presence || Time.current.in_time_zone(ErpAI::SkuDiagnosisRunner::TIME_ZONE).to_date

      ErpAI::SkuDiagnosisRunner.batch_sku_codes(as_of_date: diagnosis_date).each do |batch_sku_code|
        self.class.perform_later(
          as_of_date: diagnosis_date,
          sku_code: batch_sku_code,
          rule_ids: rule_ids
        )
      end
    end
  end
end
