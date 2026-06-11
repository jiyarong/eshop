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

  private

  def token_suffix
    @token
  end
end
