module AITasks
  class SkuPlannerJob < ApplicationJob
    queue_as :default
    limits_concurrency to: AITasks::SkuPlanningConcurrency::MAX_CONCURRENT_SKUS,
      key: ->(*) { "sku_planners" },
      duration: 1.hour

    retry_on Ec::SkuPlanningDataReadiness::NotReady, wait: 30.minutes, attempts: 5
    retry_on ErpAI::SkuPlannerRunner::EvaluationFailed, wait: 5.minutes, attempts: 3
    retry_on AITasks::SkuPlanningPipelineJob::DiagnosisIncomplete, wait: 5.minutes, attempts: 3

    def perform(sku_code: nil, as_of_date: nil, pipeline: false, diagnosis_started_at: nil)
      return enqueue_batch(as_of_date:) if sku_code.blank?

      if pipeline && !AITasks::SkuPlanningPipelineJob.diagnosis_complete?(
        as_of_date: as_of_date,
        sku_code: sku_code,
        started_at: diagnosis_started_at
      )
        raise AITasks::SkuPlanningPipelineJob::DiagnosisIncomplete, "SKU diagnosis is incomplete for #{sku_code}"
      end

      arguments = { sku_code: sku_code }
      arguments[:as_of_date] = as_of_date if as_of_date.present?
      arguments[:rerun] = false if pipeline
      ErpAI::SkuPlannerRunner.run(**arguments)
    end

    private

    def enqueue_batch(as_of_date:)
      date = as_of_date.presence || Time.current.in_time_zone(ErpAI::SkuDiagnosisRunner::TIME_ZONE).to_date
      ErpAI::SkuDiagnosisRunner.batch_sku_codes(as_of_date: date).each do |sku_code|
        self.class.perform_later(as_of_date: date, sku_code: sku_code)
      end
    end
  end
end
