module Erp
  class SkuMarketingStatesController < BaseController
    before_action :set_sku
    before_action -> { require_permission!(:manage_skus) }, only: [ :new, :create ]

    def index
      load_history
    end

    def new
      current_state = @sku.current_marketing_state
      @marketing_state = @sku.marketing_states.build(
        grade: current_state&.grade,
        stage: current_state&.stage
      )
      load_history
      render_modal_or_page(:new, :new_modal)
    end

    def create
      attributes = marketing_state_params
      @sku.with_lock do
        previous_state = Ec::SkuMarketingState.current.find_by(sku_id: @sku.id)
        @marketing_state = Ec::SkuMarketingStateChange.new(
          sku: @sku,
          grade: attributes[:grade],
          stage: attributes[:stage],
          changed_by: current_user,
          note: attributes[:note]
        ).call
        record_operation(previous_state, @marketing_state, attributes[:note]) if previous_state&.id != @marketing_state.id
      end

      redirect_to safe_return_to(erp_skus_path(current_locale_params)), notice: t("erp.sku_marketing_states.messages.saved")
    rescue ActiveRecord::RecordInvalid => error
      raise unless error.record.is_a?(Ec::SkuMarketingState)

      @marketing_state = error.record
      load_history
      render_modal_or_page(:new, :new_modal, status: :unprocessable_entity)
    end

    private

    def set_sku
      @sku = Ec::Sku.find(params[:sku_id])
    end

    def load_history
      @marketing_states = @sku.marketing_states.includes(:changed_by).recent_first
    end

    def marketing_state_params
      params.require(:ec_sku_marketing_state).permit(:grade, :stage, :note)
    end

    def record_operation(previous_state, new_state, note)
      sku_product = @sku.sku_products.includes(:store).order(:id).first
      return unless sku_product

      description = t(
        "erp.sku_marketing_states.operation_record.change",
        grade_from: previous_state&.grade || "-", grade_to: new_state.grade,
        stage_from: previous_state&.stage&.upcase || "-", stage_to: new_state.stage.upcase
      )
      description += "\n#{t('erp.sku_marketing_states.operation_record.reason', reason: note)}" if note.present?

      Ec::OperationAction.create!(
        operation_type: "manual_note",
        operated_by_user: current_user,
        operated_at: new_state.effective_at,
        sku_product: sku_product,
        sku: @sku,
        store: sku_product.store,
        diff_result: { "note" => description },
        record_by_system: false
      )
    end
  end
end
