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
      Ec::AISuggestion.where(
        suggestable_type: "Ec::SkuProduct",
        suggestable_id: Ec::SkuProduct.where(sku_code: @sku&.sku_code).select(:id)
      ).destroy_all
      Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuProduct)
      RawOzon::ProductAttribute.where(account_id: @ozon_account&.id).delete_all
      RawOzon::Product.where(account_id: @ozon_account&.id).delete_all
      RawWb::ProductCharacteristic.where(product_id: RawWb::Product.where(account_id: @wb_account&.id).select(:id)).delete_all
      RawWb::Product.where(account_id: @wb_account&.id).delete_all
      @ozon_account&.destroy
      @wb_store&.destroy
      @wb_account&.destroy
      @store&.destroy
      Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
      UserRole.joins(:user).where("users.email LIKE ?", "sku-products-#{@token.downcase}%").delete_all
      User.where("email LIKE ?", "sku-products-#{@token.downcase}%").delete_all
    end

    test "index renders product bindings for erp sku" do
      get "/erp/skus/#{@sku.id}/products", headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "h1", "平台商品绑定"
      assert_select "th", "商品属性"
      assert_select "th", "店铺链接"
      assert_select "td", @sku.sku_code
      assert_select "td", "绑定页面 Ozon 店 #{@token}"
      assert_select "td", @bound_raw_ozon_product.ozon_product_id.to_s
      assert_select "td", "BOUND-OZON-#{@token}"
      assert_select "a[href=?][data-turbo-frame=?]", "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}", "_top", "查看属性"
      assert_select "a[href=?][target=?]", "https://seller.ozon.ru/app/products/3902460130/edit/general-info", "_blank"
      assert_select "form[action=?][method=?]", "/erp/skus/#{@sku.id}/products", "post"
      assert_select "select[name=?]", "raw_product_platform"
      assert_select "select[name=?] option[value='available'][selected]", "binding_status"
      assert_select "table.raw-product-options"
      assert_select "table.raw-product-options th", "商品属性"
      assert_select "table.raw-product-options th", "店铺链接"
      assert_select "input[type=?][name=?][value=?]", "checkbox", "raw_product_keys[]", "ozon:#{@store.id}:#{@raw_ozon_product.ozon_product_id}"
      assert_select "table.raw-product-options a[href=?]",
                    "/erp/platform_products/ozon/#{@store.id}/#{@raw_ozon_product.ozon_product_id}",
                    "查看属性"
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
      assert_select "a[href=?][data-turbo-frame=?]", "/erp/platform_products/wb/#{@wb_store.id}/7777001", "_top", "查看属性"
      assert_select "a[href=?][target=?]", "https://seller.wildberries.ru/new-goods/card?nmID=7777001&type=EXIST_CARD", "_blank"
    ensure
      wb_binding&.destroy
    end

    test "platform product show renders unbound ozon product attributes with the ozon template" do
      RawOzon::ProductAttribute.create!(
        account: @ozon_account,
        ozon_product_id: @raw_ozon_product.ozon_product_id,
        offer_id: @raw_ozon_product.offer_id,
        product_attributes: [
          {
            "id" => 85,
            "name" => "Brand",
            "values" => [{ "value" => "Unbound Brand #{@token}" }]
          }
        ],
        complex_attributes: [],
        raw_json: {},
        synced_at: Time.zone.parse("2026-06-15 10:05:00")
      )

      get "/erp/platform_products/ozon/#{@store.id}/#{@raw_ozon_product.ozon_product_id}", headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "h1", "可选 Ozon 平台商品 #{@token}"
      assert_select "body", text: /Ozon 商品属性/
      assert_select "dt", "Description Category ID"
      assert_select "dd", "12345"
      assert_select "dt", "Type ID"
      assert_select "dd", "67890"
      assert_select "td", "Brand"
      assert_select "td", "Unbound Brand #{@token}"
      assert_select "body", text: /WB 商品属性/, count: 0
      assert_select ".listing-diagnoses-panel", text: /尚未绑定 SKU/
      assert_select "form[action*='listing_diagnoses']", count: 0
    end

    test "bound platform product renders listing diagnosis action and history" do
      suggestion = @binding.ai_suggestions.create!(
        suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
        submitted_by: @current_user,
        status: :completed,
        content: "## 诊断结论\n\n需要优化标题。",
        started_at: 2.minutes.ago,
        completed_at: 1.minute.ago
      )

      get "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}",
        headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "h2", "Listing AI 诊断"
      assert_select "form[action=?]",
        "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}/listing_diagnoses.turbo_stream"
      assert_select ".listing-diagnosis-status--completed", "已完成"
      assert_select "a[href=?]",
        "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}/listing_diagnoses/#{suggestion.id}",
        "查看详情"
    end

    test "starting a listing diagnosis returns immediately and enqueues the job" do
      assert_enqueued_jobs 1, only: AITasks::ListingDiagnosisJob do
        assert_difference -> { @binding.ai_suggestions.count }, 1 do
          post "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}/listing_diagnoses.turbo_stream"
        end
      end

      assert_response :accepted
      suggestion = @binding.ai_suggestions.recent_first.first
      assert suggestion.pending?
      assert_equal Ec::AISuggestion::LISTING_AUDIT_TYPE, suggestion.suggestion_type
      assert_select "turbo-stream[action='replace'][target=?]", "listing_diagnoses_ec_sku_product_#{@binding.id}"
      assert_select ".listing-diagnosis-status--pending", "等待诊断"
      assert_select "[data-controller='listing-diagnosis-status']"
    end

    test "listing diagnosis status endpoint refreshes the history panel" do
      @binding.ai_suggestions.create!(
        suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
        submitted_by: @current_user
      )

      get "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}/listing_diagnoses.turbo_stream"
      assert_response :success
      assert_select "turbo-stream[action='replace'][target=?]", "listing_diagnoses_ec_sku_product_#{@binding.id}"
    end

    test "does not enqueue a second active listing diagnosis" do
      @binding.ai_suggestions.create!(
        suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
        submitted_by: @current_user
      )

      assert_no_enqueued_jobs only: AITasks::ListingDiagnosisJob do
        assert_no_difference -> { @binding.ai_suggestions.count } do
          post "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}/listing_diagnoses.turbo_stream"
        end
      end

      assert_response :accepted
      assert_select ".listing-diagnosis-status--pending", "等待诊断"
    end

    test "listing diagnosis detail renders a completed markdown result" do
      suggestion = @binding.ai_suggestions.create!(
        suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
        submitted_by: @current_user,
        status: :completed,
        content: "## 诊断结论\n\n需要优化标题。",
        completed_at: Time.current
      )

      get "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}/listing_diagnoses/#{suggestion.id}",
        headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "h1", "Listing AI 诊断详情"
      assert_select "[data-controller='markdown']"
      assert_select "pre", text: /需要优化标题/
      assert_select "a", text: "查看原始对话/继续诊断", count: 0
    end

    test "listing diagnosis detail links to its original conversation" do
      agent = Agent.create!(
        code: "listing-audit-#{@token.downcase}",
        name: "Listing Audit #{@token}",
        system_prompt: "Audit the supplied listing.",
        model_id: "fake-model",
        temperature: 0.2,
        tools: []
      )
      conversation = agent.conversations.create!(user: @current_user)
      suggestion = @binding.ai_suggestions.create!(
        suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
        submitted_by: @current_user,
        conversation: conversation,
        status: :completed,
        content: "## 诊断结论",
        completed_at: Time.current
      )

      get "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}/listing_diagnoses/#{suggestion.id}",
        headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "a.button[href=?]", "/ai/conversations/#{conversation.id}", "查看原始对话/继续诊断"
    ensure
      suggestion&.destroy!
      conversation&.destroy!
      agent&.destroy!
    end

    test "failed listing diagnosis detail renders retry and delete actions" do
      suggestion = @binding.ai_suggestions.create!(
        suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
        submitted_by: @current_user,
        status: :failed,
        error_message: "temporary failure",
        completed_at: Time.current
      )
      diagnosis_path = "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}/listing_diagnoses/#{suggestion.id}"

      get diagnosis_path, headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "form[action='#{diagnosis_path}/retry'] button", text: "重试"
      assert_select "form[action='#{diagnosis_path}'][data-turbo-confirm='确认删除这条 Listing 诊断记录？']" do
        assert_select "button.btn-danger", text: "删除记录"
      end
    end

    test "retrying a failed listing diagnosis resets and enqueues it" do
      suggestion = @binding.ai_suggestions.create!(
        suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
        submitted_by: @current_user,
        status: :failed,
        content: "stale content",
        error_message: "temporary failure",
        started_at: 2.minutes.ago,
        completed_at: 1.minute.ago
      )
      diagnosis_path = "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}/listing_diagnoses/#{suggestion.id}"

      assert_enqueued_jobs 1, only: AITasks::ListingDiagnosisJob do
        post "#{diagnosis_path}/retry"
      end

      assert_redirected_to diagnosis_path
      suggestion.reload
      assert suggestion.pending?
      assert_nil suggestion.content
      assert_nil suggestion.conversation_id
      assert_nil suggestion.error_message
      assert_nil suggestion.started_at
      assert_nil suggestion.completed_at
    end

    test "does not retry a listing diagnosis unless it failed" do
      suggestion = @binding.ai_suggestions.create!(
        suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
        submitted_by: @current_user,
        status: :completed,
        content: "done",
        completed_at: Time.current
      )
      diagnosis_path = "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}/listing_diagnoses/#{suggestion.id}"

      assert_no_enqueued_jobs only: AITasks::ListingDiagnosisJob do
        post "#{diagnosis_path}/retry"
      end

      assert_redirected_to diagnosis_path
      assert suggestion.reload.completed?
    end

    test "deletes a listing diagnosis record" do
      suggestion = @binding.ai_suggestions.create!(
        suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
        submitted_by: @current_user,
        status: :failed,
        error_message: "temporary failure",
        completed_at: Time.current
      )
      diagnosis_path = "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}/listing_diagnoses/#{suggestion.id}"

      assert_difference -> { @binding.ai_suggestions.count }, -1 do
        delete diagnosis_path
      end

      assert_redirected_to "/erp/platform_products/ozon/#{@store.id}/#{@bound_raw_ozon_product.ozon_product_id}#listing_diagnoses_ec_sku_product_#{@binding.id}"
    end

    test "platform product show renders unbound wb product characteristics with the wb template" do
      get "/erp/platform_products/wb/#{@wb_store.id}/#{@raw_wb_product.nm_id}", headers: { "Accept" => "text/html" }

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

    test "index filters raw product options by platform and binding status" do
      get "/erp/skus/#{@sku.id}/products",
          params: { raw_product_platform: "wb", binding_status: "available" },
          headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "select[name=?] option[value='wb'][selected]", "raw_product_platform"
      assert_select "select[name=?] option[value='available'][selected]", "binding_status"
      assert_select "input[type=?][name=?][value=?]", "checkbox", "raw_product_keys[]", "wb:#{@wb_store.id}:#{@raw_wb_product.nm_id}"
      assert_select "input[type=?][name=?][value=?]", "checkbox", "raw_product_keys[]", "ozon:#{@store.id}:#{@raw_ozon_product.ozon_product_id}", count: 0
      assert_select "table.raw-product-options td", { text: "OFFER-#{@token}", count: 0 }
    end

    test "index renders only the add binding panel in the erp modal" do
      get "/erp/skus/#{@sku.id}/products", headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

      assert_response :success
      assert_select "turbo-frame#erp_modal"
      assert_select ".sku-product-binding-modal[role='dialog']"
      assert_select "h2", "新增绑定"
      assert_select "h2", { text: "当前绑定", count: 0 }
      assert_select "select[name='binding_status'] option[value='available'][selected]"
    end

    test "index can show products that are already bound" do
      get "/erp/skus/#{@sku.id}/products",
          params: { binding_status: "bound" },
          headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "select[name='binding_status'] option[value='bound'][selected]"
      assert_select "td", "BOUND-OZON-#{@token}"
      assert_select "input[name='raw_product_keys[]']", count: 0
      assert_select "button", { text: "新增绑定", count: 0 }
    end

    test "index paginates platform products and preserves filters" do
      products = 21.times.map do |index|
        RawOzon::Product.create!(
          account: @ozon_account,
          ozon_product_id: 9_100_000 + index,
          offer_id: "PAGE-#{@token}-#{index.to_s.rjust(2, '0')}",
          name: "分页商品 #{index}",
          raw_json: {},
          synced_at: Time.zone.parse("2026-06-15 12:00:00")
        )
      end

      get "/erp/skus/#{@sku.id}/products",
          params: { raw_product_platform: "ozon", binding_status: "available" },
          headers: { "Accept" => "text/html" }

      assert_response :success
      assert_select "table.raw-product-options tbody tr", count: 10
      assert_select ".inventory-pagination-bar"
      assert_select ".inventory-pagination-bar__summary", text: /显示第 1-10 条/
      assert_select ".pagination-chip", text: /第 1\/3 页/
      assert_select ".pagination-nav a[href*='page=2'][href*='binding_status=available'][href*='raw_product_platform=ozon']"
      assert_select "form.pagination-jump input[name='jump_page'][value='1']"
    ensure
      products&.each(&:destroy)
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
