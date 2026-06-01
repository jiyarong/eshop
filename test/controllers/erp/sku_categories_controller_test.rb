require "test_helper"

class Erp::SkuCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-categories-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @category = Ec::SkuCategory.create!(code: "PAGE-CAT-#{@token}", name: "页面类目")
  end

  teardown do
    Ec::SkuCategory.where("code LIKE ?", "%#{@token}%").delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-categories-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-categories-#{@token.downcase}%").delete_all
  end

  test "index renders categories" do
    get "/erp/sku_categories", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU 类别"
    assert_select "td", @category.code
    assert_select "td", @category.name
  end

  test "show renders category detail" do
    get "/erp/sku_categories/#{@category.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @category.name
    assert_select "dt", "类别编码"
  end

  test "new renders form" do
    get "/erp/sku_categories/new", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "新增 SKU 类别"
    assert_select "form[action='/erp/sku_categories']"
  end

  test "create category" do
    assert_difference "Ec::SkuCategory.count", 1 do
      post "/erp/sku_categories", params: {
        ec_sku_category: {
          code: "created-cat-#{@token}",
          name: "新增类目",
          parent_id: @category.id,
          position: 2,
          is_active: "1",
          memo: "手动录入"
        }
      }
    end

    created = Ec::SkuCategory.find_by!(code: "CREATED-CAT-#{@token}")
    assert_redirected_to "/erp/sku_categories/#{created.id}"
    assert_equal @category, created.parent
  end

  test "edit and update category" do
    get "/erp/sku_categories/#{@category.id}/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "编辑 SKU 类别"

    sign_in @current_user
    patch "/erp/sku_categories/#{@category.id}", params: {
      ec_sku_category: {
        name: "更新类目",
        position: 3,
        is_active: "0"
      }
    }

    assert_redirected_to "/erp/sku_categories/#{@category.id}"
    @category.reload
    assert_equal "更新类目", @category.name
    assert_not @category.is_active
  end
end
