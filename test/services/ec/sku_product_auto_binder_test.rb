require "test_helper"

module Ec
  class SkuProductAutoBinderTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4).upcase
      @ozon_sku = Ec::Sku.create!(sku_code: "OZON-BIND-#{@token}", product_name: "Ozon 绑定 SKU")
      @wb_sku = Ec::Sku.create!(sku_code: "WB-BIND-#{@token}", product_name: "WB 绑定 SKU")
      @ozon_account = RawOzon::SellerAccount.create!(
        company_name: "Auto Binder Ozon #{@token}",
        client_id: "auto-binder-ozon-#{@token}",
        api_key: "api-key-#{@token}",
        company_type: "general"
      )
      @wb_account = RawWb::SellerAccount.create!(
        name: "Auto Binder WB #{@token}",
        api_token: "auto-binder-wb-#{@token}",
        company_type: "small"
      )
      @ozon_store = Ec::Store.create!(
        platform: "ozon",
        store_name: "Auto Binder Ozon Store #{@token}",
        company_type: "general",
        ozon_raw_account_id: @ozon_account.id
      )
      @wb_store = Ec::Store.create!(
        platform: "wb",
        store_name: "Auto Binder WB Store #{@token}",
        company_type: "small",
        wb_raw_account_id: @wb_account.id
      )
      @ozon_product = RawOzon::Product.create!(
        account: @ozon_account,
        ozon_product_id: "98#{@token.hex % 1_000_000}",
        offer_id: @ozon_sku.sku_code,
        name: "Ozon 平台商品",
        raw_json: { "sku" => "OZON-PLATFORM-#{@token}" },
        synced_at: Time.zone.parse("2026-06-15 10:00:00")
      )
      @wb_product = RawWb::Product.create!(
        account: @wb_account,
        nm_id: "87#{@token.hex % 1_000_000}",
        vendor_code: @wb_sku.sku_code,
        title: "WB 平台商品",
        synced_at: Time.zone.parse("2026-06-15 10:00:00")
      )
    end

    teardown do
      Ec::SkuProduct.where(sku_code: [@ozon_sku&.sku_code, @wb_sku&.sku_code]).delete_all if defined?(Ec::SkuProduct)
      @ozon_product&.destroy
      @wb_product&.destroy
      @ozon_store&.destroy
      @wb_store&.destroy
      @ozon_account&.destroy
      @wb_account&.destroy
      Ec::Sku.with_deleted.where(id: [@ozon_sku&.id, @wb_sku&.id].compact).delete_all
    end

    test "binds raw products whose sku code matches an erp sku" do
      assert_difference "Ec::SkuProduct.count", 2 do
        result = Ec::SkuProductAutoBinder.call

        assert_equal 2, result.created_count
        assert_equal 0, result.skipped_count
      end

      ozon_binding = Ec::SkuProduct.find_by!(store: @ozon_store, product_id: @ozon_product.ozon_product_id.to_s)
      assert_equal @ozon_sku.sku_code, ozon_binding.sku_code
      assert_equal "ozon", ozon_binding.platform
      assert_equal @ozon_sku.sku_code, ozon_binding.offer_id
      assert_equal "OZON-PLATFORM-#{@token}", ozon_binding.platform_sku_id
      assert_equal "Ozon 平台商品", ozon_binding.product_name

      wb_binding = Ec::SkuProduct.find_by!(store: @wb_store, product_id: @wb_product.nm_id.to_s)
      assert_equal @wb_sku.sku_code, wb_binding.sku_code
      assert_equal "wb", wb_binding.platform
      assert_equal @wb_sku.sku_code, wb_binding.offer_id
      assert_nil wb_binding.platform_sku_id
      assert_equal "WB 平台商品", wb_binding.product_name
    end

    test "skips products that are already bound" do
      Ec::SkuProduct.create!(
        sku_code: @ozon_sku.sku_code,
        store: @ozon_store,
        product_id: @ozon_product.ozon_product_id.to_s
      )

      assert_difference "Ec::SkuProduct.count", 1 do
        result = Ec::SkuProductAutoBinder.call

        assert_equal 1, result.created_count
        assert_equal 1, result.skipped_count
      end
    end
  end
end
