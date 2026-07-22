require "test_helper"

class Erp::SkusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-skus-#{@token.downcase}@example.com", "manager")
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
    sku_scope = Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%")
    sku_codes = sku_scope.pluck(:sku_code)
    marketing_state_ids = Ec::SkuMarketingState.where(sku_id: sku_scope.select(:id)).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuMarketingState", record_id: marketing_state_ids).delete_all
    Ec::SkuMarketingState.where(id: marketing_state_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: sku_scope.select(:id)).delete_all if defined?(Ec::OperationLog)
    Ec::SkuDeveloperAssignment.where(sku_code: sku_codes).delete_all if defined?(Ec::SkuDeveloperAssignment)
    if defined?(Ec::SkuProductOperator)
      Ec::SkuProductOperator.joins(:sku_product).where(ec_sku_products: { sku_code: sku_codes }).delete_all
    end
    Ec::SkuProduct.where(sku_code: sku_codes).delete_all if defined?(Ec::SkuProduct)
    Ec::SkuBatch.where("batch_code LIKE ?", "%#{@token}%").delete_all
    sku_scope.delete_all
    Ec::MasterSku.where("master_sku_code LIKE ?", "%#{@token}%").delete_all if defined?(Ec::MasterSku)
    Ec::SkuCategory.where(id: @category.id).delete_all
    Ec::Category.where(source: "test", source_id: platform_category_source_ids).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-skus-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-skus-#{@token.downcase}%").delete_all
  end

  test "index renders sku list with batches" do
    get "/erp/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU 管理"
    assert_select ".product-management.sku-management"
    assert_select ".product-page-actions a[href='#{erp_new_sku_path(return_to: "/erp/skus")}'][data-turbo-frame='erp_modal']", text: "新增 SKU"
    assert_select ".card.product-filter-card form[action='/erp/skus'][method='get']"
    assert_select "input[name='q'][placeholder=?]", "搜索 SKU、SPU、中文名或俄文名…"
    assert_select ".spu-sku-filter"
    assert_select "#sku-spu-sku-filter-trigger", text: "全部 SPU/SKU"
    assert_select ".spu-sku-filter__columns"
    assert_select ".spu-sku-filter__spu-column .spu-sku-filter__spu-button .spu-sku-filter__name", text: @master_sku.master_sku_code
    assert_select ".spu-sku-filter__sku-column .spu-sku-filter__sku-pane .spu-sku-filter__sku-option .spu-sku-filter__name", text: @sku.sku_code
    assert_select "input[type='checkbox'][name='master_sku_ids[]'][value=?]", @master_sku.id.to_s
    assert_select "input[type='checkbox'][name='sku_codes[]'][value=?]", @sku.sku_code
    assert_select ".popover-multiselect", minimum: 2
    assert_select "#sku-grade-filter-trigger", text: "全部 Grade"
    assert_select "#sku-stage-filter-trigger", text: "全部 Stage"
    assert_select "input[type='checkbox'][name='grades[]'][value='S']"
    assert_select "input[type='checkbox'][name='stages[]'][value='new']"
    assert_select ".category-multiselect[data-controller='category-multiselect']"
    assert_select ".category-multiselect__trigger", text: "全部类别"
    assert_select ".category-multiselect input[name='category_ids[]'][value=?]", @platform_category_child.id.to_s
    assert_select ".product-summary-grid[aria-label=?]", "SKU 概览"
    assert_select ".summary-label", "启用 SKU"
    assert_select ".prod-tbl thead th", text: "SKU"
    assert_select ".prod-tbl thead th", text: "SPU"
    assert_select ".prod-tbl thead th", text: "商品名"
    assert_select ".prod-tbl thead th", text: "营销状态"
    assert_select ".prod-tbl thead th", text: "开发人员"
    assert_select ".prod-tbl thead th", text: "运营人员"
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", text: @sku.sku_code
    assert_select ".prod-tbl tr.sku-row.master .code-text", text: @master_sku.master_sku_code
    assert_select ".prod-tbl tr.sku-row.master .product-name-stack" do
      assert_select ".zh-name", text: @sku.product_name
      assert_select ".ru-name", text: @sku.product_name_ru
    end
    assert_select ".prod-tbl tr.sku-row.master .sku-developers", text: "未绑定"
    assert_select ".prod-tbl tr.sku-row.master .sku-operators", text: "未绑定"
    assert_select ".sku-marketing-state .marketing-tag--unset", text: "Grade 未设置"
    assert_select ".sku-marketing-state .marketing-tag--unset", text: "Stage 未设置"
    assert_select "button.product-tree-toggle[data-action='product-tree#toggleMaster'][aria-expanded='false']", minimum: 1
    assert_select "button.product-tree-toggle[data-action='product-tree#toggleSku']", count: 0
    assert_select "tr.batch-row[hidden]", minimum: 1
    assert_select ".batch-title", text: "批次清单"
    assert_select "turbo-frame#sku_batch_#{@batch.id}_batch_code_cell .inline-edit-cell--display", text: @batch.batch_code
    assert_select ".batch-tbl td", text: "180"
    assert_select ".badge.badge-suc", text: "Active"
    assert_select ".badge.badge-sec", text: "下架"
    assert_select "a[href='#{new_erp_sku_marketing_state_path(@sku, return_to: "/erp/skus")}'][data-turbo-frame='erp_modal']"
    assert_select "a.sku-developers[href='#{edit_erp_sku_developer_path(@sku, return_to: "/erp/skus")}'][data-turbo-frame='erp_modal']", text: "未绑定"
    assert_select "a.sku-operators[href='#{edit_erp_sku_operator_path(@sku, return_to: "/erp/skus")}'][data-turbo-frame='erp_modal']", text: "未绑定"
    assert_select "a[href='#{erp_edit_sku_path(@sku, return_to: "/erp/skus")}'][data-turbo-frame='erp_modal']", text: "编辑"
    assert_select "a[href='#{erp_sku_path(@sku)}'][data-turbo-method='delete'][data-turbo-confirm=?]", "确认删除这个 SKU？", minimum: 1
    assert_select "a[href='#{erp_new_sku_batch_path(sku_code: @sku.sku_code, return_to: "/erp/skus")}'][data-turbo-frame='erp_modal']", text: "新增批次"
    assert_select "a[href='#{erp_edit_sku_batch_path(@batch, return_to: "/erp/skus")}'][data-turbo-frame='erp_modal']", text: "编辑"
    assert_select "a[data-turbo-method='delete'][data-turbo-confirm=?][href=?]", "确认删除这个批次？", erp_sku_batch_path(@batch, return_to: "/erp/skus"), minimum: 1
  end

  test "index localizes visible sku list chrome in english" do
    get "/erp/skus", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU Management"
    assert_select ".product-page-actions a[href='#{erp_new_sku_path(locale: "en", return_to: "/erp/skus?locale=en")}'][data-turbo-frame='erp_modal']", text: "Add SKU"
    assert_select ".product-summary-grid[aria-label=?]", "SKU overview"
    assert_select ".summary-label", "Active SKUs"
    assert_select "input[placeholder=?]", "Search SKU, SPU, Chinese name, or Russian name..."
    assert_select "#sku-spu-sku-filter-trigger", text: "All SPUs/SKUs"
    assert_select ".category-multiselect__trigger", text: "All categories"
    assert_select "#sku-grade-filter-trigger", text: "All Grades"
    assert_select "#sku-stage-filter-trigger", text: "All Stages"
    assert_select ".prod-tbl thead th", text: "SKU"
    assert_select ".prod-tbl thead th", text: "SPU"
    assert_select ".prod-tbl thead th", text: "Product name"
    assert_select ".prod-tbl thead th", text: "Marketing state"
    assert_select ".prod-tbl thead th", text: "Developers"
    assert_select ".prod-tbl thead th", text: "Operators"
    assert_select ".marketing-tag--unset", text: "Grade unset"
    assert_select ".batch-title", text: "Batch list"
    assert_select ".batch-tbl th", text: "Purchase date"
    assert_select ".badge.badge-suc", text: "Active"
    assert_select ".badge.badge-sec", text: "Inactive"
    assert_select "a[href='#{erp_new_sku_batch_path(locale: "en", sku_code: @sku.sku_code, return_to: "/erp/skus?locale=en")}'][data-turbo-frame='erp_modal']", text: "Add batch"
    assert_select "a[href='#{erp_sku_batch_path(@batch, locale: "en", return_to: "/erp/skus?locale=en")}'][data-turbo-method='delete']", minimum: 1 do |links|
      assert_equal "Delete this batch?", links.first["data-turbo-confirm"]
    end
  end

  test "index renders current marketing state and strategy tags" do
    Ec::SkuMarketingStateChange.new(
      sku: @sku, grade: "A", stage: "grw", changed_by: @current_user, note: "增长阶段"
    ).call

    get "/erp/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".prod-tbl tr.sku-row" do
      assert_select ".marketing-grade--a", "A"
      assert_select ".marketing-stage--grw", "GRW"
      assert_select ".sku-marketing-state__strategy", "加速成长"
    end
  end

  test "index filters skus by keyword status and master sku" do
    get "/erp/skus", params: { q: @sku.sku_code.downcase, status: "active", master_sku_id: @master_sku.id }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='q'][value=?]", @sku.sku_code.downcase
    assert_select "#sku-spu-sku-filter-trigger", text: @master_sku.master_sku_code
    assert_select "input[type='checkbox'][name='master_sku_ids[]'][value=?][checked='checked']", @master_sku.id.to_s
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", text: @sku.sku_code
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", { text: @inactive_sku.sku_code, count: 0 }
  end

  test "index filters skus by selected spu and sku codes" do
    get "/erp/skus",
      params: { master_sku_ids: [@master_sku.id], sku_codes: [@inactive_sku.sku_code] },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "#sku-spu-sku-filter-trigger", text: "已选 2 项"
    assert_select "input[type='checkbox'][name='master_sku_ids[]'][value=?][checked='checked']", @master_sku.id.to_s
    assert_select "input[type='checkbox'][name='sku_codes[]'][value=?][checked='checked']", @inactive_sku.sku_code
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", text: @sku.sku_code
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", text: @inactive_sku.sku_code
  end

  test "index filters skus by master sku category" do
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
      ec_category: other_child
    )
    other_sku = Ec::Sku.create!(
      master_sku: other_master_sku,
      sku_code: "SKU-PAGE-OTHER-#{@token}",
      product_name: "其他类别 SKU",
      sku_category: @category
    )

    get "/erp/skus", params: { category_ids: [@platform_category_child.id] }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".category-multiselect__trigger", text: "平台父类 #{@token} / 平台子类 #{@token}"
    assert_select ".category-multiselect input[name='category_ids[]'][value=?][checked='checked']", @platform_category_child.id.to_s
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", text: @sku.sku_code
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", { text: other_sku.sku_code, count: 0 }
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", { text: @inactive_sku.sku_code, count: 0 }
  end

  test "index filters skus by responsible users" do
    developer = User.create!(
      email: "erp-skus-#{@token.downcase}-developer@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "SKU 筛选店 #{@token}",
      company_type: "general",
      is_active: true
    )
    sku_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: store,
      product_id: "SKU-FILTER-P-#{@token}",
      platform_sku_id: "SKU-FILTER-PS-#{@token}",
      product_name: "SKU 筛选平台商品 #{@token}"
    )
    Ec::SkuDeveloperAssignment.create!(sku: @sku, user: developer)
    Ec::SkuProductOperator.create!(sku_product: sku_product, user: @current_user)

    get "/erp/skus", params: { developer_id: developer.id, operator_id: @current_user.id }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[type='hidden'][name='developer_id'][value=?]", developer.id.to_s
    assert_select "input[type='hidden'][name='operator_id'][value=?]", @current_user.id.to_s
    assert_select "#sku-responsible-user-filter-developer-trigger", text: developer.display_name
    assert_select "#sku-responsible-user-filter-operator-trigger", text: @current_user.display_name
    assert_select ".responsible-user-filter__option.is-selected[data-value='#{developer.id}'] .responsible-user-filter__name", text: developer.display_name
    assert_select ".responsible-user-filter__option--shortcut.is-selected[data-value='#{@current_user.id}']", text: "选中自己"
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", text: @sku.sku_code
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", { text: @inactive_sku.sku_code, count: 0 }
  ensure
    Ec::SkuDeveloperAssignment.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuDeveloperAssignment)
    Ec::SkuProductOperator.where(sku_product_id: sku_product&.id).delete_all if defined?(Ec::SkuProductOperator) && defined?(sku_product)
    sku_product&.destroy
    store&.destroy
  end

  test "index displays sku developers and multiple product operators" do
    developer = User.create!(
      email: "erp-skus-#{@token.downcase}-display-developer@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "开发 #{@token}"
    )
    operator_a = User.create!(
      email: "erp-skus-#{@token.downcase}-display-operator-a@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "运营 A #{@token}"
    )
    operator_b = User.create!(
      email: "erp-skus-#{@token.downcase}-display-operator-b@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "运营 B #{@token}"
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "SKU 展示职责店 #{@token}",
      company_type: "general",
      is_active: true
    )
    sku_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: store,
      product_id: "SKU-DISPLAY-P-#{@token}",
      platform_sku_id: "SKU-DISPLAY-PS-#{@token}",
      product_name: "SKU 展示平台商品 #{@token}"
    )
    Ec::SkuDeveloperAssignment.create!(sku: @sku, user: developer)
    Ec::SkuProductOperator.create!(sku_product: sku_product, user: operator_a)
    Ec::SkuProductOperator.create!(sku_product: sku_product, user: operator_b)

    get "/erp/skus", params: { q: @sku.sku_code }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".prod-tbl tr.sku-row.master", 1 do
      assert_select ".code-text.sub", text: @sku.sku_code
      assert_select ".sku-developers", text: developer.name
      assert_select ".sku-operators", text: "#{operator_a.name}, #{operator_b.name}"
    end
  ensure
    Ec::SkuDeveloperAssignment.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuDeveloperAssignment)
    Ec::SkuProductOperator.where(sku_product_id: sku_product&.id).delete_all if defined?(Ec::SkuProductOperator) && defined?(sku_product)
    sku_product&.destroy
    store&.destroy
  end

  test "index filters sku by master sku keyword" do
    get "/erp/skus", params: { q: @master_sku.master_sku_code.downcase }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", text: @sku.sku_code
    assert_select ".prod-tbl tr.sku-row.master .code-text", text: @master_sku.master_sku_code
  end

  test "index filters skus by current marketing grades and stages" do
    Ec::SkuMarketingStateChange.new(
      sku: @sku, grade: "A", stage: "grw", changed_by: @current_user, note: "增长阶段"
    ).call
    other_sku = Ec::Sku.create!(
      sku_code: "SKU-MKT-#{@token}",
      product_name: "其他营销商品",
      is_active: true
    )
    Ec::SkuMarketingStateChange.new(
      sku: other_sku, grade: "A", stage: "mat", changed_by: @current_user, note: "成熟阶段"
    ).call
    excluded_sku = Ec::Sku.create!(
      sku_code: "SKU-MKT-EXC-#{@token}",
      product_name: "不匹配营销商品",
      is_active: true
    )
    Ec::SkuMarketingStateChange.new(
      sku: excluded_sku, grade: "B", stage: "new", changed_by: @current_user, note: "不匹配筛选"
    ).call

    get "/erp/skus", params: { grades: ["a"], stages: ["GRW", "MAT"] }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "#sku-grade-filter-trigger", text: "A"
    assert_select "#sku-stage-filter-trigger", text: "已选 2 项"
    assert_select "input[type='checkbox'][name='grades[]'][value='A'][checked='checked']"
    assert_select "input[type='checkbox'][name='stages[]'][value='grw'][checked='checked']"
    assert_select "input[type='checkbox'][name='stages[]'][value='mat'][checked='checked']"
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", text: @sku.sku_code
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", text: other_sku.sku_code
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", { text: excluded_sku.sku_code, count: 0 }
    assert_select ".prod-tbl tr.sku-row.master .code-text.sub", { text: @inactive_sku.sku_code, count: 0 }
  end

  test "index paginates sku list with inventory pagination styling" do
    22.times do |index|
      Ec::Sku.create!(
        sku_code: format("SKU-PAG-%02d-%s", index, @token),
        product_name: "分页 SKU #{index}",
        is_active: true
      )
    end

    get "/erp/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "tbody tr.sku-row.master", count: 10
    assert_select ".inventory-pagination-bar"
    assert_select ".inventory-pagination-bar .pagination-nav"
    assert_select ".inventory-pagination-bar .pagination-chip", "第 1/3 页"
    assert_select ".inventory-pagination-bar", /显示第 1-10 条，共 24 条/
    assert_select ".inventory-pagination-bar .pagination-jump-input[value='1']"
    assert_select ".inventory-pagination-bar .pg-btn", "2"

    sign_in @current_user
    get "/erp/skus", params: { page: 2, q: "SKU-PAG-" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "tbody tr.sku-row.master", count: 10
    assert_select ".inventory-pagination-bar .pagination-chip", "第 2/3 页"
    assert_select ".inventory-pagination-bar", /显示第 11-20 条，共 22 条/
    assert_select ".inventory-pagination-bar .pg-btn.on", "2"
    assert_select ".inventory-pagination-bar a[href*='page=1'][href*='q=SKU-PAG-']"
    assert_select ".inventory-pagination-bar a[href*='page=3'][href*='q=SKU-PAG-']"
    assert_select ".inventory-pagination-bar form[action='/erp/skus'] input[name='q'][value='SKU-PAG-']"
    assert_select ".inventory-pagination-bar .pagination-jump-input[value='2']"
  end

  test "index pagination preserves marketing filters" do
    12.times do |index|
      sku = Ec::Sku.create!(
        sku_code: format("SKU-GRD-%02d-%s", index, @token),
        product_name: "Grade 分页 SKU #{index}",
        is_active: true
      )
      Ec::SkuMarketingStateChange.new(
        sku: sku, grade: "B", stage: "new", changed_by: @current_user, note: "分页筛选"
      ).call
    end

    get "/erp/skus", params: { page: 2, grades: ["B"], stages: ["new"] }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-pagination-bar .pagination-chip", "第 2/2 页"
    assert_select ".inventory-pagination-bar a[href*='page=1'][href*='grades%5B%5D=B'][href*='stages%5B%5D=new']"
    assert_select ".inventory-pagination-bar form[action='/erp/skus'] input[name='grades[]'][value='B']"
    assert_select ".inventory-pagination-bar form[action='/erp/skus'] input[name='stages[]'][value='new']"
  end

  test "index jump pagination clamps and falls back to current page" do
    22.times do |index|
      Ec::Sku.create!(
        sku_code: format("SKU-JMP-%02d-%s", index, @token),
        product_name: "跳页 SKU #{index}",
        is_active: true
      )
    end

    get "/erp/skus",
        params: { page: 2, current_page: 2, jump_page: 99, q: "SKU-JMP-" },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-pagination-bar .pagination-chip", "第 3/3 页"
    assert_select ".inventory-pagination-bar", /显示第 21-22 条，共 22 条/

    sign_in @current_user
    get "/erp/skus",
        params: { page: 2, current_page: 2, jump_page: "bad", q: "SKU-JMP-" },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-pagination-bar .pagination-chip", "第 2/3 页"
    assert_select ".inventory-pagination-bar", /显示第 11-20 条，共 22 条/
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
    assert_select "input[name='ec_sku[sku_code]'][readonly='readonly'][value=?]", @sku.sku_code
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

  test "modal edit renders developer assignment selector" do
    developer = User.create!(
      email: "erp-skus-#{@token.downcase}-modal-developer@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "弹框开发 #{@token}"
    )
    Ec::SkuDeveloperAssignment.create!(sku: @sku, user: developer)

    get "/erp/skus/#{@sku.id}/developer/edit", headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "编辑开发人员"
    assert_select ".erp-modal__subtitle", text: @sku.sku_code
    assert_select "form[action='#{erp_sku_developer_path(@sku, return_to: nil)}'][data-turbo-frame='_top']"
    assert_select "input[type='hidden'][name='developer_user_id'][value=?]", developer.id.to_s
    assert_select "#sku-developer-assignment-#{@sku.id}-trigger", text: developer.display_name
    assert_select ".responsible-user-filter__option.is-selected[data-value='#{developer.id}'] .responsible-user-filter__name", text: developer.display_name
    assert_select ".responsible-user-filter__option--shortcut[data-value='']", text: "解除绑定"
    assert_select "button[type='submit']", text: "保存开发人员"
  ensure
    Ec::SkuDeveloperAssignment.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuDeveloperAssignment)
  end

  test "update developer assignment keeps only selected user" do
    old_developer = User.create!(
      email: "erp-skus-#{@token.downcase}-old-developer@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "旧开发 #{@token}"
    )
    extra_developer = User.create!(
      email: "erp-skus-#{@token.downcase}-extra-developer@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "额外开发 #{@token}"
    )
    new_developer = User.create!(
      email: "erp-skus-#{@token.downcase}-new-developer@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "新开发 #{@token}"
    )
    Ec::SkuDeveloperAssignment.create!(sku: @sku, user: old_developer)
    Ec::SkuDeveloperAssignment.create!(sku: @sku, user: extra_developer)

    patch "/erp/skus/#{@sku.id}/developer", params: {
      developer_user_id: new_developer.id,
      return_to: "/erp/skus?q=#{@sku.sku_code}"
    }

    assert_redirected_to "/erp/skus?q=#{@sku.sku_code}"
    assert_equal [new_developer.id], @sku.reload.developer_ids
  ensure
    Ec::SkuDeveloperAssignment.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuDeveloperAssignment)
  end

  test "update developer assignment clears selected user when blank" do
    developer = User.create!(
      email: "erp-skus-#{@token.downcase}-clear-developer@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "清空开发 #{@token}"
    )
    Ec::SkuDeveloperAssignment.create!(sku: @sku, user: developer)

    patch "/erp/skus/#{@sku.id}/developer", params: { developer_user_id: "" }

    assert_redirected_to "/erp/skus"
    assert_empty @sku.reload.developer_ids
  ensure
    Ec::SkuDeveloperAssignment.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuDeveloperAssignment)
  end

  test "modal edit renders operator assignment selector" do
    operator = User.create!(
      email: "erp-skus-#{@token.downcase}-modal-operator@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "弹框运营 #{@token}"
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "SKU 运营弹框店 #{@token}",
      company_type: "general",
      is_active: true
    )
    sku_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: store,
      product_id: "SKU-OP-MODAL-P-#{@token}",
      platform_sku_id: "SKU-OP-MODAL-PS-#{@token}",
      product_name: "SKU 运营弹框商品 #{@token}"
    )
    Ec::SkuProductOperator.create!(sku_product: sku_product, user: operator)

    get "/erp/skus/#{@sku.id}/operator/edit", headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "编辑运营人员"
    assert_select ".erp-modal__subtitle", text: @sku.sku_code
    assert_select "form[action='#{erp_sku_operator_path(@sku, return_to: nil)}'][data-turbo-frame='_top']"
    assert_select "input[type='hidden'][name='operator_user_id'][value=?]", operator.id.to_s
    assert_select "#sku-operator-assignment-#{@sku.id}-trigger", text: operator.display_name
    assert_select ".responsible-user-filter__option.is-selected[data-value='#{operator.id}'] .responsible-user-filter__name", text: operator.display_name
    assert_select ".responsible-user-filter__option--shortcut[data-value='']", text: "解除绑定"
    assert_select "button[type='submit']", text: "保存运营人员"
  ensure
    Ec::SkuProductOperator.where(sku_product_id: sku_product&.id).delete_all if defined?(Ec::SkuProductOperator) && defined?(sku_product)
    sku_product&.destroy
    store&.destroy
  end

  test "modal edit asks to bind products before assigning operator when sku has none" do
    get "/erp/skus/#{@sku.id}/operator/edit", headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "编辑运营人员"
    assert_select ".form-hint", text: "请先为这个 SKU 绑定平台商品，再设置运营人员。"
    assert_select "a.btn[href='#{erp_sku_sku_products_path(@sku)}'][data-turbo-frame='_top']", text: "平台商品绑定"
    assert_select "form[action='#{erp_sku_operator_path(@sku, return_to: nil)}']", count: 0
  end

  test "update operator assignment alerts when sku has no products" do
    operator = User.create!(
      email: "erp-skus-#{@token.downcase}-missing-product-operator@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "缺少绑定运营 #{@token}"
    )

    patch "/erp/skus/#{@sku.id}/operator", params: {
      operator_user_id: operator.id,
      return_to: "/erp/skus?q=#{@sku.sku_code}"
    }

    assert_redirected_to "/erp/skus?q=#{@sku.sku_code}"
    assert_equal "请先为这个 SKU 绑定平台商品，再设置运营人员。", flash[:alert]
  end

  test "update operator assignment keeps selected user on every sku product" do
    old_operator = User.create!(
      email: "erp-skus-#{@token.downcase}-old-operator@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "旧运营 #{@token}"
    )
    extra_operator = User.create!(
      email: "erp-skus-#{@token.downcase}-extra-operator@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "额外运营 #{@token}"
    )
    new_operator = User.create!(
      email: "erp-skus-#{@token.downcase}-new-operator@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "新运营 #{@token}"
    )
    store_a = Ec::Store.create!(
      platform: "ozon",
      store_name: "SKU 运营店 A #{@token}",
      company_type: "general",
      is_active: true
    )
    store_b = Ec::Store.create!(
      platform: "wb",
      store_name: "SKU 运营店 B #{@token}",
      company_type: "general",
      is_active: true
    )
    product_a = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: store_a,
      product_id: "SKU-OP-A-#{@token}",
      platform_sku_id: "SKU-OP-PS-A-#{@token}",
      product_name: "SKU 运营商品 A #{@token}"
    )
    product_b = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: store_b,
      product_id: "SKU-OP-B-#{@token}",
      platform_sku_id: "SKU-OP-PS-B-#{@token}",
      product_name: "SKU 运营商品 B #{@token}"
    )
    Ec::SkuProductOperator.create!(sku_product: product_a, user: old_operator)
    Ec::SkuProductOperator.create!(sku_product: product_a, user: extra_operator)
    Ec::SkuProductOperator.create!(sku_product: product_b, user: old_operator)

    patch "/erp/skus/#{@sku.id}/operator", params: {
      operator_user_id: new_operator.id,
      return_to: "/erp/skus?q=#{@sku.sku_code}"
    }

    assert_redirected_to "/erp/skus?q=#{@sku.sku_code}"
    assert_equal [new_operator.id], product_a.reload.operator_ids
    assert_equal [new_operator.id], product_b.reload.operator_ids
  ensure
    Ec::SkuProductOperator.where(sku_product_id: [product_a&.id, product_b&.id].compact).delete_all if defined?(Ec::SkuProductOperator)
    product_a&.destroy
    product_b&.destroy
    store_a&.destroy
    store_b&.destroy
  end

  test "update operator assignment clears every sku product when blank" do
    operator = User.create!(
      email: "erp-skus-#{@token.downcase}-clear-operator@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "清空运营 #{@token}"
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "SKU 清空运营店 #{@token}",
      company_type: "general",
      is_active: true
    )
    product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: store,
      product_id: "SKU-OP-CLEAR-#{@token}",
      platform_sku_id: "SKU-OP-CLEAR-PS-#{@token}",
      product_name: "SKU 清空运营商品 #{@token}"
    )
    Ec::SkuProductOperator.create!(sku_product: product, user: operator)

    patch "/erp/skus/#{@sku.id}/operator", params: { operator_user_id: "" }

    assert_redirected_to "/erp/skus"
    assert_empty product.reload.operator_ids
  ensure
    Ec::SkuProductOperator.where(sku_product_id: product&.id).delete_all if defined?(Ec::SkuProductOperator) && defined?(product)
    product&.destroy
    store&.destroy
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

  test "update rejects sku code changes" do
    patch "/erp/skus/#{@sku.id}", params: {
      ec_sku: {
        sku_code: "RENAMED-#{@token}"
      }
    }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :unprocessable_entity
    assert_select ".error-box", text: /SKU编码 创建后不可修改/
    assert_equal "SKU-PAGE-#{@token}", @sku.reload.sku_code
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

  private

  def platform_category_source_id(suffix)
    "#{@token}-#{suffix}"
  end

  def platform_category_source_ids
    %w[parent child other-parent other-child].map { |suffix| platform_category_source_id(suffix) }
  end
end
