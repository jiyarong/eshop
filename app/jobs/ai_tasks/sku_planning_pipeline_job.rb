module AITasks
  class SkuPlanningPipelineJob < ApplicationJob
    queue_as :default

    class DiagnosisIncomplete < StandardError; end
    class EvaluationFailed < StandardError; end

    retry_on ErpAI::SkuDiagnosisRunner::Failure, wait: 5.minutes, attempts: 3
    retry_on DiagnosisIncomplete, wait: 5.minutes, attempts: 3
    retry_on EvaluationFailed, wait: 5.minutes, attempts: 3
    retry_on ErpAI::SkuPlannerRunner::Failure, wait: 5.minutes, attempts: 3
    retry_on ErpAI::SkuPlannerRunner::EvaluationFailed, wait: 5.minutes, attempts: 3

    STAGES = %w[evaluation diagnosis planner].freeze

    # A batch invocation dispatches one per-SKU stage chain. A direct SKU
    # invocation runs its stages synchronously, and can resume at a later stage.
    def perform(as_of_date: nil, sku_code: nil, stage: nil)
      date = (as_of_date.presence || Time.current.in_time_zone(ErpAI::SkuDiagnosisRunner::TIME_ZONE).to_date).to_date
      if sku_code.blank? && stage.blank?
        enqueue_sku_pipelines(as_of_date: date)
        return
      end

      stages = stages_from(stage)
      started_at = Time.current

      if stages.include?("evaluation")
        evaluations = Ec::SkuOperationPlanEvaluationRunner.run(
          as_of_date: date,
          sku_code: sku_code,
          client: ErpAI::DefaultClient.new,
          agent: Agent.ensure_fixed!("sku_plan_evaluation")
        )
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
        zone = Time.find_zone!(ErpAI::SkuDiagnosisRunner::TIME_ZONE)
        period_start = date.beginning_of_week(:monday)
        from = zone.local(period_start.year, period_start.month, period_start.day)
        to = zone.local(date.year, date.month, date.day) + 1.day
        events = events.where(ec_ai_diagnosis: { created_at: from...to })
          .where("ec_ai_diagnosis_events.scope IS NULL OR ec_ai_diagnosis_events.scope != ?", "advise")
        events = events.where("ec_ai_diagnosis_events.created_at >= ?", started_at) if started_at
        event_rule_ids_by_sku = events.pluck("ec_ai_diagnosis.sku_id", :sub_agent_id)
          .group_by(&:first)
          .transform_values { |rows| rows.filter_map(&:last).to_set }

        skus.all? do |sku|
          required_rule_ids = rules.filter_map { |rule| rule.id if rule.applies_to_sku?(sku) }
          completed_rule_ids = event_rule_ids_by_sku.fetch(sku.id, Set.new)
          required_rule_ids.all? { |rule_id| completed_rule_ids.include?(rule_id) }
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

    def enqueue_sku_pipelines(as_of_date:)
      diagnosis_sku_codes = ErpAI::SkuDiagnosisRunner.batch_sku_codes(as_of_date: as_of_date)
      diagnosis_sku_code_set = diagnosis_sku_codes.to_set
      evaluation_sku_codes = Ec::SkuOperationPlanEvaluationRunner.sku_codes(
        as_of_date: as_of_date,
        force: false
      )

      (diagnosis_sku_codes + evaluation_sku_codes).uniq.each do |sku_code|
        AITasks::SkuOperationPlanEvaluationJob.perform_later(
          as_of_date: as_of_date,
          sku_code: sku_code,
          force: false,
          pipeline: true,
          continue_to_diagnosis: diagnosis_sku_code_set.include?(sku_code)
        )
      end
    end

    def stages_from(stage)
      self.class.send(:stages_from, stage)
    end
  end
end
