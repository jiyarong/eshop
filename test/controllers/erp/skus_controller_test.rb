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
      purchase_date: Date.parse("2026-05-12"),
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
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").select(:id)).delete_all if defined?(Ec::OperationLog)
    Ec::SkuBatch.where("batch_code LIKE ?", "%#{@token}%").delete_all
    Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").delete_all
    Ec::MasterSku.where("master_sku_code LIKE ?", "%#{@token}%").delete_all if defined?(Ec::MasterSku)
    Ec::SkuCategory.where(id: @category.id).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-skus-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-skus-#{@token.downcase}%").delete_all
  end

  test "index renders skus" do
    get "/erp/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SPU 管理"
    assert_select ".product-management"
    assert_select ".page-h"
    assert_select ".product-page-actions a", text: "新增 SPU"
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
    assert_select ".prod-tbl thead th", text: "SPU"
    assert_select ".prod-tbl thead th", text: "中文名"
    assert_select ".prod-tbl thead th", text: "俄文名"
    assert_select ".prod-tbl tr.master .code-text", text: @master_sku.master_sku_code
    assert_select ".product-list-card[data-controller='product-tree']"
    assert_select "tr.master.open", count: 0
    assert_select "tr.sku-row.open", count: 0
    assert_select "tr.sub-row[hidden]", minimum: 1
    assert_select "tr.batch-row[hidden]", minimum: 1
    assert_select "button.product-tree-toggle[data-action='product-tree#toggleMaster'][aria-expanded='false']", minimum: 1
    assert_select "button.product-tree-toggle[data-action='product-tree#toggleSku'][aria-expanded='false']", minimum: 1
    assert_select "button.product-tree-toggle[aria-expanded='false'] i.bi-chevron-right", minimum: 1
    assert_select "button.product-tree-toggle[aria-expanded='false'] i.bi-chevron-down", count: 0
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
    assert_select "turbo-frame#sku_batch_#{@batch.id}_batch_code_cell .inline-edit-cell--display", text: @batch.batch_code
    assert_select ".batch-tbl td", text: "180"
    assert_select "td", "页面主产品"
    assert_select ".attr-zh", text: @category.name
    assert_select ".badge.badge-suc", text: "Active"
    assert_select ".badge.badge-sec", text: "下架"
    assert_select "turbo-frame#erp_modal"
    assert_select "a[href='#{erp_new_master_sku_path}'][data-turbo-frame='erp_modal']", text: "新增 SPU"
    assert_select "a[href='#{erp_edit_master_sku_path(@master_sku)}'][data-turbo-frame='erp_modal']", text: "编辑 SPU"
    assert_select "a[href='#{erp_new_sku_path(master_sku_id: @master_sku.id)}'][data-turbo-frame='erp_modal']", text: "新增 SKU"
    assert_select "a[href='#{erp_edit_sku_path(@sku)}'][data-turbo-frame='erp_modal']", text: "编辑"
    assert_select "a[href='#{erp_sku_path(@sku)}'][data-turbo-method='delete'][data-turbo-confirm=?]", "确认删除这个 SKU？", minimum: 1
    assert_select "a[href='#{erp_new_sku_batch_path(sku_code: @sku.sku_code, return_to: "/erp/skus")}'][data-turbo-frame='erp_modal']", text: "新增批次"
    assert_select "a[href='#{erp_edit_sku_batch_path(@batch, return_to: "/erp/skus")}'][data-turbo-frame='erp_modal']", text: "编辑"
    assert_select "a[data-turbo-method='delete'][data-turbo-confirm=?][href=?]", "确认删除这个批次？", erp_sku_batch_path(@batch, return_to: "/erp/skus"), minimum: 1
  end

  test "inventory batch rows render inline editable cell frames" do
    get "/erp/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "turbo-frame#sku_batch_#{@batch.id}_batch_code_cell", count: 1
    assert_select "turbo-frame#sku_batch_#{@batch.id}_purchase_date_cell", count: 1
    assert_select "turbo-frame#sku_batch_#{@batch.id}_expected_arrival_on_cell", count: 1
    assert_select "turbo-frame#sku_batch_#{@batch.id}_received_on_cell", count: 1
    assert_select "turbo-frame#sku_batch_#{@batch.id}_purchased_quantity_cell", count: 1
    assert_select "turbo-frame#sku_batch_#{@batch.id}_received_quantity_cell", count: 1
    assert_select "turbo-frame#sku_batch_#{@batch.id}_status_cell", count: 1
    assert_select "#global_toast", count: 1
    assert_select "#batch-inline-feedback--sku-#{@sku.id}", count: 0
    assert_select "tr.batch-row[hidden] table.batch-tbl tbody tr", count: 1 do
      assert_select "td:nth-of-type(2) .inline-edit-cell--display", text: @batch.purchase_date.to_s
    end
    assert_match @batch.purchase_date.to_s, response.body
  end

  test "index localizes visible chrome in english" do
    get "/erp/skus", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SPU Management"
    assert_select ".product-page-actions a", text: "Add SPU"
    assert_select ".product-summary-grid[aria-label=?]", "Product overview"
    assert_select ".summary-label", "Batches"
    assert_select ".summary-label", "Active SPUs"
    assert_select "input[placeholder=?]", "Search SPU, Chinese name, or Russian name..."
    assert_select "label", "Status"
    assert_select "option", "All"
    assert_select "option", "Enabled"
    assert_select "label", "Category"
    assert_select "option", "All categories"
    assert_select "button", "Filter"
    assert_select "a", "Reset"
    assert_select ".prod-tbl thead th", text: "Chinese name"
    assert_select ".prod-tbl thead th", text: "Actions"
    assert_select ".sub-h", text: "SKU variants · 1 item"
    assert_select ".batch-title", text: "Batch list"
    assert_select ".batch-tbl th", text: "Purchase date"
    assert_select ".badge.badge-suc", text: "Active"
    assert_select ".badge.badge-sec", text: "Inactive"
    assert_select "a[href='#{erp_new_master_sku_path(locale: "en")}'][data-turbo-frame='erp_modal']", text: "Add SPU"
    assert_select "a[href='#{erp_new_sku_path(locale: "en", master_sku_id: @master_sku.id)}'][data-turbo-frame='erp_modal']", text: "Add SKU"
    assert_select "a[href='#{erp_sku_path(@sku, locale: "en")}'][data-turbo-method='delete']", minimum: 1 do |links|
      assert_equal "Delete this SKU?", links.first["data-turbo-confirm"]
    end
    assert_select "a[href='#{erp_new_sku_batch_path(locale: "en", sku_code: @sku.sku_code, return_to: "/erp/skus?locale=en")}'][data-turbo-frame='erp_modal']", text: "Add batch"
    assert_select "a[href='#{erp_sku_batch_path(@batch, locale: "en", return_to: "/erp/skus?locale=en")}'][data-turbo-method='delete']", minimum: 1 do |links|
      assert_equal "Delete this batch?", links.first["data-turbo-confirm"]
    end
  end

  test "index filters products by keyword and status" do
    get "/erp/skus", params: { q: @master_sku.master_sku_code.downcase, status: "active" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='q'][value=?]", @master_sku.master_sku_code.downcase
    assert_select ".prod-tbl tr.master .code-text", text: @master_sku.master_sku_code
    assert_no_match @inactive_sku.sku_code, response.body
  end

  test "index does not render expand toggle for unfiled sku without batches" do
    orphan = Ec::Sku.create!(
      sku_code: "SKU-ORPHAN-#{@token}",
      product_name: "无批次商品",
      is_active: true
    )

    get "/erp/skus", params: { q: orphan.sku_code }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td .code-text.sub", orphan.sku_code
    assert_select "button.product-tree-toggle[data-action='product-tree#toggleMaster']", count: 0
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

  test "sku modal form localizes visible chrome in english" do
    get "/erp/skus/#{@sku.id}/edit", params: { locale: "en" }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "h2", "Edit SKU"
    assert_select "button[aria-label=?]", "Close"
    assert_select "label", "SKU code"
    assert_select "label", "Chinese name"
    assert_select "label", "Listed"
    assert_select "option", "None"
    assert_select "input[type='submit'][value=?]", "Save"
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

  test "update sku records operation log with signed in user" do
    assert_difference "Ec::OperationLog.count", 1 do
      patch "/erp/skus/#{@sku.id}", params: {
        ec_sku: {
          product_name: "审计更新商品",
          color: "绿色"
        }
      }
    end

    log = Ec::OperationLog.order(:created_at).last
    assert_equal @current_user, log.user
    assert_equal "Ec::Sku", log.record_type
    assert_equal @sku.id, log.record_id
    assert_equal "update", log.action
    assert_equal [
      { "field" => "product_name", "from" => "页面商品", "to" => "审计更新商品" },
      { "field" => "color", "from" => "白色", "to" => "绿色" }
    ], log.changeset
  end

  test "destroy soft deletes sku and hides it from index" do
    assert_no_difference "Ec::Sku.with_deleted.count" do
      delete "/erp/skus/#{@sku.id}"
    end

    assert_redirected_to "/erp/skus"
    assert_not_nil Ec::Sku.with_deleted.find(@sku.id).deleted_at
    assert_nil Ec::Sku.find_by(id: @sku.id)

    sign_in @current_user
    get "/erp/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_no_match @sku.sku_code, response.body
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
