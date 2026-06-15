require "test_helper"

module Ec
  class SkuProductTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4).upcase
      @sku = Ec::Sku.create!(sku_code: "BIND-#{@token}", product_name: "绑定测试 SKU")
      @store = Ec::Store.create!(
        platform: "ozon",
        store_name: "绑定测试店 #{@token}",
        company_type: "general"
      )
    end

    teardown do
      Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuProduct)
      @store&.destroy
      @sku&.destroy
    end

    test "binds one store product to one erp sku" do
      binding = Ec::SkuProduct.create!(
        sku_code: @sku.sku_code,
        store: @store,
        product_id: "9876543210",
        offer_id: "PLATFORM-OFFER",
        platform_sku_id: "3902460130",
        product_name: "平台商品"
      )

      assert_equal "ozon", binding.platform
      assert_equal @sku, binding.sku
      assert_equal @store, binding.store
    end

    test "requires unique product id inside a store" do
      Ec::SkuProduct.create!(
        sku_code: @sku.sku_code,
        store: @store,
        product_id: "9876543210"
      )

      duplicate = Ec::SkuProduct.new(
        sku_code: @sku.sku_code,
        store: @store,
        product_id: "9876543210"
      )

      assert_not duplicate.valid?
      assert duplicate.errors[:product_id].any?
    end
  end
end
