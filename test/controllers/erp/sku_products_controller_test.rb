require "test_helper"

module Erp
  class SkuProductsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @token = SecureRandom.hex(4).upcase
      @current_user = create_user_with_roles("sku-products-#{@token.downcase}@example.com", "manager")
      sign_in @current_user

      @sku = Ec::Sku.create!(
        sku_code: "ERP-BIND-#{@token}",
        product_name: "绑定页面 SKU",
        is_active: true
      )
      @ozon_account = RawOzon::SellerAccount.create!(
        client_id: "sku-products-ozon-#{@token}",
        api_key: "test-key",
        company_name: "绑定页面 Ozon Raw #{@token}",
        company_type: "general"
      )
      @store = Ec::Store.create!(
        platform: "ozon",
        store_name: "绑定页面 Ozon 店 #{@token}",
        company_type: "general",
        ozon_raw_account_id: @ozon_account.id
      )
      @raw_ozon_product = RawOzon::Product.create!(
        account: @ozon_account,
        ozon_product_id: 8_888_001,
        offer_id: "RAW-OZON-#{@token}",
        name: "可选 Ozon 平台商品 #{@token}",
        raw_json: { "sku" => 4_444_001 },
        synced_at: Time.zone.parse("2026-06-15 10:00:00")
      )
      @wb_account = RawWb::SellerAccount.create!(
        name: "绑定页面 WB Raw #{@token}",
        api_token: "wb-token-#{@token}",
        company_type: "small"
      )
      @wb_store = Ec::Store.create!(
        platform: "wb",
        store_name: "绑定页面 WB 店 #{@token}",
        company_type: "small",
        wb_raw_account_id: @wb_account.id
      )
      @raw_wb_product = RawWb::Product.create!(
        account: @wb_account,
        nm_id: 7_777_001,
        vendor_code: "RAW-WB-#{@token}",
        title: "可选 WB 平台商品 #{@token}",
        synced_at: Time.zone.parse("2026-06-15 10:20:00")
      )
      @binding = Ec::SkuProduct.create!(
        sku_code: @sku.sku_code,
        store: @store,
        product_id: "9876543210",
        offer_id: "OFFER-#{@token}",
        platform_sku_id: "3902460130",
        product_name: "已绑定平台商品"
      )
    end

    teardown do
      Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuProduct)
      RawOzon::Product.where(account_id: @ozon_account&.id).delete_all
      RawWb::Product.where(account_id: @wb_account&.id).delete_all
      @ozon_account&.destroy
      @wb_store&.destroy
      @wb_account&.destroy
      @store&.destroy
      @sku&.destroy
      UserRole.joins(:user).where("users.email LIKE ?", "sku-products-#{@token.downcase}%").delete_all
      User.where("email LIKE ?", "sku-products-#{@token.downcase}%").delete_all
    end

    test "index renders product bindings for erp sku" do
      get "/erp/skus/#{@sku.id}/products", headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "h1", "平台商品绑定"
      assert_select "td", @sku.sku_code
      assert_select "td", "绑定页面 Ozon 店 #{@token}"
      assert_select "td", "9876543210"
      assert_select "td", "OFFER-#{@token}"
      assert_select "a[href=?][target=?]",
                    "https://seller.ozon.ru/app/products/3902460130/edit/general-info",
                    "_blank"
      assert_select "form[action=?][method=?]", "/erp/skus/#{@sku.id}/products", "post"
      assert_select "select[name=?]", "raw_product_platform"
      assert_select "input[type=?][name=?]", "checkbox", "available_only"
      assert_select "table.raw-product-options"
      assert_select "input[type=?][name=?][value=?]", "checkbox", "raw_product_keys[]", "ozon:#{@store.id}:#{@raw_ozon_product.ozon_product_id}"
      assert_select "table.raw-product-options a[href=?][target=?]",
                    "https://seller.ozon.ru/app/products/4444001/edit/general-info",
                    "_blank"
      assert_select "td", "可选 Ozon 平台商品 #{@token}"
    end

    test "index renders wb product edit links with the shared platform helper" do
      wb_binding = Ec::SkuProduct.create!(
        sku_code: @sku.sku_code,
        store: @wb_store,
        product_id: "7777001",
        offer_id: "RAW-WB-#{@token}",
        product_name: "已绑定 WB 平台商品"
      )

      get "/erp/skus/#{@sku.id}/products", headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "a[href=?][target=?]",
                    "https://seller.wildberries.ru/new-goods/card?nmID=7777001&type=EXIST_CARD",
                    "_blank"
    ensure
      wb_binding&.destroy
    end

    test "index filters raw product options by search keyword" do
      hidden_product = RawOzon::Product.create!(
        account: @ozon_account,
        ozon_product_id: 8_888_002,
        offer_id: "HIDDEN-OZON-#{@token}",
        name: "不匹配的平台商品 #{@token}",
        raw_json: { "sku" => 4_444_002 },
        synced_at: Time.zone.parse("2026-06-15 10:10:00")
      )

      get "/erp/skus/#{@sku.id}/products",
          params: { raw_product_query: "RAW-OZON-#{@token}" },
          headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "input[name=?][value=?]", "raw_product_query", "RAW-OZON-#{@token}"
      assert_select "input[type=?][name=?][value=?]", "checkbox", "raw_product_keys[]", "ozon:#{@store.id}:#{@raw_ozon_product.ozon_product_id}"
      assert_select "input[type=?][name=?][value=?]", "checkbox", "raw_product_keys[]", "ozon:#{@store.id}:#{hidden_product.ozon_product_id}", count: 0
    ensure
      hidden_product&.destroy
    end

    test "index filters raw product options by platform and available checkbox" do
      get "/erp/skus/#{@sku.id}/products",
          params: { raw_product_platform: "wb", available_only: "1" },
          headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "select[name=?] option[value='wb'][selected]", "raw_product_platform"
      assert_select "input[type=?][name=?][checked]", "checkbox", "available_only"
      assert_select "input[type=?][name=?][value=?]", "checkbox", "raw_product_keys[]", "wb:#{@wb_store.id}:#{@raw_wb_product.nm_id}"
      assert_select "input[type=?][name=?][value=?]", "checkbox", "raw_product_keys[]", "ozon:#{@store.id}:#{@raw_ozon_product.ozon_product_id}", count: 0
      assert_select "table.raw-product-options td", { text: "OFFER-#{@token}", count: 0 }
    end

    test "creates product bindings from selected raw products under erp sku" do
      other_wb_account = RawWb::SellerAccount.create!(
        name: "绑定页面 WB Raw #{@token}",
        api_token: "wb-token-other-#{@token}",
        company_type: "small"
      )
      other_wb_store = Ec::Store.create!(
        platform: "wb",
        store_name: "绑定页面 WB 店 2 #{@token}",
        company_type: "small",
        wb_raw_account_id: other_wb_account.id
      )
      raw_product = RawWb::Product.create!(
        account: other_wb_account,
        nm_id: 123_456,
        vendor_code: "WB-OFFER-#{@token}",
        title: "新增 WB 商品",
        synced_at: Time.zone.parse("2026-06-15 11:00:00")
      )
      second_raw_product = RawWb::Product.create!(
        account: other_wb_account,
        nm_id: 123_457,
        vendor_code: "WB-OFFER-2-#{@token}",
        title: "第二个 WB 商品",
        synced_at: Time.zone.parse("2026-06-15 11:10:00")
      )

      assert_difference "Ec::SkuProduct.count", 2 do
        post "/erp/skus/#{@sku.id}/products", params: {
          raw_product_keys: [
            "wb:#{other_wb_store.id}:#{raw_product.nm_id}",
            "wb:#{other_wb_store.id}:#{second_raw_product.nm_id}"
          ]
        }
      end

      assert_redirected_to "/erp/skus/#{@sku.id}/products"
      binding = Ec::SkuProduct.find_by!(store_id: other_wb_store.id, product_id: "123456")
      assert_equal @sku.sku_code, binding.sku_code
      assert_equal "wb", binding.platform
      assert_equal "WB-OFFER-#{@token}", binding.offer_id
      assert_equal "新增 WB 商品", binding.product_name
      assert Ec::SkuProduct.find_by!(store_id: other_wb_store.id, product_id: "123457")
    ensure
      Ec::SkuProduct.where(store_id: other_wb_store&.id).delete_all if defined?(Ec::SkuProduct)
      raw_product&.destroy
      second_raw_product&.destroy
      other_wb_store&.destroy
      other_wb_account&.destroy
    end

    test "destroys product binding" do
      assert_difference "Ec::SkuProduct.count", -1 do
        delete "/erp/skus/#{@sku.id}/products/#{@binding.id}"
      end

      assert_redirected_to "/erp/skus/#{@sku.id}/products"
    end
  end
end
