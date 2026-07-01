module Erp
  class StoreSkuProductOperatorsController < BaseController
    before_action -> { require_permission!(:manage_skus) }
    before_action :set_store
    before_action :set_sku_product

    def update
      return unless @sku_product

      @sku_product.operators = operator_candidates.where(id: operator_ids)
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

    def operator_candidates
      User.where(active: true)
    end
  end
end
