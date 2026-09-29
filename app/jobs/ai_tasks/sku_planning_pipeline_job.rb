module AITasks
  class SkuPlanningPipelineJob < ApplicationJob
    queue_as :default

    class DiagnosisIncomplete < StandardError; end
    class EvaluationFailed < StandardError; end

    retry_on ErpAI::SkuDiagnosisRunner::Failure, wait: 5.minutes, attempts: 3
    retry_on DiagnosisIncomplete, wait: 5.minutes, attempts: 3
    retry_on EvaluationFailed, wait: 5.minutes, attempts: 3

    STAGES = %w[evaluation diagnosis planner].freeze

    # The default invocation runs all stages synchronously. A retry can start
    # at a later stage when an earlier stage has already completed.
    def perform(as_of_date: nil, sku_code: nil, stage: nil)
      date = as_of_date.presence || Time.current.in_time_zone(ErpAI::SkuDiagnosisRunner::TIME_ZONE).to_date
      stages = stages_from(stage)
      started_at = Time.current

      if stages.include?("evaluation")
        evaluations = Ec::SkuOperationPlanEvaluationRunner.run(as_of_date: date, sku_code: sku_code)
        if Array(evaluations).any? { |evaluation| evaluation.respond_to?(:status) && evaluation.status == "failed" }
          raise EvaluationFailed, "SKU plan evaluation failed"
        end
      end
      ErpAI::SkuDiagnosisRunner.run(as_of_date: date, sku_code: sku_code) if stages.include?("diagnosis")

      if stages.include?("planner")
        diagnosis_started_at = started_at if stages.include?("diagnosis")
        unless self.class.diagnosis_complete?(as_of_date: date, sku_code: sku_code, started_at: diagnosis_started_at)
          raise DiagnosisIncomplete, "SKU diagnosis is incomplete for #{sku_code.presence || 'the planning batch'}"
        end

        ErpAI::SkuPlannerRunner.run(sku_code: sku_code, as_of_date: date, rerun: false)
      end
    end

    class << self
      # Every enabled rule applicable to the selected SKU must have a current
      # latest event before Planner is allowed to generate a plan.
      def diagnosis_complete?(as_of_date:, sku_code: nil, started_at: nil)
        date = as_of_date.to_date
        skus = if sku_code.present?
          Ec::Sku.where(sku_code: sku_code).to_a
        else
          codes = ErpAI::SkuDiagnosisRunner.batch_sku_codes(as_of_date: date)
          Ec::Sku.where(sku_code: codes).to_a
        end
        return true if skus.empty?

        rules = Ec::SkuDiagnosisRule.enabled_for(date).to_a
        return true if rules.empty?

        events = Ec::AIDiagnosisEvent
          .joins(:ai_diagnosis)
          .where(
            is_latest: true,
            ec_ai_diagnosis: { type: Ec::GeneralDiagnosis.sti_name, sku_id: skus.map(&:id) }
          )
        events = events.where("ec_ai_diagnosis_events.created_at >= ?", started_at) if started_at
        event_rule_ids_by_sku = events.pluck("ec_ai_diagnosis.sku_id", :sub_agent_id)
          .group_by(&:first)
          .transform_values { |rows| rows.filter_map(&:last).to_set }

        skus.all? do |sku|
          required_rule_ids = rules.filter_map { |rule| rule.id if rule.applies_to_sku?(sku) }
          required_rule_ids.empty? || (required_rule_ids - event_rule_ids_by_sku.fetch(sku.id, Set.new)).empty?
        end
      end

      private

      def stages_from(stage)
        return STAGES if stage.blank?

        normalized = stage.to_s
        raise ArgumentError, "unsupported pipeline stage: #{stage}" unless STAGES.include?(normalized)

        STAGES.drop(STAGES.index(normalized))
      end
    end

    private

    def stages_from(stage)
      self.class.send(:stages_from, stage)
    end
  end
end
