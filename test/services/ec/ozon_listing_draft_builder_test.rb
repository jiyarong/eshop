require "test_helper"

module Ec
  class OzonListingDraftBuilderTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(5).upcase
      @sku = Ec::Sku.create!(sku_code: "LISTING-#{@token}", product_name: "Widget", product_name_ru: "Виджет", weight_kg: 0.25)
      @account = RawOzon::SellerAccount.create!(client_id: "listing-#{@token}", api_key: "secret-#{@token}", company_type: "general")
      @store = Ec::Store.create!(platform: "ozon", store_name: "Ozon #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
      @dimension = Ec::SkuDimension.create!(sku_code: @sku.sku_code, outer_length_cm: 10, outer_width_cm: 5, outer_height_cm: 2, outer_box_weight_kg: 0.3)
    end

    teardown do
      Ec::OzonListingPublication.where(sku_code: @sku&.sku_code).delete_all
      Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
      Ec::SkuDimension.where(sku_code: @sku&.sku_code).delete_all
      Ec::Sku.where(id: @sku&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      RawOzon::ProductAttribute.where(account_id: @account&.id).delete_all
      RawOzon::Product.where(account_id: @account&.id).delete_all
      RawOzon::SellerAccount.where(id: @account&.id).delete_all
    end

    test "builds an account-scoped canonical payload from the SKU" do
      payload = Ec::OzonListingDraftBuilder.new(
        sku: @sku,
        store: @store,
        overrides: {
          description_category_id: 10,
          type_id: 20,
          images: ["https://cdn.example.test/widget.jpg"],
          price: { price: "99.00", currency_code: "RUB" }
        }
      ).call

      assert_equal @sku.sku_code, payload[:offer_id]
      assert_equal 10, payload.dig(:category, :description_category_id)
      assert_equal 100.0, payload.dig(:dimensions, :length).to_f
      assert_equal 300.0, payload[:weight].to_f
      assert_equal ["https://cdn.example.test/widget.jpg"], payload[:images]
      assert_nil payload[:api_key]
    end

    test "does not read another account's product attributes" do
      other = RawOzon::SellerAccount.create!(client_id: "other-#{@token}", api_key: "other-secret", company_type: "general")
      RawOzon::Product.create!(account: @account, ozon_product_id: 1001, offer_id: @sku.sku_code, name: "Current", raw_json: {})
      RawOzon::ProductAttribute.create!(account: other, ozon_product_id: 1001, product_attributes: [{ "id" => 1 }], raw_json: {})
      @store.sku_products.create!(sku: @sku, product_id: "1001", offer_id: @sku.sku_code)

      payload = Ec::OzonListingDraftBuilder.new(sku: @sku, store: @store).call
      assert_empty payload[:attributes]
    ensure
      RawOzon::ProductAttribute.where(account_id: other&.id).delete_all
      RawOzon::Product.where(account_id: other&.id).delete_all
      RawOzon::SellerAccount.where(id: other&.id).delete_all
    end
  end
end
