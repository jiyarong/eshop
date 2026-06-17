require "test_helper"

module Erp
  class SkuProductsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @token = SecureRandom.hex(4).upcase
      @ozon_product_id = 80_000_000 + @token.hex % 9_000_000
      @wb_nm_id = 70_000_000 + @token.hex % 9_000_000
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
        ozon_product_id: @ozon_product_id,
        offer_id: "RAW-OZON-#{@token}",
        name: "可选 Ozon 平台商品 #{@token}",
        description_category_id: 12_345,
        type_id: 67_890,
        currency_code: "RUB",
        raw_json: { "sku" => 4_444_001 },
        synced_at: Time.zone.parse("2026-06-15 10:00:00")
      )
      @bound_raw_ozon_product = RawOzon::Product.create!(
        account: @ozon_account,
        ozon_product_id: @ozon_product_id + 1,
        offer_id: "BOUND-OZON-#{@token}",
        name: "已绑定 Ozon 平台商品 #{@token}",
        description_category_id: 12_345,
        type_id: 67_890,
        currency_code: "RUB",
        raw_json: { "sku" => 3_902_460_130 },
        synced_at: Time.zone.parse("2026-06-15 10:00:00")
      )
      @raw_ozon_attribute = RawOzon::ProductAttribute.create!(
        account: @ozon_account,
        ozon_product_id: @bound_raw_ozon_product.ozon_product_id,
        offer_id: @bound_raw_ozon_product.offer_id,
        barcode: "460000000001",
        product_attributes: [
          {
            "id" => 85,
            "name" => "Brand",
            "values" => [{ "dictionary_value_id" => 971_082_156, "value" => "Test Brand #{@token}" }]
          },
          {
            "id" => 1001,
            "name" => "Material",
            "values" => [{ "value" => "Steel" }, { "value" => "Glass" }]
          }
        ],
        complex_attributes: [
          {
            "id" => 2001,
            "name" => "Package",
            "values" => [{ "value" => "Box #{@token}" }]
          }
        ],
        raw_json: {},
        synced_at: Time.zone.parse("2026-06-15 10:05:00")
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
        nm_id: @wb_nm_id,
        vendor_code: "RAW-WB-#{@token}",
        brand: "WB Brand #{@token}",
        title: "可选 WB 平台商品 #{@token}",
        subject_name: "WB Subject #{@token}",
        wb_category: "WB Category #{@token}",
        synced_at: Time.zone.parse("2026-06-15 10:20:00")
      )
      @raw_wb_characteristic = RawWb::ProductCharacteristic.create!(
        product: @raw_wb_product,
        charc_id: 12,
        charc_name: "Color",
        value: ["black", "white"]
      )
      @binding = Ec::SkuProduct.create!(
        sku_code: @sku.sku_code,
        store: @store,
        product_id: @bound_raw_ozon_product.ozon_product_id.to_s,
        offer_id: @bound_raw_ozon_product.offer_id,
        platform_sku_id: "3902460130",
        product_name: @bound_raw_ozon_product.name
      )
    end

    teardown do
      Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuProduct)
      RawOzon::ProductAttribute.where(account_id: @ozon_account&.id).delete_all
      RawOzon::Product.where(account_id: @ozon_account&.id).delete_all
      RawWb::ProductCharacteristic.where(product_id: RawWb::Product.where(account_id: @wb_account&.id).select(:id)).delete_all
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
      assert_select "td", @bound_raw_ozon_product.ozon_product_id.to_s
      assert_select "td", "BOUND-OZON-#{@token}"
      assert_select "a[href=?]", "/erp/skus/#{@sku.id}/products/#{@binding.id}", @bound_raw_ozon_product.ozon_product_id.to_s
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
      assert_select "a[href=?]", "/erp/skus/#{@sku.id}/products/#{wb_binding.id}", "7777001"
    ensure
      wb_binding&.destroy
    end

    test "show renders ozon product attributes with the ozon template" do
      get "/erp/skus/#{@sku.id}/products/#{@binding.id}", headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "h1", "已绑定 Ozon 平台商品 #{@token}"
      assert_select "body", text: /Ozon 商品属性/
      assert_select "dt", "Description Category ID"
      assert_select "dd", "12345"
      assert_select "dt", "Type ID"
      assert_select "dd", "67890"
      assert_select "td", "Brand"
      assert_select "td", "Test Brand #{@token}"
      assert_select "td", "Material"
      assert_select "td", "Steel, Glass"
      assert_select "td", "Package"
      assert_select "td", "Box #{@token}"
      assert_select "body", text: /WB 商品属性/, count: 0
    end

    test "show renders wb product characteristics with the wb template" do
      wb_binding = Ec::SkuProduct.create!(
        sku_code: @sku.sku_code,
        store: @wb_store,
        product_id: @raw_wb_product.nm_id.to_s,
        offer_id: @raw_wb_product.vendor_code,
        product_name: @raw_wb_product.title
      )

      get "/erp/skus/#{@sku.id}/products/#{wb_binding.id}", headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "h1", "可选 WB 平台商品 #{@token}"
      assert_select "body", text: /WB 商品属性/
      assert_select "dt", "品牌"
      assert_select "dd", "WB Brand #{@token}"
      assert_select "dt", "WB 类别"
      assert_select "dd", "WB Category #{@token}"
      assert_select "dt", "Subject"
      assert_select "dd", "WB Subject #{@token}"
      assert_select "td", "Color"
      assert_select "td", "black, white"
      assert_select "body", text: /Ozon 商品属性/, count: 0
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
