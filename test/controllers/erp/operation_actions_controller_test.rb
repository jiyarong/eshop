require "test_helper"

class Erp::OperationActionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("operation-actions-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @sku = Ec::Sku.create!(sku_code: "ACTION-UI-#{@token}", product_name: "Action UI SKU")
    @other_sku = Ec::Sku.create!(sku_code: "ACTION-OTHER-#{@token}", product_name: "Other SKU")
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "WB Action #{@token}", company_type: "small", is_active: true)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon Action #{@token}", company_type: "general", is_active: true)
    @wb_product = create_sku_product(@sku, @wb_store, "WB-P-#{@token}")
    @ozon_product = create_sku_product(@other_sku, @ozon_store, "OZON-P-#{@token}")
    @content_action = create_action(
      @wb_product,
      "listing_content",
      {
        "title" => { "from" => "Old title", "to" => "New title" },
        "images" => {
          "primary_from" => "old.jpg",
          "primary_to" => "new.jpg",
          "added" => ["new.jpg"],
          "removed" => ["old.jpg"]
        },
        "attributes" => {
          "85" => { "values" => { "removed" => ["Old brand"], "added" => ["New brand"] } }
        }
      }
    )
    @pricing_action = create_action(
      @ozon_product,
      "listing_pricing",
      { "price" => { "from" => "100.0", "to" => "90.0" } }
    )
  end

  teardown do
    Ec::OperationAction.where(ec_store_id: [@wb_store&.id, @ozon_store&.id].compact).delete_all
    Ec::SkuProduct.where(store_id: [@wb_store&.id, @ozon_store&.id].compact).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id].compact).delete_all
    Ec::Sku.with_deleted.where(id: [@sku&.id, @other_sku&.id].compact).delete_all
    UserRole.where(user_id: @current_user&.id).delete_all
    User.where(id: @current_user&.id).delete_all
  end

  test "index renders operation actions and structured diffs" do
    get "/erp/operation_actions", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "运营记录"
    assert_select "form[action='/erp/operation_actions'][method='get']"
    assert_select "select[name='operation_type']"
    assert_select "select[name='platform']"
    assert_select "input[name='sku']"
    assert_select ".operation-actions-table tbody tr.sku-row", 2
    assert_select "td", @sku.sku_code
    assert_select ".operation-action-field-chip", "标题"
    assert_select ".operation-action-field-chip", "图片"
    assert_select ".operation-action-diff-item h3", "属性 / 85 / values"
    assert_select ".operation-action-diff-value strong", "新增"
    assert_select ".erp-nav__link[href='/erp/operation_actions'][aria-current='page']", "运营记录"
  end

  test "index filters by operation type platform and sku" do
    get "/erp/operation_actions",
      params: { operation_type: "listing_content", platform: "wb", sku: @sku.sku_code },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "select[name='operation_type'] option[value='listing_content'][selected='selected']"
    assert_select "select[name='platform'] option[value='wb'][selected='selected']"
    assert_select "input[name='sku'][value=?]", @sku.sku_code
    assert_select ".operation-actions-table tbody tr.sku-row", 1
    assert_select "td", @sku.sku_code
    assert_select "td", { text: @other_sku.sku_code, count: 0 }
  end

  test "index paginates ten actions per page and preserves filters" do
    20.times do |index|
      create_action(
        @wb_product,
        "listing_content",
        { "title" => { "from" => "Old #{index}", "to" => "New #{index}" } },
        operated_at: index.minutes.ago
      )
    end

    sign_in @current_user
    get "/erp/operation_actions",
      params: { operation_type: "listing_content", platform: "wb", sku: @sku.sku_code },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".operation-actions-table tbody tr.sku-row", 10
    assert_select ".pagination-chip", "第 1/3 页"
    assert_select ".inventory-pagination-bar", /显示第 1-10 条，共 21 条/
    assert_select "a[href*='page=2'][href*='operation_type=listing_content'][href*='platform=wb']"
    assert_select ".pagination-jump form[action='/erp/operation_actions']", 0
    assert_select "form.pagination-jump[action='/erp/operation_actions'] input[name='operation_type'][value='listing_content']"
    assert_select "form.pagination-jump[action='/erp/operation_actions'] input[name='platform'][value='wb']"
    assert_select "form.pagination-jump[action='/erp/operation_actions'] input[name='sku'][value=?]", @sku.sku_code
    assert_select "form.pagination-jump[action='/erp/operation_actions'] input[name='jump_page']"

    sign_in @current_user
    get "/erp/operation_actions",
      params: { operation_type: "listing_content", platform: "wb", sku: @sku.sku_code, jump_page: 2 },
      headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".pagination-chip", "第 2/3 页"
    assert_select ".inventory-pagination-bar", /显示第 11-20 条，共 21 条/
  end

  private

  def create_sku_product(sku, store, product_id)
    Ec::SkuProduct.create!(sku: sku, store: store, product_id: product_id, offer_id: sku.sku_code)
  end

  def create_action(sku_product, operation_type, fields, operated_at: Time.current)
    Ec::OperationAction.create!(
      operation_type: operation_type,
      operated_by_user: @current_user,
      operated_at: operated_at,
      sku_product: sku_product,
      sku: sku_product.sku,
      store: sku_product.store,
      diff_result: {
        "platform" => sku_product.platform,
        "attribution" => "assigned_operator",
        "fields" => fields
      },
      record_by_system: true
    )
  end
end
