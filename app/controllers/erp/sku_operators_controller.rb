module Erp
  class SkuOperatorsController < BaseController
    include ResponsibleUserFilterable

    before_action -> { require_permission!(:manage_skus) }
    before_action :set_sku
    before_action :load_operator_options, only: [:edit, :update]

    def edit
      @selected_operator_id = @sku.operator_assignment&.user_id
      render_modal_or_page(:edit, :edit)
    end

    def update
      selected_user_id = operator_user_id_param
      if selected_user_id.present?
        assignment = @sku.operator_assignment || @sku.build_operator_assignment
        assignment.update!(user_id: selected_user_id)
      else
        @sku.operator_assignment&.destroy!
      end

      redirect_to safe_return_to(erp_skus_path(current_locale_params)), notice: t("erp.skus.messages.operator_saved")
    end

    private

    def set_sku
      @sku = Ec::Sku.find(params[:sku_id])
    end

    def load_operator_options
      @operator_options = responsible_user_options
    end

    def operator_user_id_param
      user_id = Integer(params[:operator_user_id], exception: false)
      return unless user_id

      @operator_options.exists?(id: user_id) ? user_id : nil
    end
  end
end
