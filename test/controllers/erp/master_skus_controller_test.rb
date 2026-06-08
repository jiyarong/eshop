require "test_helper"

class Erp::MasterSkusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-master-skus-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
  end

  teardown do
    Ec::Sku.where("sku_code LIKE ?", "%#{@token}%").delete_all
    Ec::MasterSku.where("master_sku_code LIKE ?", "%#{@token}%").delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-master-skus-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-master-skus-#{@token.downcase}%").delete_all
  end

  test "modal new renders master sku form" do
    get "/erp/master_skus/new", headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "新增产品"
    assert_select "form[action='/erp/master_skus'][data-turbo-frame='_top']"
    assert_select "input[name='ec_master_sku[master_sku_code]']"
  end

  test "create master sku redirects to product list" do
    assert_difference "Ec::MasterSku.count", 1 do
      post "/erp/master_skus", params: {
        ec_master_sku: {
          master_sku_code: "master-create-#{@token}",
          product_name: "新增主产品",
          product_name_ru: "Новый главный товар",
          is_active: "1",
          memo: "弹框新增"
        }
      }
    end

    created = Ec::MasterSku.find_by!(master_sku_code: "MASTER-CREATE-#{@token}")
    assert_redirected_to "/erp/skus"
    assert_equal "新增主产品", created.product_name
  end

  test "invalid modal create rerenders form" do
    post "/erp/master_skus", params: {
      ec_master_sku: {
        master_sku_code: "",
        product_name: "缺少编码"
      }
    }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#erp_modal"
    assert_select ".error-box"
  end
end
