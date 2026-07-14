require "test_helper"

class Erp::SpusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-spus-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @category = Ec::SkuCategory.create!(code: "SKU-PAGE-CAT-#{@token}", name: "SKU 页面类目")
    @platform_category_parent = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: platform_category_source_id("parent"),
      origin_name: "Platform Parent #{@token}",
      origin_language: "en",
      name_cn: "平台父类 #{@token}",
      name_en: "Platform Parent #{@token}"
    )
    @platform_category_child = Ec::Category.create!(
      source: "test",
      source_type: "subject",
      source_id: platform_category_source_id("child"),
      parent: @platform_category_parent,
      origin_name: "Platform Child #{@token}",
      origin_language: "en",
      name_cn: "平台子类 #{@token}",
      name_en: "Platform Child #{@token}"
    )
    @master_sku = Ec::MasterSku.create!(
      master_sku_code: "MASTER-#{@token}",
      product_name: "页面主产品",
      product_name_ru: "Главный товар",
      ec_category: @platform_category_child,
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
    marketing_state_ids = Ec::SkuMarketingState.where(sku_id: Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").select(:id)).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuMarketingState", record_id: marketing_state_ids).delete_all
    Ec::SkuMarketingState.where(id: marketing_state_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").select(:id)).delete_all if defined?(Ec::OperationLog)
    Ec::SkuBatch.where("batch_code LIKE ?", "%#{@token}%").delete_all
    Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").delete_all
    Ec::MasterSku.where("master_sku_code LIKE ?", "%#{@token}%").delete_all if defined?(Ec::MasterSku)
    Ec::SkuCategory.where(id: @category.id).delete_all
    Ec::Category.where(source: "test", source_id: platform_category_source_ids).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-spus-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-spus-#{@token.downcase}%").delete_all
  end

  test "index renders skus" do
    get "/erp/spus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SPU 管理"
    assert_select ".product-management"
    assert_select ".page-h"
    assert_select ".product-page-actions a", text: "新增 SPU"
    assert_no_match "Import", response.body
    assert_no_match "展开全部", response.body
    assert_no_match "收起全部", response.body
    assert_select ".card.product-filter-card form[action='/erp/spus'][method='get']"
    assert_select "input[name='q']"
    assert_select ".category-multiselect[data-controller='category-multiselect']"
    assert_select ".category-multiselect__trigger[aria-expanded='false']", text: "全部类别"
    assert_select ".category-multiselect__panel[hidden]", count: 1
    assert_select ".category-multiselect input[type='search'][placeholder=?]", "按类目搜索"
    assert_select ".category-multiselect input[name='category_ids[]'][value=?]", @platform_category_child.id.to_s, count: 1
    assert_select ".category-multiselect__option", text: "平台父类 #{@token} / 平台子类 #{@token}", count: 1
    assert_select ".category-multiselect__option", text: @category.name, count: 0
    assert_select ".product-summary-grid", 1
    assert_select ".product-summary-card", 4
    assert_select ".card.product-list-card"
    assert_select ".prod-tbl"
    assert_select ".prod-tbl thead th", text: "SPU"
    assert_select ".prod-tbl thead th", text: "中文名"
    assert_select ".prod-tbl thead th", text: "俄文名"
    assert_select ".prod-tbl thead th", text: "平台类目"
    assert_select ".prod-tbl tr.master .code-text", text: @master_sku.master_sku_code
    assert_select ".prod-tbl tr.master .platform-category", text: "平台父类 #{@token} / 平台子类 #{@token}"
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
    assert_select ".sku-marketing-state .marketing-tag--unset", text: "Grade 未设置"
    assert_select ".sku-marketing-state .marketing-tag--unset", text: "Stage 未设置"
    assert_select "a[href='#{new_erp_sku_marketing_state_path(@sku, return_to: "/erp/spus")}'][data-turbo-frame='erp_modal']"
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
    assert_select "a[href='#{erp_new_sku_path(master_sku_id: @master_sku.id, return_to: "/erp/spus")}'][data-turbo-frame='erp_modal']", text: "新增 SKU"
    assert_select "a[href='#{erp_edit_sku_path(@sku, return_to: "/erp/spus")}'][data-turbo-frame='erp_modal']", text: "编辑"
    assert_select "a[href=?][data-turbo-method='delete'][data-turbo-confirm=?]", erp_sku_path(@sku, return_to: "/erp/spus"), "确认删除这个 SKU？", minimum: 1
    assert_select "a[href='#{erp_new_sku_batch_path(sku_code: @sku.sku_code, return_to: "/erp/spus")}'][data-turbo-frame='erp_modal']", text: "新增批次"
    assert_select "a[href='#{erp_edit_sku_batch_path(@batch, return_to: "/erp/spus")}'][data-turbo-frame='erp_modal']", text: "编辑"
    assert_select "a[data-turbo-method='delete'][data-turbo-confirm=?][href=?]", "确认删除这个批次？", erp_sku_batch_path(@batch, return_to: "/erp/spus"), minimum: 1
  end

  test "inventory batch rows render inline editable cell frames" do
    get "/erp/spus", headers: { "Accept" => "text/html" }

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
    get "/erp/spus", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SPU Management"
    assert_select ".product-page-actions a", text: "Add SPU"
    assert_select ".product-summary-grid[aria-label=?]", "Product overview"
    assert_select ".summary-label", "Batches"
    assert_select ".summary-label", "Active SPUs"
    assert_select "input[placeholder=?]", "Search SPU, SKU, Chinese name, or Russian name..."
    assert_select ".category-multiselect__trigger", text: "All categories"
    assert_select ".category-multiselect input[type='search'][placeholder=?]", "Search categories"
    assert_select "label", "Status"
    assert_select "option", "All"
    assert_select "option", "Enabled"
    assert_select "label", "Category"
    assert_select "button", "Filter"
    assert_select "a", "Reset"
    assert_select ".prod-tbl thead th", text: "Chinese name"
    assert_select ".prod-tbl thead th", text: "Platform category"
    assert_select ".prod-tbl thead th", text: "Actions"
    assert_select ".prod-tbl thead th", text: "Marketing state"
    assert_select ".marketing-tag--unset", text: "Grade unset"
    assert_select ".prod-tbl tr.master .platform-category", text: "Platform Parent #{@token} / Platform Child #{@token}"
    assert_select ".sub-h", text: "SKU variants · 1 item"
    assert_select ".batch-title", text: "Batch list"
    assert_select ".batch-tbl th", text: "Purchase date"
    assert_select ".badge.badge-suc", text: "Active"
    assert_select ".badge.badge-sec", text: "Inactive"
    assert_select "a[href='#{erp_new_master_sku_path(locale: "en")}'][data-turbo-frame='erp_modal']", text: "Add SPU"
    assert_select "a[href='#{erp_new_sku_path(locale: "en", master_sku_id: @master_sku.id, return_to: "/erp/spus?locale=en")}'][data-turbo-frame='erp_modal']", text: "Add SKU"
    assert_select "a[href=?][data-turbo-method='delete']", erp_sku_path(@sku, locale: "en", return_to: "/erp/spus?locale=en"), minimum: 1 do |links|
      assert_equal "Delete this SKU?", links.first["data-turbo-confirm"]
    end
    assert_select "a[href='#{erp_new_sku_batch_path(locale: "en", sku_code: @sku.sku_code, return_to: "/erp/spus?locale=en")}'][data-turbo-frame='erp_modal']", text: "Add batch"
    assert_select "a[href='#{erp_sku_batch_path(@batch, locale: "en", return_to: "/erp/spus?locale=en")}'][data-turbo-method='delete']", minimum: 1 do |links|
      assert_equal "Delete this batch?", links.first["data-turbo-confirm"]
    end
  end

  test "index renders current marketing state and strategy tags" do
    Ec::SkuMarketingStateChange.new(
      sku: @sku, grade: "A", stage: "grw", changed_by: @current_user, note: "增长阶段"
    ).call

    get "/erp/spus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".sub-tbl tr.sku-row" do
      assert_select ".marketing-grade--a", "Grade A"
      assert_select ".marketing-stage--grw", "Stage GRW"
      assert_select ".sku-marketing-state__strategy", "加速成长"
    end
  end

  test "index filters products by keyword and status" do
    get "/erp/spus", params: { q: @master_sku.master_sku_code.downcase, status: "active" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='q'][value=?]", @master_sku.master_sku_code.downcase
    assert_select ".prod-tbl tr.master .code-text", text: @master_sku.master_sku_code
    assert_no_match @inactive_sku.sku_code, response.body
  end

  test "index filters master sku by full child sku code" do
    get "/erp/spus", params: { q: @sku.sku_code, status: "active" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".prod-tbl tr.master .code-text", text: @master_sku.master_sku_code
    assert_select ".sub-tbl tr.sku-row .code-text", text: @sku.sku_code
    assert_no_match @inactive_sku.sku_code, response.body
  end

  test "index filters by multiple master sku platform categories" do
    other_parent = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: platform_category_source_id("other-parent"),
      origin_name: "Other Parent #{@token}",
      origin_language: "en",
      name_cn: "其他父类 #{@token}",
      name_en: "Other Parent #{@token}"
    )
    other_child = Ec::Category.create!(
      source: "test",
      source_type: "subject",
      source_id: platform_category_source_id("other-child"),
      parent: other_parent,
      origin_name: "Other Child #{@token}",
      origin_language: "en",
      name_cn: "其他子类 #{@token}",
      name_en: "Other Child #{@token}"
    )
    other_master_sku = Ec::MasterSku.create!(
      master_sku_code: "MASTER-OTHER-#{@token}",
      product_name: "其他主产品",
      ec_category: other_child,
      is_active: true
    )
    Ec::Sku.create!(
      master_sku: other_master_sku,
      sku_code: "SKU-OTHER-#{@token}",
      product_name: "其他商品",
      is_active: true
    )

    get "/erp/spus", params: { category_ids: [@platform_category_child.id, other_child.id] }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".category-multiselect__trigger", text: "已选 2 个类目"
    assert_select ".category-multiselect__panel[hidden]", count: 1
    assert_select ".category-multiselect input[name='category_ids[]'][checked='checked']", count: 2
    assert_select ".prod-tbl tr.master .code-text", text: @master_sku.master_sku_code
    assert_select ".prod-tbl tr.master .code-text", text: other_master_sku.master_sku_code

    sign_in @current_user
    get "/erp/spus", params: { category_ids: [other_child.id] }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".prod-tbl tr.master .code-text", text: other_master_sku.master_sku_code
    assert_no_match @master_sku.master_sku_code, response.body
  end

  test "index lists each master sku platform category once" do
    Ec::MasterSku.create!(
      master_sku_code: "MASTER-DUP-#{@token}",
      product_name: "重复类别主产品",
      ec_category: @platform_category_child,
      is_active: true
    )

    get "/erp/spus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".category-multiselect input[name='category_ids[]'][value=?]", @platform_category_child.id.to_s, count: 1
  end

  test "index does not render expand toggle for unfiled sku without batches" do
    orphan = Ec::Sku.create!(
      sku_code: "SKU-ORPHAN-#{@token}",
      product_name: "无批次商品",
      is_active: true
    )

    get "/erp/spus", params: { q: orphan.sku_code }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td .code-text.sub", orphan.sku_code
    assert_select "button.product-tree-toggle[data-action='product-tree#toggleMaster']", count: 0
  end

  private

  def platform_category_source_id(suffix)
    "#{@token}-#{suffix}"
  end

  def platform_category_source_ids
    %w[parent child other-parent other-child].map { |suffix| platform_category_source_id(suffix) }
  end
end
