module Ec
  class SkuMarketingStateChange
    def initialize(sku:, grade:, stage:, changed_by:, note: nil)
      @sku = sku
      @grade = grade
      @stage = stage
      @changed_by = changed_by
      @note = note
    end

    def call
      sku.with_lock do
        current_state = Ec::SkuMarketingState.current.find_by(sku_id: sku.id)
        next current_state if unchanged?(current_state)

        changed_at = Time.current
        new_state = sku.marketing_states.build(
          grade: grade,
          stage: stage,
          effective_at: changed_at,
          changed_by: changed_by,
          note: note
        )
        new_state.validate!
        current_state&.update!(ended_at: changed_at)
        new_state.save!
        new_state
      end
    end

    private

    attr_reader :sku, :grade, :stage, :changed_by, :note

    def unchanged?(current_state)
      current_state.present? && current_state.grade == grade.to_s.upcase && current_state.stage == stage.to_s.downcase
    end
  end
end
