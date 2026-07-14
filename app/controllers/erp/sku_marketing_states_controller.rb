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
      @marketing_state = Ec::SkuMarketingStateChange.new(
        sku: @sku,
        grade: marketing_state_params[:grade],
        stage: marketing_state_params[:stage],
        changed_by: current_user,
        note: marketing_state_params[:note]
      ).call

      redirect_to safe_return_to(erp_skus_path(current_locale_params)), notice: t("erp.sku_marketing_states.messages.saved")
    rescue ActiveRecord::RecordInvalid => error
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
  end
end
