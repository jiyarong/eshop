module Erp
  class SkuDevelopersController < BaseController
    include ResponsibleUserFilterable

    before_action -> { require_permission!(:manage_skus) }
    before_action :set_sku
    before_action :load_developer_options, only: [:edit, :update]

    def edit
      @selected_developer_id = @sku.developer_ids.first
      render_modal_or_page(:edit, :edit)
    end

    def update
      selected_user_id = developer_user_id_param

      Ec::SkuDeveloperAssignment.transaction do
        assignments = @sku.developer_assignments
        selected_user_id.present? ? assignments.where.not(user_id: selected_user_id).delete_all : assignments.delete_all

        if selected_user_id.present?
          assignment = assignments.find_or_initialize_by(user_id: selected_user_id)
          assignment.save! if assignment.new_record?
        end
      end

      redirect_to safe_return_to(erp_skus_path(current_locale_params)), notice: t("erp.skus.messages.developer_saved")
    end

    private

    def set_sku
      @sku = Ec::Sku.find(params[:sku_id])
    end

    def load_developer_options
      @developer_options = responsible_user_options
    end

    def developer_user_id_param
      user_id = Integer(params[:developer_user_id], exception: false)
      return unless user_id

      @developer_options.exists?(id: user_id) ? user_id : nil
    end
  end
end
