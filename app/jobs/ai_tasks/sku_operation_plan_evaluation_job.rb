module AITasks
  class SkuOperationPlanEvaluationJob < ApplicationJob
    queue_as :default
    class EvaluationFailed < StandardError; end

    retry_on EvaluationFailed, wait: 5.minutes, attempts: 3

    def perform(as_of_date: nil, period_start: nil, plan_id: nil, sku_code: nil)
      agent = Agent.ensure_fixed!("sku_plan_evaluation")
      evaluations = Ec::SkuOperationPlanEvaluationRunner.run(
        as_of_date: as_of_date,
        period_start: period_start,
        plan_id: plan_id,
        sku_code: sku_code,
        client: ErpAI::DefaultClient.new,
        agent: agent,
        force: true
      )
      raise EvaluationFailed, "SKU plan evaluation failed" if Array(evaluations).any? { |evaluation| evaluation.respond_to?(:status) && evaluation.status == "failed" }
    end
  end
end
