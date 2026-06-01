require "test_helper"

class Erp::SkusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-skus-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @category = Ec::SkuCategory.create!(code: "SKU-PAGE-CAT-#{@token}", name: "SKU 页面类目")
    @sku = Ec::Sku.create!(
      sku_code: "SKU-PAGE-#{@token}",
      product_name: "页面商品",
      product_name_ru: "Товар",
      sku_category: @category,
      color: "白色",
      is_active: true
    )
  end

  teardown do
    Ec::Sku.where("sku_code LIKE ?", "%#{@token}%").delete_all
    Ec::SkuCategory.where(id: @category.id).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-skus-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-skus-#{@token.downcase}%").delete_all
  end

  test "index renders skus" do
    get "/erp/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU 管理"
    assert_select "td", @sku.sku_code
    assert_select "td", @category.name
  end

  test "show renders sku detail" do
    get "/erp/skus/#{@sku.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @sku.sku_code
    assert_select "dt", "颜色"
  end

  test "new renders form" do
    get "/erp/skus/new", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "新增 SKU"
    assert_select "form[action='/erp/skus']"
  end

  test "create sku" do
    assert_difference "Ec::Sku.count", 1 do
      post "/erp/skus", params: {
        ec_sku: {
          sku_code: "created-sku-#{@token}",
          product_name: "新增商品",
          product_name_ru: "Новый товар",
          sku_category_id: @category.id,
          color: "黑色",
          spec: "双支装",
          size: "20cm",
          weight_kg: "1.25",
          volume_l: "3.5",
          model: "M-100",
          quality_grade: "A",
          features: "耐磨",
          owner_name: "运营 A",
          is_active: "1",
          memo: "手动录入"
        }
      }
    end

    created = Ec::Sku.find_by!(sku_code: "CREATED-SKU-#{@token}")
    assert_redirected_to "/erp/skus/#{created.id}"
    assert_equal @category, created.sku_category
  end

  test "edit and update sku" do
    get "/erp/skus/#{@sku.id}/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "编辑 SKU"

    sign_in @current_user
    patch "/erp/skus/#{@sku.id}", params: {
      ec_sku: {
        product_name: "更新商品",
        color: "蓝色",
        is_active: "0"
      }
    }

    assert_redirected_to "/erp/skus/#{@sku.id}"
    @sku.reload
    assert_equal "更新商品", @sku.product_name
    assert_equal "蓝色", @sku.color
    assert_not @sku.is_active
  end
end
