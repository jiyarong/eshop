module Erp
  class SkuOperatorsController < BaseController
    include ResponsibleUserFilterable

    before_action -> { require_permission!(:manage_skus) }
    before_action :set_sku
    before_action :load_operator_options, only: [:edit, :update]

    def edit
      @operator_assignment_available = @sku.sku_products.exists?
      @selected_operator_id = @sku.sku_products.flat_map(&:operator_ids).first
      render_modal_or_page(:edit, :edit)
    end

    def update
      unless @sku.sku_products.exists?
        redirect_to safe_return_to(erp_skus_path(current_locale_params)), alert: t("erp.skus.messages.operator_requires_product_binding")
        return
      end

      selected_user_id = operator_user_id_param
      product_ids = @sku.sku_products.select(:id)
      operator_role = Ec::SkuProductOperator.roles.fetch("operator")

      Ec::SkuProductOperator.transaction do
        assignments = Ec::SkuProductOperator.where(sku_product_id: product_ids, role: operator_role)
        selected_user_id.present? ? assignments.where.not(user_id: selected_user_id).delete_all : assignments.delete_all

        if selected_user_id.present?
          @sku.sku_products.find_each do |product|
            assignment = product.operator_role_assignments.find_or_initialize_by(user_id: selected_user_id)
            assignment.role = operator_role
            assignment.save! if assignment.new_record? || assignment.changed?
          end
        end
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
