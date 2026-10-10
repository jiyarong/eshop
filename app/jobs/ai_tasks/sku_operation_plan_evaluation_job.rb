module AITasks
  class SkuOperationPlanEvaluationJob < ApplicationJob
    queue_as :default
    limits_concurrency to: AITasks::SkuPlanningConcurrency::MAX_CONCURRENT_SKUS,
      key: ->(*) { "sku_plan_evaluations" },
      duration: 1.hour

    class EvaluationFailed < StandardError; end

    retry_on Ec::SkuPlanningDataReadiness::NotReady, wait: 30.minutes, attempts: 5
    retry_on EvaluationFailed, wait: 5.minutes, attempts: 3

    def perform(as_of_date: nil, period_start: nil, plan_id: nil, sku_code: nil, force: true,
      pipeline: false, continue_to_diagnosis: false)
      return enqueue_batch(as_of_date:, period_start:, force:, pipeline:, continue_to_diagnosis:) if plan_id.blank? && sku_code.blank?

      if pipeline
        date = (as_of_date.presence || Time.current.in_time_zone(ErpAI::SkuDiagnosisRunner::TIME_ZONE).to_date).to_date
        Ec::SkuPlanningDataReadiness.check!(as_of_date: date, sku_code: sku_code)
      end

      agent = Agent.ensure_fixed!("sku_plan_evaluation")
      evaluations = Ec::SkuOperationPlanEvaluationRunner.run(
        as_of_date: as_of_date,
        period_start: period_start,
        plan_id: plan_id,
        sku_code: sku_code,
        client: ErpAI::DefaultClient.new,
        agent: agent,
        force: force
      )
      raise EvaluationFailed, "SKU plan evaluation failed" if Array(evaluations).any? { |evaluation| evaluation.respond_to?(:status) && evaluation.status == "failed" }

      return unless pipeline && continue_to_diagnosis

      AITasks::SkuDiagnosisJob.perform_later(as_of_date: as_of_date, sku_code: sku_code, pipeline: true)
    end

    private

    def enqueue_batch(as_of_date:, period_start:, force:, pipeline:, continue_to_diagnosis:)
      sku_codes = Ec::SkuOperationPlanEvaluationRunner.sku_codes(
        as_of_date: as_of_date,
        period_start: period_start,
        force: force
      )
      sku_codes.each do |sku_code|
        self.class.perform_later(
          as_of_date: as_of_date,
          period_start: period_start,
          sku_code: sku_code,
          force: force,
          pipeline: pipeline,
          continue_to_diagnosis: continue_to_diagnosis
        )
      end
    end
  end
end
