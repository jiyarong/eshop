module Ec
  class StageInspect < AIDiagnosis
    AUTO_STAGES = %w[GRW MAT].freeze
    CLEARANCE_EVENT_TYPE = "clearance_recommendation".freeze

    def process_persisted_events!
      diagnosed_stage = data["diagnosed_stage"].to_s.upcase.presence
      raise ArgumentError, "diagnosed_stage must be GRW, MAT or CLR" unless diagnosed_stage.in?(AUTO_STAGES + [ "CLR" ])

      if diagnosed_stage == "CLR"
        validate_clearance_event!
        return self
      end

      apply_stage!(diagnosed_stage)
      self
    end

    private

    def validate_clearance_event!
      clearance_events = events.select { |event| event.event_type == CLEARANCE_EVENT_TYPE }
      raise ArgumentError, "CLR requires one clearance_recommendation event" unless clearance_events.one?
      raise ArgumentError, "clearance_recommendation must be red" unless clearance_events.first.severity == "red"
    end

    def apply_stage!(target_stage)
      sku.lock!
      current_state = sku.marketing_states.current.lock.take
      raise ArgumentError, "current marketing state is required for automatic stage update" unless current_state

      diagnosed_current_stage = data["current_stage"].to_s.upcase.presence
      if diagnosed_current_stage.present? && diagnosed_current_stage != current_state.stage.upcase
        raise ArgumentError, "diagnosis current stage is stale"
      end

      return record_unchanged_execution!(current_state, target_stage) if current_state.stage.casecmp?(target_stage)

      executed_at = Time.current
      current_state.update!(ended_at: executed_at)
      new_state = sku.marketing_states.create!(
        grade: current_state.grade,
        stage: target_stage,
        effective_at: executed_at,
        changed_by: submitted_by,
        note: "Automatically updated by StageInspect ##{id}"
      )
      record_execution!(current_state.stage, target_stage, new_state.id, executed_at)
    end

    def record_unchanged_execution!(current_state, target_stage)
      record_execution!(current_state.stage, target_stage, current_state.id, Time.current, status: "unchanged")
    end

    def record_execution!(from_stage, to_stage, marketing_state_id, executed_at, status: "executed")
      event = events.first
      event.update!(details: event.details.merge(
        "auto_execution" => {
          "status" => status,
          "from_stage" => from_stage.upcase,
          "to_stage" => to_stage,
          "marketing_state_id" => marketing_state_id,
          "executed_at" => executed_at.iso8601,
          "executed_by_id" => submitted_by.id
        }
      ))
    end
  end
end
