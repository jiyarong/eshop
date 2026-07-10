require "test_helper"

class Erp::StoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-stores-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "明斯克 Ozon 店 #{token_suffix}",
      company_type: "general",
      registration_country: "belarus",
      is_active: true
    )
  end

  teardown do
    Ec::Store.where("store_name LIKE ?", "%#{token_suffix}%").delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-stores-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-stores-#{@token.downcase}%").delete_all
  end

  test "index renders stores and static options" do
    get "/erp/stores", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "店铺设置"
    assert_select ".store-management"
    assert_select ".page-h"
    assert_select ".product-page-actions a", text: "新增店铺"
    assert_select ".card.product-filter-card form[action='/erp/stores'][method='get']"
    assert_select "input[name='q']"
    assert_select "select[name='platform'] option[value='ozon']", text: "Ozon"
    assert_select "select[name='platform'] option[value='wb']", text: "WB"
    assert_select "select[name='registration_country'] option[value='belarus']", text: "白俄罗斯"
    assert_select "select[name='registration_country'] option[value='russia']", text: "俄罗斯"
    assert_select "select[name='company_type'] option[value='small']", text: "小规模"
    assert_select "select[name='company_type'] option[value='general']", text: "普通"
    assert_select ".product-summary-card", 4
    assert_select ".prod-tbl thead th", text: "店铺 ID"
    assert_select ".prod-tbl thead th", text: "平台"
    assert_select ".prod-tbl thead th", text: "公司规模类型"
    assert_select ".prod-tbl thead th", text: "公司注册国"
    assert_select ".prod-tbl td .code-text", text: "SHOP-%03d" % @store.id
    assert_select ".prod-tbl td", text: @store.store_name
    assert_select ".badge.badge-pri", text: "OZON"
    assert_select ".badge.badge-suc", text: "已激活"
    assert_select "turbo-frame#erp_modal"
    assert_select "a[href='#{erp_new_store_path}'][data-turbo-frame='erp_modal']", text: "新增店铺"
    assert_select "a[href='#{erp_edit_store_path(@store)}'][data-turbo-frame='erp_modal']", text: "编辑"
  end

  test "index localizes visible chrome in english" do
    get "/erp/stores", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "Store Settings"
    assert_select ".product-page-actions a", text: "Add store"
    assert_select ".product-summary-grid[aria-label=?]", "Store overview"
    assert_select ".summary-label", "All stores"
    assert_select ".summary-label", "Active"
    assert_select "input[placeholder=?]", "Search store name or notes..."
    assert_select "label", "Platform"
    assert_select "option", "All platforms"
    assert_select "label", "Scale"
    assert_select "option", "Small"
    assert_select "option", "General"
    assert_select "label", "Country"
    assert_select "option", "Belarus"
    assert_select "option", "Russia"
    assert_select "label", "Status"
    assert_select "button", "Filter"
    assert_select "a", "Reset"
    assert_select ".prod-tbl thead th", text: "Store ID"
    assert_select ".prod-tbl thead th", text: "Company scale"
    assert_select ".prod-tbl thead th", text: "Registration country"
    assert_select ".badge.badge-suc", text: "Active"
    assert_select "a[href='#{erp_new_store_path(locale: "en")}'][data-turbo-frame='erp_modal']", text: "Add store"
    assert_select "a[href='#{erp_edit_store_path(@store, locale: "en")}'][data-turbo-frame='erp_modal']", text: "Edit"
  end

  test "index filters stores" do
    inactive_store = Ec::Store.create!(
      platform: "wb",
      store_name: "莫斯科 WB 店 #{token_suffix}",
      company_type: "small",
      registration_country: "russia",
      is_active: false
    )

    get "/erp/stores",
      params: { q: "明斯克", platform: "ozon", status: "active" },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='q'][value='明斯克']"
    assert_select "select[name='platform'] option[selected='selected'][value='ozon']"
    assert_select ".prod-tbl td", text: @store.store_name
    assert_no_match inactive_store.store_name, response.body
  end

  test "new renders store form with static options" do
    get "/erp/stores/new", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "新增店铺"
    assert_select "form[action='/erp/stores']"
    assert_select "select[name='ec_store[platform]'] option[value='ozon']", text: "Ozon"
    assert_select "select[name='ec_store[company_type]'] option[value='small']", text: "小规模"
    assert_select "select[name='ec_store[registration_country]'] option[value='belarus']", text: "白俄罗斯"
  end

  test "modal new renders store form" do
    get "/erp/stores/new", headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "新增店铺"
    assert_select "form[action='/erp/stores'][data-turbo-frame='_top']"
  end

  test "store modal form localizes visible chrome in english" do
    get "/erp/stores/new", params: { locale: "en" }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "h2", "Add store"
    assert_select "button[aria-label=?]", "Close"
    assert_select "label", "Platform"
    assert_select "label", "Company scale"
    assert_select "label", "Name"
    assert_select "input[placeholder=?]", "Example: Minsk Ozon store"
    assert_select "option", "Please select"
    assert_select ".switch-checkbox span", "Inactive stores will not enter the 1.0 operations workflow."
    assert_select "input[type='submit'][value=?]", "Save"
  end

  test "create store returns to store list" do
    assert_difference "Ec::Store.count", 1 do
      post "/erp/stores", params: {
        ec_store: {
          platform: "wb",
          store_name: "新增 WB 店 #{token_suffix}",
          company_type: "small",
          registration_country: "russia",
          is_active: "1",
          memo: "手动录入"
        }
      }
    end

    created = Ec::Store.find_by!(store_name: "新增 WB 店 #{token_suffix}")
    assert_redirected_to "/erp/stores"
    assert_equal "wb", created.platform
    assert_equal "small", created.company_type
    assert_equal "russia", created.registration_country
  end

  test "invalid modal create rerenders store form" do
    post "/erp/stores", params: {
      ec_store: {
        platform: "ozon",
        store_name: "",
        company_type: "general",
        registration_country: ""
      }
    }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select ".error-box"
  end

  test "edit and update store returns to store list" do
    get "/erp/stores/#{@store.id}/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "编辑店铺"

    sign_in @current_user
    patch "/erp/stores/#{@store.id}", params: {
      ec_store: {
        store_name: "更新 Ozon 店 #{token_suffix}",
        company_type: "small",
        registration_country: "russia",
        is_active: "0"
      }
    }

    assert_redirected_to "/erp/stores"
    @store.reload
    assert_equal "更新 Ozon 店 #{token_suffix}", @store.store_name
    assert_equal "small", @store.company_type
    assert_equal "russia", @store.registration_country
    assert_not @store.is_active
  end

  test "sku product can have multiple operator users" do
    sku = Ec::Sku.create!(
      sku_code: "STORE-OPS-#{token_suffix}",
      product_name: "店铺运营 SKU #{token_suffix}",
      is_active: true
    )
    product = Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: @store,
      product_id: "P-#{token_suffix}",
      offer_id: "OFFER-#{token_suffix}",
      product_name: "店铺运营商品 #{token_suffix}"
    )
    operator_a = create_user_with_roles("store-operator-a-#{@token.downcase}@example.com", "operator")
    operator_b = create_user_with_roles("store-operator-b-#{@token.downcase}@example.com", "operator")

    product.operators = [operator_a, operator_b]
    product.save!

    assert_equal [operator_a.email, operator_b.email].sort, product.reload.operators.map(&:email).sort
    assert_equal ["operator"], product.operator_assignments.pluck(:role).uniq
    assert_includes operator_a.reload.operated_sku_products, product
  ensure
    Ec::SkuProductOperator.joins(:sku_product).where(ec_sku_products: { sku_code: sku&.sku_code }).delete_all if defined?(Ec::SkuProductOperator)
    Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all if sku
    UserRole.joins(:user).where("users.email LIKE ?", "store-operator-%#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "store-operator-%#{@token.downcase}%").delete_all
  end

  test "show renders store products and current operators for manager" do
    raw_account = RawOzon::SellerAccount.create!(
      company_name: "Store Show Ozon #{@token}",
      client_id: "store-show-ozon-#{@token}",
      api_key: "api-key-#{@token}",
      company_type: "general"
    )
    @store.update!(ozon_raw_account_id: raw_account.id)
    sku = Ec::Sku.create!(
      sku_code: "STORE-SHOW-#{token_suffix}",
      product_name: "店铺详情 SKU #{token_suffix}",
      is_active: true
    )
    RawOzon::Product.create!(
      account: raw_account,
      ozon_product_id: "70#{@token.hex % 1_000_000}",
      offer_id: "BOUND-RAW-OFFER-#{token_suffix}",
      name: "已绑定平台商品 #{token_suffix}",
      raw_json: { "sku" => "BOUND-RAW-SKU-#{token_suffix}" },
      synced_at: Time.zone.parse("2026-06-15 10:00:00")
    )
    unbound_raw_product = RawOzon::Product.create!(
      account: raw_account,
      ozon_product_id: "71#{@token.hex % 1_000_000}",
      offer_id: "UNBOUND-RAW-OFFER-#{token_suffix}",
      name: "未绑定平台商品 #{token_suffix}",
      raw_json: { "sku" => "UNBOUND-RAW-SKU-#{token_suffix}" },
      synced_at: Time.zone.parse("2026-06-16 11:30:00")
    )
    product = Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: @store,
      product_id: "70#{@token.hex % 1_000_000}",
      offer_id: "BOUND-RAW-OFFER-#{token_suffix}",
      product_name: "店铺详情商品 #{token_suffix}"
    )
    unassigned_product = Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: @store,
      product_id: "SHOW-EMPTY-#{token_suffix}",
      product_name: "未绑定运营商品 #{token_suffix}"
    )
    operator = create_user_with_roles("store-show-operator-#{@token.downcase}@example.com", "operator")
    developer = create_user_with_roles("store-show-developer-#{@token.downcase}@example.com", "operator")
    operator.update!(name: "运营 #{@token}")
    developer.update!(name: "开发 #{@token}")
    product.operators = [operator]
    Ec::SkuProductOperator.create!(sku_product: product, user: developer, role: "developer")

    get "/erp/stores/#{@store.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @store.store_name
    assert_select "dt", "店铺 ID"
    assert_select "dd", "SHOP-%03d" % @store.id
    assert_select "h2", "店铺商品"
    assert_select "td", sku.sku_code
    assert_select "td", "70#{@token.hex % 1_000_000}"
    assert_select "td", "BOUND-RAW-OFFER-#{token_suffix}"
    assert_select "td", "店铺详情商品 #{token_suffix}"
    assert_select "td", "SHOW-EMPTY-#{token_suffix}"
    assert_select ".raw-product-options thead th", text: "开发人员"
    assert_select ".raw-product-options thead th", text: "运营人员"
    assert_select "h2", "未绑定平台商品"
    assert_select "td", unbound_raw_product.ozon_product_id.to_s
    assert_select "td", "UNBOUND-RAW-OFFER-#{token_suffix}"
    assert_select "td", "UNBOUND-RAW-SKU-#{token_suffix}"
    assert_select "td", "未绑定平台商品 #{token_suffix}"
    assert_includes response.body, "2026-06-16 19:30"
    assert_no_match "已绑定平台商品 #{token_suffix}", response.body
    assert_select ".operator-list button[type='button'][data-action=?][data-operator-dialog-id=?]", "click->operator-dialog#open", "operator-dialog-#{product.id}", text: developer.name
    assert_select ".operator-list button[type='button'][data-action=?][data-operator-dialog-id=?]", "click->operator-dialog#open", "operator-dialog-#{product.id}", text: operator.name
    assert_select ".operator-list button[type='button'][data-action=?][data-operator-dialog-id=?]", "click->operator-dialog#open", "operator-dialog-#{unassigned_product.id}", text: "未绑定"
    assert_select "form[action=?][method=?]", "/erp/stores/#{@store.id}/sku_products/#{product.id}/operators", "post"
    assert_select "dialog#operator-dialog-#{product.id}.operator-assignment-dialog" do
      assert_select "h3", "绑定职责人员"
      assert_select "select[multiple='multiple'][name='developer_ids[]']" do
        assert_select "option[selected='selected'][value=?]", developer.id.to_s, text: developer.name
      end
      assert_select "select[multiple='multiple'][name='operator_ids[]']" do
        assert_select "option[selected='selected'][value=?]", operator.id.to_s, text: operator.name
      end
      assert_select "button[type='submit']", "保存职责人员"
    end
    assert_select "td > button[type='button']", text: "绑定运营人员", count: 0
    assert_select "input[type=?][name=?]", "checkbox", "developer_ids[]", count: 0
    assert_select "input[type=?][name=?]", "checkbox", "operator_ids[]", count: 0
  ensure
    Ec::SkuProductOperator.joins(:sku_product).where(ec_sku_products: { sku_code: sku&.sku_code }).delete_all if defined?(Ec::SkuProductOperator)
    Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
    RawOzon::Product.where(account_id: raw_account&.id).delete_all if raw_account
    raw_account&.destroy
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all if sku
    UserRole.joins(:user).where("users.email LIKE ?", "store-show-%#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "store-show-%#{@token.downcase}%").delete_all
  end

  test "show hides operator management form for read only erp user" do
    readonly_user = create_user_with_roles("store-readonly-#{@token.downcase}@example.com", "operator")
    sign_in readonly_user
    sku = Ec::Sku.create!(
      sku_code: "STORE-READ-#{token_suffix}",
      product_name: "只读店铺 SKU #{token_suffix}",
      is_active: true
    )
    product = Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: @store,
      product_id: "READ-#{token_suffix}",
      product_name: "只读店铺商品 #{token_suffix}"
    )

    get "/erp/stores/#{@store.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", "READ-#{token_suffix}"
    assert_select "form[action=?]", "/erp/stores/#{@store.id}/sku_products/#{product.id}/operators", count: 0
  ensure
    sign_in @current_user
    Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all if sku
    UserRole.joins(:user).where("users.email LIKE ?", "store-readonly-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "store-readonly-#{@token.downcase}%").delete_all
  end

  test "update operators replaces assigned user set" do
    sku = Ec::Sku.create!(
      sku_code: "STORE-UPD-#{token_suffix}",
      product_name: "更新运营 SKU #{token_suffix}",
      is_active: true
    )
    product = Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: @store,
      product_id: "UPD-#{token_suffix}",
      product_name: "更新运营商品 #{token_suffix}"
    )
    old_operator = create_user_with_roles("store-old-operator-#{@token.downcase}@example.com", "operator")
    new_operator = create_user_with_roles("store-new-operator-#{@token.downcase}@example.com", "operator")
    old_developer = create_user_with_roles("store-old-developer-#{@token.downcase}@example.com", "operator")
    new_developer = create_user_with_roles("store-new-developer-#{@token.downcase}@example.com", "operator")
    inactive_operator = create_user_with_roles("store-inactive-operator-#{@token.downcase}@example.com", "operator")
    inactive_operator.update!(active: false)
    product.operators = [old_operator]
    Ec::SkuProductOperator.create!(sku_product: product, user: old_developer, role: "developer")

    patch "/erp/stores/#{@store.id}/sku_products/#{product.id}/operators", params: {
      developer_ids: [new_developer.id.to_s],
      operator_ids: [new_operator.id.to_s, inactive_operator.id.to_s]
    }

    assert_redirected_to "/erp/stores/#{@store.id}"
    assert_equal [new_operator.id], product.reload.operator_ids
    assert_equal [new_developer.id], product.developer_ids
    assert_equal(
      { new_developer.id => "developer", new_operator.id => "operator" },
      product.operator_assignments.pluck(:user_id, :role).to_h
    )
  ensure
    Ec::SkuProductOperator.joins(:sku_product).where(ec_sku_products: { sku_code: sku&.sku_code }).delete_all if defined?(Ec::SkuProductOperator)
    Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all if sku
    UserRole.joins(:user).where("users.email LIKE ?", "store-%#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "store-%#{@token.downcase}%").delete_all
  end

  test "update operators only updates products under the current store" do
    other_store = Ec::Store.create!(
      platform: "ozon",
      store_name: "其他 Ozon 店 #{token_suffix}",
      company_type: "general",
      registration_country: "belarus",
      is_active: true
    )
    sku = Ec::Sku.create!(
      sku_code: "STORE-WRONG-#{token_suffix}",
      product_name: "错误店铺 SKU #{token_suffix}",
      is_active: true
    )
    product = Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: other_store,
      product_id: "WRONG-#{token_suffix}",
      product_name: "错误店铺商品 #{token_suffix}"
    )
    operator = create_user_with_roles("store-wrong-operator-#{@token.downcase}@example.com", "operator")

    patch "/erp/stores/#{@store.id}/sku_products/#{product.id}/operators", params: {
      operator_ids: [operator.id.to_s]
    }

    assert_response :not_found
    assert_empty product.reload.operators
  ensure
    Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all if sku
    other_store&.destroy
    UserRole.joins(:user).where("users.email LIKE ?", "store-wrong-operator-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "store-wrong-operator-#{@token.downcase}%").delete_all
  end

  private

  def token_suffix
    @token
  end
end
