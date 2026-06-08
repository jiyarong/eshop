module Erp
  class MasterSkusController < BaseController
    before_action -> { require_permission!(:manage_skus) }

    def new
      @master_sku = Ec::MasterSku.new(is_active: true)
      render_modal_or_page(:new, :new_modal)
    end

    def create
      @master_sku = Ec::MasterSku.new(master_sku_params)
      if @master_sku.save
        redirect_to erp_skus_path
      else
        render_modal_or_page(:new, :new_modal, status: :unprocessable_entity)
      end
    end

    private

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
