module Ec
  class GradeInspect < AIDiagnosis
    GRADE_RANK = Ec::SkuMarketingState::GRADES.each_with_index.to_h.freeze
    UPGRADE_EVENT_TYPE = "grade_upgrade_candidate".freeze

    def process_persisted_events!
      upgrade_events = events.select { |event| event.event_type == UPGRADE_EVENT_TYPE }
      return self if upgrade_events.empty?
      raise ArgumentError, "only one grade upgrade event is allowed" unless upgrade_events.one?

      sku.lock!
      event = upgrade_events.first
      current_state = sku.marketing_states.current.lock.take
      raise ArgumentError, "current marketing grade is required for automatic upgrade" unless current_state

      target_grade = event.details["candidate_grade"].to_s.upcase.presence
      unless higher_grade?(target_grade, current_state.grade)
        raise ArgumentError, "grade upgrade candidate must target a higher grade"
      end

      diagnosed_grade = data["current_grade"].to_s.upcase.presence
      if diagnosed_grade.present? && diagnosed_grade != current_state.grade
        raise ArgumentError, "diagnosis current grade is stale"
      end

      apply_upgrade!(event, current_state, target_grade)
      self
    end

    private

    def higher_grade?(target_grade, current_grade)
      GRADE_RANK.key?(target_grade) && GRADE_RANK.fetch(target_grade) < GRADE_RANK.fetch(current_grade)
    end

    def apply_upgrade!(event, current_state, target_grade)
      executed_at = Time.current
      current_state.update!(ended_at: executed_at)
      new_state = sku.marketing_states.create!(
        grade: target_grade,
        stage: current_state.stage,
        effective_at: executed_at,
        changed_by: submitted_by,
        note: "Automatically upgraded by GradeInspect ##{id} event ##{event.id}"
      )
      event.update!(details: event.details.merge(
        "auto_execution" => {
          "status" => "executed",
          "from_grade" => current_state.grade,
          "to_grade" => target_grade,
          "marketing_state_id" => new_state.id,
          "executed_at" => executed_at.iso8601,
          "executed_by_id" => submitted_by.id
        }
      ))
    end
  end
end
