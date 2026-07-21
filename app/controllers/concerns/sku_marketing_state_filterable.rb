module SkuMarketingStateFilterable
  extend ActiveSupport::Concern

  private

  def load_sku_marketing_state_filters
    @grades = selected_marketing_grades
    @stages = selected_marketing_stages
  end

  def apply_marketing_state_filters(scope)
    return scope unless sku_marketing_state_filters_active?

    scope = scope.joins(:current_marketing_state)
    scope = scope.where(ec_sku_marketing_states: { grade: @grades }) if @grades.present?
    scope = scope.where(ec_sku_marketing_states: { stage: @stages }) if @stages.present?
    scope
  end

  def sku_marketing_state_filters_active?
    @grades.present? || @stages.present?
  end

  def selected_marketing_grades
    Array(params[:grades].presence || params[:grade])
      .reject(&:blank?)
      .map { |value| value.to_s.upcase }
      .select { |value| Ec::SkuMarketingState::GRADES.include?(value) }
      .uniq
  end

  def selected_marketing_stages
    Array(params[:stages].presence || params[:stage])
      .reject(&:blank?)
      .map { |value| value.to_s.downcase }
      .select { |value| Ec::SkuMarketingState::STAGES.include?(value) }
      .uniq
  end
end
