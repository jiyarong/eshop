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

    def developer_ids
      Array(params[:developer_ids]).reject(&:blank?)
    end

    def operator_candidates
      User.where(active: true)
    end

    def update_role_assignments
      selected_developer_ids = operator_candidates.where(id: developer_ids).pluck(:id)
      update_developer_assignments(selected_developer_ids)
    end

    def update_developer_assignments(selected_developer_ids)
      assignments = @sku_product.sku.developer_assignments
      selected_developer_ids.empty? ? assignments.delete_all : assignments.where.not(user_id: selected_developer_ids).delete_all

      selected_developer_ids.each { |user_id| upsert_developer_assignment(user_id) }
    end

    def upsert_developer_assignment(user_id)
      assignment = @sku_product.sku.developer_assignments.find_or_initialize_by(user_id: user_id)
      assignment.save!
    end
  end
end
