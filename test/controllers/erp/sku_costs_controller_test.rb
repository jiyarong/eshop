require "test_helper"

class Erp::SkuCostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-sku-costs-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @platform_category_parent = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: platform_category_source_id("parent"),
      origin_name: "Cost Parent #{@token}",
      origin_language: "en",
      name_cn: "成本父类 #{@token}",
      name_en: "Cost Parent #{@token}"
    )
    @platform_category_child = Ec::Category.create!(
      source: "test",
      source_type: "subject",
      source_id: platform_category_source_id("child"),
      parent: @platform_category_parent,
      origin_name: "Cost Child #{@token}",
      origin_language: "en",
      name_cn: "成本子类 #{@token}",
      name_en: "Cost Child #{@token}"
    )
    @master_sku = Ec::MasterSku.create!(
      master_sku_code: "ERP-COST-SPU-#{@token}",
      product_name: "成本维护 SPU",
      ec_category: @platform_category_child
    )
    @sku = Ec::Sku.create!(master_sku: @master_sku, sku_code: "ERP-COST-#{@token}", product_name: "成本维护 SKU")
    @cost = Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      effective_on: Date.new(2025, 1, 1),
      purchase_price_cny: 10,
      freight_to_by_cny: 2,
      customs_misc_cny: 1,
      customs_duty_rate: 0.1,
      import_vat_rate: 0.2
    )
  end

  teardown do
    sku_codes = Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").pluck(:sku_code)
    Ec::SkuDeveloperAssignment.where(sku_code: sku_codes).delete_all if defined?(Ec::SkuDeveloperAssignment)
    if defined?(Ec::SkuProductOperator)
      Ec::SkuProductOperator.joins(:sku_product).where(ec_sku_products: { sku_code: sku_codes }).delete_all
    end
    Ec::SkuProduct.where(sku_code: sku_codes).delete_all if defined?(Ec::SkuProduct)
    Ec::Store.where("store_name LIKE ?", "%#{@token}%").delete_all if defined?(Ec::Store)
    Ec::SkuCost.where(sku_code: sku_codes).delete_all
    Ec::SkuDimension.where(sku_code: sku_codes).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku_codes).delete_all
    Ec::MasterSku.where("master_sku_code LIKE ?", "%#{@token}%").delete_all
    Ec::Category.where(source: "test", source_id: platform_category_source_ids).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-sku-costs-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-sku-costs-#{@token.downcase}%").delete_all
  end

  test "index renders sku cost maintenance table" do
    get "/erp/sku_costs", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU 成本维护"
    assert_select "#sku-cost-spu-sku-filter-trigger", text: "全部 SPU/SKU"
    assert_select ".category-multiselect__trigger", text: "全部类别"
    assert_select ".category-multiselect input[name='category_ids[]'][value=?]", @platform_category_child.id.to_s
    assert_select ".spu-sku-filter__spu-column"
    assert_select ".spu-sku-filter__sku-column"
    assert_select "#sku-cost-responsible-user-filter-developer-trigger", text: "全部开发人员"
    assert_select "#sku-cost-responsible-user-filter-operator-trigger", text: "全部运营人员"
    assert_select "input[type='checkbox'][name='master_sku_ids[]'][value=?]", @master_sku.id.to_s
    assert_select "input[type='checkbox'][name='sku_codes[]'][value=?]", @sku.sku_code
    assert_select "td", @sku.sku_code
    assert_select "th", "生效日期"
    assert_select "th", "采购价 CNY"
    assert_select "a[href*='/erp/sku_costs/new']", "新增成本"
    assert_select "turbo-frame#sku_cost_#{@sku.sku_code}_purchase_price_cny_cell"
  end

  test "index filters sku costs by selected spu" do
    other_sku = Ec::Sku.create!(sku_code: "ERP-COST-OTHER-#{@token}", product_name: "其他成本 SKU")

    get "/erp/sku_costs", params: { master_sku_ids: [@master_sku.id] }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "#sku-cost-spu-sku-filter-trigger", text: @master_sku.master_sku_code
    assert_select "input[type='checkbox'][name='master_sku_ids[]'][value=?][checked='checked']", @master_sku.id.to_s
    assert_select "td", @sku.sku_code
    assert_select ".prod-tbl tbody tr.sku-row td:first-child", { text: other_sku.sku_code, count: 0 }
  end

  test "index filters sku costs by master sku category" do
    other_parent = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: platform_category_source_id("other-parent"),
      origin_name: "Other Cost Parent #{@token}",
      origin_language: "en",
      name_cn: "其他成本父类 #{@token}",
      name_en: "Other Cost Parent #{@token}"
    )
    other_child = Ec::Category.create!(
      source: "test",
      source_type: "subject",
      source_id: platform_category_source_id("other-child"),
      parent: other_parent,
      origin_name: "Other Cost Child #{@token}",
      origin_language: "en",
      name_cn: "其他成本子类 #{@token}",
      name_en: "Other Cost Child #{@token}"
    )
    other_master_sku = Ec::MasterSku.create!(
      master_sku_code: "ERP-COST-SPU-OTHER-#{@token}",
      product_name: "其他成本 SPU",
      ec_category: other_child
    )
    other_sku = Ec::Sku.create!(
      master_sku: other_master_sku,
      sku_code: "ERP-COST-OTHER-#{@token}",
      product_name: "其他成本 SKU"
    )

    get "/erp/sku_costs", params: { category_ids: [@platform_category_child.id] }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".category-multiselect__trigger", text: "成本父类 #{@token} / 成本子类 #{@token}"
    assert_select ".category-multiselect input[name='category_ids[]'][value=?][checked='checked']", @platform_category_child.id.to_s
    assert_select "td", @sku.sku_code
    assert_select ".prod-tbl tbody tr.sku-row td:first-child", { text: other_sku.sku_code, count: 0 }
  end

  test "index filters sku costs by responsible users" do
    developer = User.create!(
      email: "erp-sku-costs-#{@token.downcase}-developer@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    operator = User.create!(
      email: "erp-sku-costs-#{@token.downcase}-operator@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "成本筛选店 #{@token}",
      company_type: "general",
      is_active: true
    )
    sku_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: store,
      product_id: "COST-FILTER-P-#{@token}",
      platform_sku_id: "COST-FILTER-PS-#{@token}",
      product_name: "成本筛选平台商品 #{@token}"
    )
    other_sku = Ec::Sku.create!(
      sku_code: "ERP-COST-RESP-OTHER-#{@token}",
      product_name: "其他负责人 SKU"
    )
    Ec::SkuDeveloperAssignment.create!(sku: @sku, user: developer)
    Ec::SkuProductOperator.create!(sku_product: sku_product, user: operator)

    get "/erp/sku_costs", params: { developer_id: developer.id, operator_id: operator.id }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[type='hidden'][name='developer_id'][value=?]", developer.id.to_s
    assert_select "input[type='hidden'][name='operator_id'][value=?]", operator.id.to_s
    assert_select "#sku-cost-responsible-user-filter-developer-trigger", text: developer.display_name
    assert_select "#sku-cost-responsible-user-filter-operator-trigger", text: operator.display_name
    assert_select "td", @sku.sku_code
    assert_select ".prod-tbl tbody tr.sku-row td:first-child", { text: other_sku.sku_code, count: 0 }
  end

  test "index paginates sku cost maintenance table" do
    prefix = "ERP-COST-PAG-#{@token}"
    24.times do |index|
      Ec::Sku.create!(sku_code: "#{prefix}-#{format("%02d", index)}", product_name: "成本分页 #{index}")
    end

    sign_in @current_user
    get "/erp/sku_costs", params: { sku: prefix }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".product-management.sku-management"
    assert_select ".product-filter-card"
    assert_select ".product-list-card table.prod-tbl"
    assert_select "tbody tr.sku-row", 10
    assert_select ".inventory-pagination-bar"
    assert_select ".inventory-pagination-bar .pagination-chip", "第 1/3 页"
    assert_select ".inventory-pagination-bar", /显示第 1-10 条，共 24 条/
    assert_select ".inventory-pagination-bar .pg-btn", "2"

    sign_in @current_user
    get "/erp/sku_costs", params: { sku: prefix, page: 2 }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-pagination-bar .pagination-chip", "第 2/3 页"
    assert_select ".inventory-pagination-bar", /显示第 11-20 条，共 24 条/
    assert_select ".inventory-pagination-bar .pg-btn.on", "2"
    assert_select ".inventory-pagination-bar a[href*='page=1'][href*='sku=ERP-COST-PAG-']"
    assert_select ".inventory-pagination-bar a[href*='page=3'][href*='sku=ERP-COST-PAG-']"
    assert_select ".inventory-pagination-bar form[action='/erp/sku_costs'] input[name='sku'][value='#{prefix}']"
  end

  test "inline update persists existing sku cost field" do
    patch "/erp/sku_costs/#{@sku.sku_code}",
      params: {
        inline_field: "purchase_price_cny",
        inline_context: {
          frame_id: "sku_cost_#{@sku.sku_code}_purchase_price_cny_cell"
        },
        ec_sku_cost: {
          purchase_price_cny: "12.50"
        }
      },
      headers: {
        "Accept" => "text/vnd.turbo-stream.html"
      }

    assert_response :success
    assert_equal BigDecimal("12.5"), @cost.reload.purchase_price_cny
    assert_select "turbo-stream[action='replace'][target='sku_cost_#{@sku.sku_code}_purchase_price_cny_cell']" do
      assert_select "template", "12.50"
    end
    assert_select "turbo-stream[action='update'][target='global_toast']"
  end

  test "inline update creates missing sku cost record" do
    Ec::SkuCost.where(sku_code: @sku.sku_code).delete_all

    assert_difference "Ec::SkuCost.count", 1 do
      patch "/erp/sku_costs/#{@sku.sku_code}",
        params: {
          inline_field: "freight_to_by_cny",
          inline_context: {
            frame_id: "sku_cost_#{@sku.sku_code}_freight_to_by_cny_cell"
          },
          ec_sku_cost: {
            freight_to_by_cny: "3.75"
          }
        },
        headers: {
          "Accept" => "text/vnd.turbo-stream.html"
        }
    end

    assert_response :success
    cost = Ec::SkuCost.find_by!(sku_code: @sku.sku_code)
    assert_equal Date.current, cost.effective_on
    assert_equal BigDecimal("3.75"), cost.freight_to_by_cny
  end

  test "create adds another effective sku cost" do
    assert_difference "Ec::SkuCost.where(sku_code: @sku.sku_code).count", 1 do
      post "/erp/sku_costs",
        params: {
          ec_sku_cost: {
            sku_code: @sku.sku_code,
            effective_on: "2026-08-01",
            purchase_price_cny: "18.50",
            freight_to_by_cny: "4.25",
            customs_misc_cny: "1.00",
            customs_duty_rate: "0.10",
            import_vat_rate: "0.20",
            misc_cost_cny: "0.50",
            damage_rate: "0.01",
            memo: "new version"
          }
        },
        headers: { "Accept" => "text/html" }
    end

    assert_redirected_to "/erp/sku_costs"
    cost = Ec::SkuCost.find_by!(sku_code: @sku.sku_code, effective_on: Date.new(2026, 8, 1))
    assert_equal BigDecimal("18.5"), cost.purchase_price_cny
    assert_equal "new version", cost.memo
  end

  private

  def platform_category_source_id(suffix)
    "#{@token}-#{suffix}"
  end

  def platform_category_source_ids
    %w[parent child other-parent other-child].map { |suffix| platform_category_source_id(suffix) }
  end
end
