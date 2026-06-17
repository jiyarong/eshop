module Erp
  class SkuProductsController < BaseController
    before_action :set_sku
    before_action -> { require_permission!(:manage_skus) }, only: [:create, :destroy]

    def index
      load_page_data
      @sku_product = @sku.sku_products.new
    end

    def create
      @sku_products = sku_product_attributes_from_raw_products.map { |attributes| @sku.sku_products.new(attributes) }
      @sku_products.reject! { |product| product.store_id && product.product_id && Ec::SkuProduct.exists?(store_id: product.store_id, product_id: product.product_id) }

      if @sku_products.all?(&:save)
        redirect_to erp_sku_sku_products_path(@sku)
      else
        @sku_product = @sku_products.find { |product| product.errors.any? } || @sku.sku_products.new
        load_page_data
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @sku.sku_products.find(params[:id]).destroy!
      redirect_to erp_sku_sku_products_path(@sku)
    end

    private

    def set_sku
      @sku = Ec::Sku.find(params[:sku_id])
    end

    def load_page_data
      @raw_product_query = params[:raw_product_query].to_s.strip
      @raw_product_platform = params[:raw_product_platform].presence_in(%w[ozon wb])
      @available_only = params[:available_only].to_s == "1"
      @stores = Ec::Store.active.order(:platform, :store_name)
      @sku_products = @sku.sku_products.includes(:store).ordered
      @raw_product_options = raw_product_options
    end

    def sku_product_attributes_from_raw_products
      Array(params[:raw_product_keys]).filter_map { |raw_product_key| sku_product_attributes_from_raw_product(raw_product_key) }
    end

    def sku_product_attributes_from_raw_product(raw_product_key)
      platform, store_id, product_id = raw_product_key.to_s.split(":", 3)
      store = Ec::Store.find_by(id: store_id)
      return unless store && platform == store.platform

      case platform
      when "ozon"
        ozon_product_attributes(store, product_id)
      when "wb"
        wb_product_attributes(store, product_id)
      else
        {}
      end
    end

    def ozon_product_attributes(store, product_id)
      product = RawOzon::Product.find_by(account_id: store.ozon_raw_account_id, ozon_product_id: product_id)
      return {} unless product

      {
        store: store,
        product_id: product.ozon_product_id.to_s,
        offer_id: product.offer_id,
        platform_sku_id: product.raw_json&.dig("sku").to_s.presence,
        product_name: product.name
      }
    end

    def wb_product_attributes(store, product_id)
      product = RawWb::Product.find_by(account_id: store.wb_raw_account_id, nm_id: product_id)
      return {} unless product

      {
        store: store,
        product_id: product.nm_id.to_s,
        offer_id: product.vendor_code,
        product_name: product.title
      }
    end

    def raw_product_options
      @stores.flat_map do |store|
        next [] if @raw_product_platform.present? && store.platform != @raw_product_platform

        case store.platform
        when "ozon"
          ozon_product_options(store)
        when "wb"
          wb_product_options(store)
        else
          []
        end
      end.reject { |product| @available_only && product[:bound] }
    end

    def ozon_product_options(store)
      return [] if store.ozon_raw_account_id.blank?

      RawOzon::Product
        .where(account_id: store.ozon_raw_account_id)
        .order(:offer_id, :ozon_product_id)
        .then { |scope| filter_ozon_products(scope, store) }
        .map do |product|
          raw_product_option_hash(
            key: "ozon:#{store.id}:#{product.ozon_product_id}",
            store: store,
            product_id: product.ozon_product_id,
            offer_id: product.offer_id,
            platform_sku_id: product.raw_json&.dig("sku"),
            product_name: product.name
          )
        end
    end

    def wb_product_options(store)
      return [] if store.wb_raw_account_id.blank?

      RawWb::Product
        .where(account_id: store.wb_raw_account_id)
        .order(:vendor_code, :nm_id)
        .then { |scope| filter_wb_products(scope, store) }
        .map do |product|
          raw_product_option_hash(
            key: "wb:#{store.id}:#{product.nm_id}",
            store: store,
            product_id: product.nm_id,
            offer_id: product.vendor_code,
            platform_sku_id: nil,
            product_name: product.title
          )
        end
    end

    def raw_product_option_hash(key:, store:, product_id:, offer_id:, platform_sku_id:, product_name:)
      {
        key: key,
        platform: store.platform,
        store_id: store.id,
        store_name: store.store_name,
        product_id: product_id,
        offer_id: offer_id,
        platform_sku_id: platform_sku_id,
        product_name: product_name,
        bound: Ec::SkuProduct.exists?(store: store, product_id: product_id.to_s)
      }
    end

    def filter_ozon_products(scope, store)
      return scope if @raw_product_query.blank?

      keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@raw_product_query)}%"
      return scope.where("1=1") if store.store_name.to_s.match?(/#{Regexp.escape(@raw_product_query)}/i)

      scope.where(
        "ozon_product_id::text ILIKE :keyword OR offer_id ILIKE :keyword OR name ILIKE :keyword OR raw_json ->> 'sku' ILIKE :keyword",
        keyword: keyword
      )
    end

    def filter_wb_products(scope, store)
      return scope if @raw_product_query.blank?

      keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@raw_product_query)}%"
      return scope.where("1=1") if store.store_name.to_s.match?(/#{Regexp.escape(@raw_product_query)}/i)

      scope.where(
        "nm_id::text ILIKE :keyword OR vendor_code ILIKE :keyword OR title ILIKE :keyword",
        keyword: keyword
      )
    end
  end
end
