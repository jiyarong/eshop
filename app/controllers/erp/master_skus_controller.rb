module Erp
  class MasterSkusController < BaseController
    before_action -> { require_permission!(:manage_skus) }
    before_action :set_master_sku, only: [:edit, :update]

    def new
      @master_sku = Ec::MasterSku.new(is_active: true)
      render_modal_or_page(:new, :new_modal)
    end

    def edit
      render_modal_or_page(:edit, :edit_modal)
    end

    def create
      @master_sku = Ec::MasterSku.new(master_sku_params)
      if @master_sku.save
        redirect_to erp_skus_path
      else
        render_modal_or_page(:new, :new_modal, status: :unprocessable_entity)
      end
    end

    def update
      if @master_sku.update(master_sku_params)
        redirect_to erp_skus_path
      else
        render_modal_or_page(:edit, :edit_modal, status: :unprocessable_entity)
      end
    end

    private

    def set_master_sku
      @master_sku = Ec::MasterSku.find(params[:id])
    end

    def master_sku_params
      params.require(:ec_master_sku).permit(
        :master_sku_code,
        :product_name,
        :product_name_ru,
        :is_active,
        :memo
      )
    end
  end
end
