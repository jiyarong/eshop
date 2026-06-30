module Ec
  class UnboundRawProductReport
    Row = Data.define(
      :platform,
      :store_id,
      :store_name,
      :account_id,
      :account_name,
      :product_id,
      :offer_id,
      :platform_sku_id,
      :product_name,
      :synced_at
    )

    def self.call(store_id: nil)
      new(store_id: store_id).call
    end

    def initialize(store_id: nil)
      @store_id = store_id
    end

    def call
      ozon_rows + wb_rows
    end

    private

    def ozon_rows
      RawOzon::Product
        .joins("JOIN ec_stores ON ec_stores.platform = 'ozon' AND ec_stores.ozon_raw_account_id = raw_ozon_products.account_id")
        .joins("LEFT JOIN ec_sku_products ON ec_sku_products.store_id = ec_stores.id AND ec_sku_products.product_id = raw_ozon_products.ozon_product_id::text")
        .joins("LEFT JOIN raw_ozon_seller_accounts ON raw_ozon_seller_accounts.id = raw_ozon_products.account_id")
        .then { |scope| @store_id ? scope.where(ec_stores: { id: @store_id }) : scope }
        .where(ec_sku_products: { id: nil })
        .order("ec_stores.store_name", "raw_ozon_products.offer_id", "raw_ozon_products.ozon_product_id")
        .pluck(
          "ec_stores.id",
          "ec_stores.store_name",
          "raw_ozon_products.account_id",
          "raw_ozon_seller_accounts.company_name",
          "raw_ozon_products.ozon_product_id",
          "raw_ozon_products.offer_id",
          Arel.sql("raw_ozon_products.raw_json ->> 'sku'"),
          "raw_ozon_products.name",
          "raw_ozon_products.synced_at"
        )
        .map do |store_id, store_name, account_id, account_name, product_id, offer_id, platform_sku_id, product_name, synced_at|
          Row.new(
            platform: "ozon",
            store_id: store_id,
            store_name: store_name,
            account_id: account_id,
            account_name: account_name,
            product_id: product_id,
            offer_id: offer_id,
            platform_sku_id: platform_sku_id,
            product_name: product_name,
            synced_at: synced_at
          )
        end
    end

    def wb_rows
      RawWb::Product
        .joins("JOIN ec_stores ON ec_stores.platform = 'wb' AND ec_stores.wb_raw_account_id = raw_wb_products.account_id")
        .joins("LEFT JOIN ec_sku_products ON ec_sku_products.store_id = ec_stores.id AND ec_sku_products.product_id = raw_wb_products.nm_id::text")
        .joins("LEFT JOIN raw_wb_seller_accounts ON raw_wb_seller_accounts.id = raw_wb_products.account_id")
        .then { |scope| @store_id ? scope.where(ec_stores: { id: @store_id }) : scope }
        .where(ec_sku_products: { id: nil })
        .order("ec_stores.store_name", "raw_wb_products.vendor_code", "raw_wb_products.nm_id")
        .pluck(
          "ec_stores.id",
          "ec_stores.store_name",
          "raw_wb_products.account_id",
          "raw_wb_seller_accounts.name",
          "raw_wb_products.nm_id",
          "raw_wb_products.vendor_code",
          "raw_wb_products.title",
          "raw_wb_products.synced_at"
        )
        .map do |store_id, store_name, account_id, account_name, product_id, offer_id, product_name, synced_at|
          Row.new(
            platform: "wb",
            store_id: store_id,
            store_name: store_name,
            account_id: account_id,
            account_name: account_name,
            product_id: product_id,
            offer_id: offer_id,
            platform_sku_id: nil,
            product_name: product_name,
            synced_at: synced_at
          )
        end
    end
  end
end
