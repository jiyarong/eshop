module Erp
  class PlatformProductsController < BaseController
    before_action :set_store
    helper_method :sku_product_attribute_value

    def show
      @platform = params[:platform].presence_in(%w[ozon wb])
      return render_not_found unless @platform && @store.platform == @platform

      @product_id = params[:product_id].to_s
      @raw_product = raw_product
      return render_not_found unless @raw_product

      @raw_product_attribute = raw_product_attribute
    end

    private

    def set_store
      @store = Ec::Store.find_by(id: params[:store_id])
      render_not_found unless @store
    end

    def raw_product
      case @platform
      when "ozon"
        RawOzon::Product.find_by(account_id: @store.ozon_raw_account_id, ozon_product_id: @product_id)
      when "wb"
        RawWb::Product.includes(:subject, :product_characteristics).find_by(account_id: @store.wb_raw_account_id, nm_id: @product_id)
      end
    end

    def raw_product_attribute
      return unless @platform == "ozon"

      RawOzon::ProductAttribute.find_by(account_id: @store.ozon_raw_account_id, ozon_product_id: @product_id)
    end

    def sku_product_attribute_value(value)
      case value
      when Array
        value.map { |item| sku_product_attribute_value(item) }.reject(&:blank?).join(", ")
      when Hash
        value["value"].presence || value["name"].presence || value.to_json
      else
        erp_value(value)
      end
    end

    def render_not_found
      render plain: "Not Found", status: :not_found
    end
  end
end
