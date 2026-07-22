require "test_helper"

class Erp::SkuBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-batches-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @sku = Ec::Sku.create!(sku_code: "ERP-BATCH-#{@token}", product_name: "ERP 批次 SKU")
    @batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "ERP-BATCH-#{@token}",
      purchase_date: Date.new(2026, 6, 1),
      purchased_quantity: 100,
      received_quantity: 80,
      purchase_unit_price_cny: 12.5
    )
  end

  teardown do
    sku_scope = Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%")
    batch_ids = Ec::SkuBatch.where(sku_code: sku_scope.select(:sku_code)).pluck(:id)
    Ec::CostAllocationItem.where(sku_batch_id: batch_ids).delete_all
    Ec::PurchaseOrderItem.where(sku_batch_id: batch_ids).delete_all
    Ec::SkuBatch.where(id: batch_ids).delete_all
    Ec::SkuDeveloperAssignment.where(sku_code: sku_scope.select(:sku_code)).delete_all if defined?(Ec::SkuDeveloperAssignment)
    if defined?(Ec::SkuProductOperator)
      Ec::SkuProductOperator.joins(:sku_product).where(ec_sku_products: { sku_code: sku_scope.select(:sku_code) }).delete_all
    end
    Ec::SkuProduct.where(sku_code: sku_scope.select(:sku_code)).delete_all if defined?(Ec::SkuProduct)
    Ec::Store.where("store_name LIKE ?", "%#{@token}%").delete_all if defined?(Ec::Store)
    sku_scope.delete_all
    Ec::MasterSku.where("master_sku_code LIKE ?", "%#{@token}%").delete_all if defined?(Ec::MasterSku)
    Ec::Category.where(source: "test", source_id: platform_category_source_ids).delete_all if defined?(Ec::Category)
    UserRole.joins(:user).where("users.email LIKE ?", "erp-batches-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-batches-#{@token.downcase}%").delete_all
  end

  test "index renders sku batches" do
    get "/erp/sku_batches", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "批次管理"
    assert_select ".product-management.sku-management"
    assert_select ".product-page-actions a[href='#{erp_new_sku_batch_path(return_to: "/erp/sku_batches")}'][data-turbo-frame='erp_modal']", text: "新增批次"
    assert_select ".product-summary-grid[aria-label=?]", "批次概览"
    assert_select ".summary-label", "全部批次"
    assert_select ".card.product-filter-card form[action='/erp/sku_batches'][method='get']"
    assert_select "input[name='q'][placeholder=?]", "搜索 SKU、中文名或俄文名…"
    assert_select "input[name='batch_code'][placeholder=?]", "搜索批次号…"
    assert_select ".category-multiselect__trigger", text: "全部类别"
    assert_select "#sku-batch-spu-sku-filter-trigger", text: "全部 SPU/SKU"
    assert_select "#sku-batch-responsible-user-filter-developer-trigger", text: "全部开发人员"
    assert_select "#sku-batch-responsible-user-filter-operator-trigger", text: "全部运营人员"
    assert_select "input[type='hidden'][name='statuses[]'][value='']"
    assert_select "#sku-batch-status-filter-trigger", text: "已选 3 项"
    assert_select "input[type='checkbox'][name='statuses[]'][value='draft'][checked='checked']"
    assert_select "input[type='checkbox'][name='statuses[]'][value='ordered'][checked='checked']"
    assert_select "input[type='checkbox'][name='statuses[]'][value='in_transit'][checked='checked']"
    assert_select "input[type='checkbox'][name='statuses[]'][value='received'][checked='checked']", count: 0
    assert_select "input[type='checkbox'][name='statuses[]'][value='closed'][checked='checked']", count: 0
    assert_select ".prod-tbl thead th", text: "批次号"
    assert_select ".prod-tbl thead th", text: "SKU"
    assert_select ".prod-tbl thead th", text: "商品名"
    assert_select ".prod-tbl thead th", text: "采购日期"
    assert_select ".prod-tbl thead th", text: "出境日期"
    assert_select ".prod-tbl thead th", text: "境外交付日期"
    assert_select ".prod-tbl thead th", text: "采购数量"
    assert_select ".prod-tbl thead th", text: "到货数量"
    assert_select "turbo-frame#sku_batch_#{@batch.id}_batch_code_cell .inline-edit-cell--display", text: @batch.batch_code
    assert_select "a[href='#{erp_sku_path(@sku)}']", text: @sku.sku_code
    assert_select "turbo-frame#sku_batch_#{@batch.id}_purchase_date_cell .inline-edit-cell--display", text: "2026-06-01"
    assert_select "turbo-frame#sku_batch_#{@batch.id}_purchased_quantity_cell .inline-edit-cell--display", text: "100"
    assert_select "turbo-frame#sku_batch_#{@batch.id}_received_quantity_cell .inline-edit-cell--display", text: "80"
    assert_select "a[href='#{erp_sku_batch_path(@batch)}']", text: "查看"
    assert_select "a[href='#{erp_edit_sku_batch_path(@batch, return_to: "/erp/sku_batches")}'][data-turbo-frame='erp_modal']"
    assert_select "a[data-turbo-method='delete'][data-turbo-confirm=?][href=?]", "确认删除这个批次？", erp_sku_batch_path(@batch, return_to: "/erp/sku_batches"), minimum: 1
  end

  test "index localizes visible chrome in english" do
    get "/erp/sku_batches", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "Batch Management"
    assert_select ".product-page-actions a[href=?][data-turbo-frame='erp_modal']", erp_new_sku_batch_path(locale: "en", return_to: "/erp/sku_batches?locale=en"), "Add batch"
    assert_select ".product-summary-grid[aria-label=?]", "Batch overview"
    assert_select ".summary-label", "All batches"
    assert_select "input[placeholder=?]", "Search SKU, Chinese name, or Russian name..."
    assert_select "input[placeholder=?]", "Search batch number..."
    assert_select "#sku-batch-status-filter-trigger", text: "3 selected"
    assert_select "input[type='checkbox'][name='statuses[]'][value='draft'][checked='checked']"
    assert_select "input[type='checkbox'][name='statuses[]'][value='ordered'][checked='checked']"
    assert_select "input[type='checkbox'][name='statuses[]'][value='in_transit'][checked='checked']"
    assert_select "input[type='checkbox'][name='statuses[]'][value='closed'][checked='checked']", count: 0
    assert_select "th", "Batch number"
    assert_select "th", "SKU"
    assert_select "th", "Product name"
    assert_select "th", "Purchase date"
    assert_select "th", "Departure date"
    assert_select "th", "Overseas delivery date"
    assert_select "th", "Purchased quantity"
    assert_select "th", "Received quantity"
    assert_select "a[href='#{erp_sku_batch_path(@batch, locale: "en", return_to: "/erp/sku_batches?locale=en")}'][data-turbo-method='delete']", minimum: 1 do |links|
      assert_equal "Delete this batch?", links.first["data-turbo-confirm"]
    end
  end

  test "index filters batches by sku search batch code and status" do
    other_sku = Ec::Sku.create!(
      sku_code: "ERP-BATCH-OTHER-#{@token}",
      product_name: "其他批次 SKU",
      product_name_ru: "Другой SKU"
    )
    matched_batch = Ec::SkuBatch.create!(
      sku_code: other_sku.sku_code,
      batch_code: "ERP-FILTER-#{@token}",
      status: "received",
      purchase_date: Date.new(2026, 6, 3),
      purchased_quantity: 50,
      received_quantity: 50,
      purchase_unit_price_cny: 8.5
    )
    Ec::SkuBatch.create!(
      sku_code: other_sku.sku_code,
      batch_code: "ERP-FILTER-DRAFT-#{@token}",
      status: "draft",
      purchase_date: Date.new(2026, 6, 4),
      purchased_quantity: 60,
      received_quantity: 0,
      purchase_unit_price_cny: 9.5
    )

    get "/erp/sku_batches",
      params: { q: "其他批次", batch_code: "FILTER", statuses: ["received"] },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='q'][value=?]", "其他批次"
    assert_select "input[name='batch_code'][value=?]", "FILTER"
    assert_select "#sku-batch-status-filter-trigger", text: "已到货"
    assert_select "input[type='checkbox'][name='statuses[]'][value='received'][checked='checked']"
    assert_select "input[type='checkbox'][name='statuses[]'][value='draft'][checked='checked']", count: 0
    assert_select "tbody tr.sku-batch-row", 1
    assert_select "turbo-frame#sku_batch_#{matched_batch.id}_batch_code_cell", text: matched_batch.batch_code
    assert_select "turbo-frame#sku_batch_#{@batch.id}_batch_code_cell", count: 0
  end

  test "index filters batches by category spu sku and responsible users" do
    platform_category_parent = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: platform_category_source_id("parent"),
      origin_name: "Batch Parent #{@token}",
      origin_language: "en",
      name_cn: "批次父类 #{@token}",
      name_en: "Batch Parent #{@token}"
    )
    platform_category_child = Ec::Category.create!(
      source: "test",
      source_type: "subject",
      source_id: platform_category_source_id("child"),
      parent: platform_category_parent,
      origin_name: "Batch Child #{@token}",
      origin_language: "en",
      name_cn: "批次子类 #{@token}",
      name_en: "Batch Child #{@token}"
    )
    master_sku = Ec::MasterSku.create!(
      master_sku_code: "ERP-BATCH-SPU-#{@token}",
      product_name: "批次 SPU #{@token}",
      ec_category: platform_category_child
    )
    matched_sku = Ec::Sku.create!(
      master_sku: master_sku,
      sku_code: "ERP-BATCH-FILTER-#{@token}",
      product_name: "批次筛选 SKU #{@token}"
    )
    matched_batch = Ec::SkuBatch.create!(
      sku_code: matched_sku.sku_code,
      batch_code: "ERP-BATCH-MATCH-#{@token}",
      status: "ordered",
      purchase_date: Date.new(2026, 6, 5),
      purchased_quantity: 70,
      received_quantity: 0,
      purchase_unit_price_cny: 10.5
    )
    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "ERP-BATCH-EXCLUDED-#{@token}",
      status: "ordered",
      purchase_date: Date.new(2026, 6, 6),
      purchased_quantity: 80,
      received_quantity: 0,
      purchase_unit_price_cny: 11.5
    )
    developer = User.create!(
      email: "erp-batches-#{@token.downcase}-developer@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "批次开发 #{@token}"
    )
    operator = User.create!(
      email: "erp-batches-#{@token.downcase}-operator@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "批次运营 #{@token}"
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "批次筛选店 #{@token}",
      company_type: "general",
      is_active: true
    )
    sku_product = Ec::SkuProduct.create!(
      sku_code: matched_sku.sku_code,
      store: store,
      product_id: "ERP-BATCH-P-#{@token}",
      platform_sku_id: "ERP-BATCH-PS-#{@token}",
      product_name: "批次筛选平台商品 #{@token}"
    )
    Ec::SkuDeveloperAssignment.create!(sku: matched_sku, user: developer)
    Ec::SkuProductOperator.create!(sku_product: sku_product, user: operator)

    get "/erp/sku_batches",
      params: {
        category_ids: [platform_category_child.id],
        master_sku_ids: [master_sku.id],
        developer_id: developer.id,
        operator_id: operator.id,
        statuses: ["ordered"]
      },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".category-multiselect__trigger", text: "批次父类 #{@token} / 批次子类 #{@token}"
    assert_select ".category-multiselect input[name='category_ids[]'][value=?][checked='checked']", platform_category_child.id.to_s
    assert_select "#sku-batch-spu-sku-filter-trigger", text: master_sku.master_sku_code
    assert_select "input[type='checkbox'][name='master_sku_ids[]'][value=?][checked='checked']", master_sku.id.to_s
    assert_select "input[type='hidden'][name='developer_id'][value=?]", developer.id.to_s
    assert_select "input[type='hidden'][name='operator_id'][value=?]", operator.id.to_s
    assert_select "#sku-batch-responsible-user-filter-developer-trigger", text: developer.display_name
    assert_select "#sku-batch-responsible-user-filter-operator-trigger", text: operator.display_name
    assert_select "tbody tr.sku-batch-row", 1
    assert_select "turbo-frame#sku_batch_#{matched_batch.id}_batch_code_cell", text: matched_batch.batch_code
    assert_select "turbo-frame#sku_batch_#{@batch.id}_batch_code_cell", count: 0
  end

  test "show renders batch cost summary" do
    get "/erp/sku_batches/#{@batch.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @batch.batch_code
    assert_select "dt", "单件批次成本"
  end

  test "show localizes visible chrome in english" do
    get "/erp/sku_batches/#{@batch.id}", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @batch.batch_code
    assert_select "a[href=?]", erp_edit_sku_batch_path(@batch, locale: "en"), "Edit"
    assert_select "dt", "Product name"
    assert_select "dt", "Purchase cost"
    assert_select "dt", "Allocated cost"
    assert_select "dt", "Unit batch cost"
  end

  test "new renders form" do
    get "/erp/sku_batches/new", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "新增 SKU 批次"
    assert_select "form[action='/erp/sku_batches']"
    assert_select "#sku-batch-form-spu-sku-selector-trigger", text: "选择 SKU"
    assert_select ".spu-sku-filter--single"
    assert_select "select[name='ec_sku_batch[sku_code]']", count: 0
    assert_select "input[type='radio'][name='ec_sku_batch[sku_code]'][value=?]", @sku.sku_code
    assert_select "input[name='master_sku_ids[]']", count: 0
    assert_select "input[name='ec_sku_batch[purchase_date]']"
  end

  test "modal new renders batch form with selected sku" do
    get "/erp/sku_batches/new", params: { sku_code: @sku.sku_code, return_to: "/erp/skus?status=active" }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "form[action='/erp/sku_batches'][data-turbo-frame='_top']"
    assert_select "#sku-batch-form-spu-sku-selector-trigger", text: @sku.sku_code
    assert_select "input[type='radio'][name='ec_sku_batch[sku_code]'][value=?][checked='checked']", @sku.sku_code
    assert_select "input[name='master_sku_ids[]']", count: 0
    assert_select "input[name='ec_sku_batch[purchase_date]']"
    assert_select "input[name='return_to'][value='/erp/skus?status=active']"
  end

  test "modal edit renders batch form" do
    get "/erp/sku_batches/#{@batch.id}/edit", params: { return_to: "/erp/skus?q=ERP" }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "编辑批次"
    assert_select "form[action='#{erp_sku_batch_path(@batch)}'][data-turbo-frame='_top']"
    assert_select "#sku-batch-form-spu-sku-selector-trigger", text: @sku.sku_code
    assert_select "input[type='radio'][name='ec_sku_batch[sku_code]'][value=?][checked='checked']", @sku.sku_code
    assert_select "input[name='ec_sku_batch[purchase_date]'][value=?]", @batch.purchase_date.to_s
    assert_select "input[name='return_to'][value='/erp/skus?q=ERP']"
  end

  test "batch modal form localizes visible chrome in english" do
    get "/erp/sku_batches/#{@batch.id}/edit", params: { locale: "en" }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "h2", "Edit batch"
    assert_select "button[aria-label=?]", "Close"
    assert_select "label", "Batch number"
    assert_select "label", "Status"
    assert_select "label", "Purchase date"
    assert_select "label", "Expected arrival"
    assert_select "label", "Actual arrival"
    assert_select "input[type='submit'][value=?]", "Save"
  end

  test "create batch returns to supplied page context" do
    assert_difference "Ec::SkuBatch.count", 1 do
      post "/erp/sku_batches", params: {
        return_to: "/erp/skus?status=active&q=batch",
        ec_sku_batch: {
          sku_code: @sku.sku_code,
          batch_code: "created-batch-#{@token}",
          status: "ordered",
          purchase_date: "2026-06-10",
          purchased_quantity: "120",
          received_quantity: "20",
          purchase_unit_price_cny: "11.5",
          expected_arrival_on: "2026-06-15",
          memo: "手动录入"
        }
      }
    end

    created = Ec::SkuBatch.find_by!(batch_code: "CREATED-BATCH-#{@token}")
    assert_redirected_to "/erp/skus?status=active&q=batch"
    assert_equal "ordered", created.status
    assert_equal Date.new(2026, 6, 10), created.purchase_date
    assert_equal 120, created.purchased_quantity
  end

  test "invalid modal create rerenders batch form" do
    post "/erp/sku_batches", params: {
      ec_sku_batch: {
        sku_code: "",
        batch_code: "",
        purchased_quantity: "120",
        purchase_unit_price_cny: "11.5"
      }
    }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select ".error-box"
  end

  test "edit and update batch returns to supplied page context" do
    get "/erp/sku_batches/#{@batch.id}/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "编辑 SKU 批次"

    sign_in @current_user
    patch "/erp/sku_batches/#{@batch.id}", params: {
      return_to: "/erp/skus?status=inactive",
      ec_sku_batch: {
        status: "received",
        purchase_date: "2026-06-02",
        received_quantity: "100",
        received_on: "2026-06-20"
      }
    }

    assert_redirected_to "/erp/skus?status=inactive"
    @batch.reload
    assert_equal "received", @batch.status
    assert_equal Date.new(2026, 6, 2), @batch.purchase_date
    assert_equal 100, @batch.received_quantity
    assert_equal Date.new(2026, 6, 20), @batch.received_on
  end

  test "inline update persists purchase date" do
    patch "/erp/sku_batches/#{@batch.id}",
      params: {
        inline_field: "purchase_date",
        inline_context: {
          frame_id: "sku_batch_#{@batch.id}_purchase_date_cell"
        },
        ec_sku_batch: {
          purchase_date: "2026-06-11"
        }
      },
      headers: {
        "Accept" => "text/vnd.turbo-stream.html"
      }

    assert_response :success
    @batch.reload
    assert_equal Date.new(2026, 6, 11), @batch.purchase_date
    assert_select "turbo-stream[action='replace'][target='sku_batch_#{@batch.id}_purchase_date_cell']" do
      assert_select "template", "2026-06-11"
    end
  end

  test "destroy batch returns to sku list" do
    assert_difference "Ec::SkuBatch.count", -1 do
      delete "/erp/sku_batches/#{@batch.id}"
    end

    assert_redirected_to "/erp/skus"
  end

  test "invalid modal update rerenders batch form" do
    patch "/erp/sku_batches/#{@batch.id}", params: {
      ec_sku_batch: {
        batch_code: "",
        purchased_quantity: "100"
      }
    }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "编辑批次"
    assert_select ".error-box"
  end

  test "inline update returns turbo stream cell and feedback on success" do
    patch "/erp/sku_batches/#{@batch.id}",
      params: {
        inline_field: "status",
        inline_context: {
          frame_id: "sku_batch_#{@batch.id}_status_cell"
        },
        ec_sku_batch: {
          status: "received"
        }
      },
      headers: {
        "Accept" => "text/vnd.turbo-stream.html"
      }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type

    @batch.reload
    assert_equal "received", @batch.status
    assert_includes response.body, %(target="sku_batch_#{@batch.id}_status_cell")
    assert_select "turbo-stream[action='replace'][target='sku_batch_#{@batch.id}_status_cell']" do
      assert_select "template", I18n.t("erp.sku_batches.statuses.received")
    end
    assert_includes response.body, I18n.t("erp.sku_batches.statuses.received")
    assert_includes response.body, %(target="global_toast")
    assert_select "turbo-stream[action='update'][target='global_toast']" do
      assert_select "template .global-toast.global-toast--success", I18n.t("erp.inline_edit.messages.saved")
      assert_select "template .global-toast.error-box", 0
    end
  end

  test "inline update keeps edit state and feedback on failure" do
    patch "/erp/sku_batches/#{@batch.id}",
      params: {
        inline_field: "batch_code",
        inline_context: {
          frame_id: "sku_batch_#{@batch.id}_batch_code_cell"
        },
        ec_sku_batch: {
          batch_code: ""
        }
      },
      headers: {
        "Accept" => "text/vnd.turbo-stream.html"
      }

    assert_response :unprocessable_entity
    assert_equal "text/vnd.turbo-stream.html", response.media_type

    @batch.reload
    assert_equal "ERP-BATCH-#{@token}", @batch.batch_code
    assert_includes response.body, %(target="sku_batch_#{@batch.id}_batch_code_cell")
    assert_select "turbo-stream[action='replace'][target='sku_batch_#{@batch.id}_batch_code_cell']" do
      assert_select "template form" do
        assert_select "input[name='ec_sku_batch[batch_code]']"
        assert_select ".error-box", /.+/
      end
    end
    assert_includes response.body, %(target="global_toast")
    assert_includes response.body, "error-box"
    assert_select "turbo-stream[action='update'][target='global_toast']" do
      assert_select "template .global-toast.global-toast--error.error-box", I18n.t("erp.inline_edit.messages.save_failed")
    end
  end

  def platform_category_source_id(suffix)
    "#{@token}-#{suffix}"
  end

  def platform_category_source_ids
    %w[parent child other-parent other-child].map { |suffix| platform_category_source_id(suffix) }
  end
end
