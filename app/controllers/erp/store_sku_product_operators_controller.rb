module Erp
  class StoreSkuProductOperatorsController < BaseController
    before_action -> { require_permission!(:manage_skus) }
    before_action :set_store
    before_action :set_sku_product

    def update
      return unless @sku_product

      update_role_assignments
      redirect_to erp_store_path(@store)
    end

    private

    def set_store
      @store = Ec::Store.find(params[:store_id])
    end

    def set_sku_product
      @sku_product = @store.sku_products.find_by(id: params[:id])
      render plain: "Not Found", status: :not_found unless @sku_product
    end

    def operator_ids
      Array(params[:operator_ids]).reject(&:blank?)
    end

    def developer_ids
      Array(params[:developer_ids]).reject(&:blank?)
    end

    def operator_candidates
      User.where(active: true)
    end

    def update_role_assignments
      selected_operator_ids = operator_candidates.where(id: operator_ids).pluck(:id)
      selected_developer_ids = operator_candidates.where(id: developer_ids).pluck(:id) - selected_operator_ids
      selected_user_ids = selected_operator_ids + selected_developer_ids

      @sku_product.operator_assignments.transaction do
        assignments = @sku_product.operator_assignments
        selected_user_ids.empty? ? assignments.delete_all : assignments.where.not(user_id: selected_user_ids).delete_all

        selected_developer_ids.each { |user_id| upsert_assignment(user_id, "developer") }
        selected_operator_ids.each { |user_id| upsert_assignment(user_id, "operator") }
      end
    end

    def upsert_assignment(user_id, role)
      assignment = @sku_product.operator_assignments.find_or_initialize_by(user_id: user_id)
      assignment.role = role
      assignment.save!
    end
  end
end
