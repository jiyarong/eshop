require "test_helper"

class Erp::SkusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-skus-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @category = Ec::SkuCategory.create!(code: "SKU-PAGE-CAT-#{@token}", name: "SKU 页面类目")
    @master_sku = Ec::MasterSku.create!(
      master_sku_code: "MASTER-#{@token}",
      product_name: "页面主产品",
      product_name_ru: "Главный товар",
      is_active: true
    )
    @sku = Ec::Sku.create!(
      master_sku: @master_sku,
      sku_code: "SKU-PAGE-#{@token}",
      product_name: "页面商品",
      product_name_ru: "Товар",
      sku_category: @category,
      color: "白色",
      spec: "双支装",
      owner_name: "运营 A",
      is_active: true
    )
    @batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "BATCH-#{@token}-A",
      status: "received",
      purchased_quantity: 200,
      received_quantity: 180,
      purchase_unit_price_cny: 12.5,
      expected_arrival_on: Date.parse("2026-06-04"),
      received_on: Date.parse("2026-05-28")
    )
    @inactive_sku = Ec::Sku.create!(
      sku_code: "SKU-INACTIVE-#{@token}",
      product_name: "下架商品",
      product_name_ru: "Неактивный товар",
      color: "黑色",
      is_active: false
    )
  end

  teardown do
    Ec::SkuBatch.where("batch_code LIKE ?", "%#{@token}%").delete_all
    Ec::Sku.where("sku_code LIKE ?", "%#{@token}%").delete_all
    Ec::MasterSku.where("master_sku_code LIKE ?", "%#{@token}%").delete_all if defined?(Ec::MasterSku)
    Ec::SkuCategory.where(id: @category.id).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-skus-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-skus-#{@token.downcase}%").delete_all
  end

  test "index renders skus" do
    get "/erp/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "产品管理"
    assert_select ".product-management"
    assert_select ".page-h"
    assert_select ".product-page-actions a", text: "新增产品"
    assert_no_match "Import", response.body
    assert_no_match "展开全部", response.body
    assert_no_match "收起全部", response.body
    assert_select ".card.product-filter-card form[action='/erp/skus'][method='get']"
    assert_select "input[name='q']"
    assert_select "select[name='category_id']"
    assert_select ".product-summary-grid", 1
    assert_select ".product-summary-card", 4
    assert_select ".card.product-list-card"
    assert_select ".prod-tbl"
    assert_select ".prod-tbl thead th", text: "Master SKU"
    assert_select ".prod-tbl thead th", text: "中文名"
    assert_select ".prod-tbl thead th", text: "俄文名"
    assert_select ".prod-tbl tr.master .code-text", text: @master_sku.master_sku_code
    assert_select ".product-list-card[data-controller='product-tree']"
    assert_select "button.product-tree-toggle[data-action='product-tree#toggleMaster'][aria-expanded='true']", minimum: 1
    assert_select "button.product-tree-toggle[data-action='product-tree#toggleSku'][aria-expanded='true']", minimum: 1
    assert_select ".sub-h", text: "SKU 变体 · 1 个"
    assert_select ".sub-tbl tr.sku-row .code-text", text: @sku.sku_code
    assert_select ".batch-title", text: "批次清单"
    assert_select ".batch-tbl th", text: "采购日期"
    assert_select ".batch-tbl th", text: "出境日期"
    assert_select ".batch-tbl th", text: "境外交付日期"
    assert_no_match "入库日期", response.body
    assert_no_match "境内交付日期", response.body
    assert_no_match "采购单价", response.body
    assert_no_match "成本价", response.body
    assert_no_match "仓库", response.body
    assert_select ".batch-tbl td .barcode", text: @batch.batch_code
    assert_select ".batch-tbl td", text: "180"
    assert_select "td", "页面主产品"
    assert_select ".attr-zh", text: @category.name
    assert_select ".badge.badge-suc", text: "Active"
    assert_select ".badge.badge-sec", text: "下架"
    assert_select "turbo-frame#erp_modal"
    assert_select "a[href='#{erp_new_master_sku_path}'][data-turbo-frame='erp_modal']", text: "新增产品"
    assert_select "a[href='#{erp_edit_master_sku_path(@master_sku)}'][data-turbo-frame='erp_modal']", text: "编辑产品"
    assert_select "a[href='#{erp_new_sku_path(master_sku_id: @master_sku.id)}'][data-turbo-frame='erp_modal']", text: "新增 SKU"
    assert_select "a[href='#{erp_edit_sku_path(@sku)}'][data-turbo-frame='erp_modal']", text: "编辑"
    assert_select "a[href='#{erp_new_sku_batch_path(sku_code: @sku.sku_code)}'][data-turbo-frame='erp_modal']", text: "新增批次"
    assert_select "a[href='#{erp_edit_sku_batch_path(@batch)}'][data-turbo-frame='erp_modal']", text: "编辑"
  end

  test "index filters products by keyword and status" do
    get "/erp/skus", params: { q: @master_sku.master_sku_code.downcase, status: "active" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='q'][value=?]", @master_sku.master_sku_code.downcase
    assert_select ".prod-tbl tr.master .code-text", text: @master_sku.master_sku_code
    assert_no_match @inactive_sku.sku_code, response.body
  end

  test "show redirects to sku report detail" do
    get "/erp/skus/#{@sku.id}", headers: { "Accept" => "text/html" }

    assert_redirected_to "/reports/skus/#{@sku.sku_code}"
  end

  test "new renders form" do
    get "/erp/skus/new", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "新增 SKU"
    assert_select "form[action='/erp/skus']"
  end

  test "modal new renders sku form with selected master sku" do
    get "/erp/skus/new", params: { master_sku_id: @master_sku.id }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "form[action='/erp/skus'][data-turbo-frame='_top']"
    assert_select "select[name='ec_sku[master_sku_id]'] option[selected='selected'][value=?]", @master_sku.id.to_s
  end

  test "modal edit renders sku form" do
    get "/erp/skus/#{@sku.id}/edit", headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "编辑 SKU"
    assert_select "form[action='#{erp_sku_path(@sku)}'][data-turbo-frame='_top']"
    assert_select "input[name='ec_sku[product_name]'][value=?]", @sku.product_name
  end

  test "create sku returns to sku list" do
    assert_difference "Ec::Sku.count", 1 do
      post "/erp/skus", params: {
        ec_sku: {
          master_sku_id: @master_sku.id,
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
    assert_redirected_to "/erp/skus"
    assert_equal @category, created.sku_category
    assert_equal @master_sku, created.master_sku
  end

  test "invalid modal create rerenders sku form" do
    post "/erp/skus", params: {
      ec_sku: {
        master_sku_id: @master_sku.id,
        sku_code: "",
        product_name: "缺少编码"
      }
    }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select ".error-box"
  end

  test "edit and update sku returns to sku list" do
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

    assert_redirected_to "/erp/skus"
    @sku.reload
    assert_equal "更新商品", @sku.product_name
    assert_equal "蓝色", @sku.color
    assert_not @sku.is_active
  end

  test "invalid modal update rerenders sku form" do
    patch "/erp/skus/#{@sku.id}", params: {
      ec_sku: {
        sku_code: "",
        product_name: "缺少编码"
      }
    }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "编辑 SKU"
    assert_select ".error-box"
  end
end
