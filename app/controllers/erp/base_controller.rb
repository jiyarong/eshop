module Erp
  class BaseController < ApplicationController
    helper_method :erp_value, :current_locale_params, :ozon_product_edit_url, :wb_product_edit_url
    before_action -> { require_permission!(:view_erp) }

    private

    def render_modal_or_page(page_template = action_name, modal_template = :"#{action_name}_modal", status: :ok)
      if turbo_frame_request?
        render modal_template, status: status
      else
        render page_template, status: status
      end
    end

    def erp_value(value)
      return "-" if value.nil? || value == ""
      return format("%.2f", value) if value.is_a?(Float) || value.is_a?(BigDecimal)

      value
    end

    def current_locale_params
      params[:locale].present? ? { locale: params[:locale] } : {}
    end

    def ozon_product_edit_url(platform_sku_id)
      return if platform_sku_id.blank?

      "https://seller.ozon.ru/app/products/#{ERB::Util.url_encode(platform_sku_id.to_s)}/edit/general-info"
    end

    def wb_product_edit_url(platform_sku_id)
      return if platform_sku_id.blank?

      "https://seller.wildberries.ru/new-goods/card?nmID=#{ERB::Util.url_encode(platform_sku_id.to_s)}&type=EXIST_CARD"
    end
  end
end
