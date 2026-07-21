require "test_helper"

class Erp::SkuDimensionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-sku-dimensions-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @platform_category_parent = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: platform_category_source_id("parent"),
      origin_name: "Dimension Parent #{@token}",
      origin_language: "en",
      name_cn: "尺寸父类 #{@token}",
      name_en: "Dimension Parent #{@token}"
    )
    @platform_category_child = Ec::Category.create!(
      source: "test",
      source_type: "subject",
      source_id: platform_category_source_id("child"),
      parent: @platform_category_parent,
      origin_name: "Dimension Child #{@token}",
      origin_language: "en",
      name_cn: "尺寸子类 #{@token}",
      name_en: "Dimension Child #{@token}"
    )
    @master_sku = Ec::MasterSku.create!(
      master_sku_code: "ERP-DIM-SPU-#{@token}",
      product_name: "尺寸维护 SPU",
      ec_category: @platform_category_child
    )
    @sku = Ec::Sku.create!(master_sku: @master_sku, sku_code: "ERP-DIM-#{@token}", product_name: "尺寸维护 SKU")
    @dimension = Ec::SkuDimension.create!(
      sku_code: @sku.sku_code,
      inner_length_cm: 10,
      inner_width_cm: 20,
      inner_height_cm: 30,
      inner_box_weight_kg: 1.25,
      outer_box_weight_kg: 8.5,
      outer_box_pcs: 6
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
    UserRole.joins(:user).where("users.email LIKE ?", "erp-sku-dimensions-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-sku-dimensions-#{@token.downcase}%").delete_all
  end

  test "index renders sku dimension maintenance table" do
    get "/erp/sku_dimensions", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU 尺寸维护"
    assert_select "#sku-dimension-spu-sku-filter-trigger", text: "全部 SPU/SKU"
    assert_select ".category-multiselect__trigger", text: "全部类别"
    assert_select ".category-multiselect input[name='category_ids[]'][value=?]", @platform_category_child.id.to_s
    assert_select "#sku-dimension-responsible-user-filter-developer-trigger", text: "全部开发人员"
    assert_select "#sku-dimension-responsible-user-filter-operator-trigger", text: "全部运营人员"
    assert_select "input[type='checkbox'][name='master_sku_ids[]'][value=?]", @master_sku.id.to_s
    assert_select "input[type='checkbox'][name='sku_codes[]'][value=?]", @sku.sku_code
    assert_select "td", @sku.sku_code
    assert_select "th", "内长 cm"
    assert_select "th", "外长 cm"
    assert_select "th", "内箱重量 kg"
    assert_select "th", "外箱重量 kg"
    assert_select "th", "外箱 pcs"
    assert_select "turbo-frame#sku_dimension_#{@sku.sku_code}_inner_length_cm_cell"
  end

  test "index filters sku dimensions by selected sku code" do
    other_sku = Ec::Sku.create!(sku_code: "ERP-DIM-OTHER-#{@token}", product_name: "其他尺寸 SKU")

    get "/erp/sku_dimensions", params: { sku_codes: [@sku.sku_code] }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "#sku-dimension-spu-sku-filter-trigger", text: @sku.sku_code
    assert_select "input[type='checkbox'][name='sku_codes[]'][value=?][checked='checked']", @sku.sku_code
    assert_select "td", @sku.sku_code
    assert_select ".prod-tbl tbody tr.sku-row td:first-child", { text: other_sku.sku_code, count: 0 }
  end

  test "index filters sku dimensions by master sku category" do
    other_parent = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: platform_category_source_id("other-parent"),
      origin_name: "Other Dimension Parent #{@token}",
      origin_language: "en",
      name_cn: "其他尺寸父类 #{@token}",
      name_en: "Other Dimension Parent #{@token}"
    )
    other_child = Ec::Category.create!(
      source: "test",
      source_type: "subject",
      source_id: platform_category_source_id("other-child"),
      parent: other_parent,
      origin_name: "Other Dimension Child #{@token}",
      origin_language: "en",
      name_cn: "其他尺寸子类 #{@token}",
      name_en: "Other Dimension Child #{@token}"
    )
    other_master_sku = Ec::MasterSku.create!(
      master_sku_code: "ERP-DIM-SPU-OTHER-#{@token}",
      product_name: "其他尺寸 SPU",
      ec_category: other_child
    )
    other_sku = Ec::Sku.create!(
      master_sku: other_master_sku,
      sku_code: "ERP-DIM-OTHER-#{@token}",
      product_name: "其他尺寸 SKU"
    )

    get "/erp/sku_dimensions", params: { category_ids: [@platform_category_child.id] }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".category-multiselect__trigger", text: "尺寸父类 #{@token} / 尺寸子类 #{@token}"
    assert_select ".category-multiselect input[name='category_ids[]'][value=?][checked='checked']", @platform_category_child.id.to_s
    assert_select "td", @sku.sku_code
    assert_select ".prod-tbl tbody tr.sku-row td:first-child", { text: other_sku.sku_code, count: 0 }
  end

  test "index filters sku dimensions by responsible users" do
    developer = User.create!(
      email: "erp-sku-dimensions-#{@token.downcase}-developer@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    operator = User.create!(
      email: "erp-sku-dimensions-#{@token.downcase}-operator@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "尺寸筛选店 #{@token}",
      company_type: "general",
      is_active: true
    )
    sku_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: store,
      product_id: "DIM-FILTER-P-#{@token}",
      platform_sku_id: "DIM-FILTER-PS-#{@token}",
      product_name: "尺寸筛选平台商品 #{@token}"
    )
    other_sku = Ec::Sku.create!(
      sku_code: "ERP-DIM-RESP-OTHER-#{@token}",
      product_name: "其他负责人 SKU"
    )
    Ec::SkuDeveloperAssignment.create!(sku: @sku, user: developer)
    Ec::SkuProductOperator.create!(sku_product: sku_product, user: operator)

    get "/erp/sku_dimensions", params: { developer_id: developer.id, operator_id: operator.id }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[type='hidden'][name='developer_id'][value=?]", developer.id.to_s
    assert_select "input[type='hidden'][name='operator_id'][value=?]", operator.id.to_s
    assert_select "#sku-dimension-responsible-user-filter-developer-trigger", text: developer.display_name
    assert_select "#sku-dimension-responsible-user-filter-operator-trigger", text: operator.display_name
    assert_select "td", @sku.sku_code
    assert_select ".prod-tbl tbody tr.sku-row td:first-child", { text: other_sku.sku_code, count: 0 }
  end

  test "index paginates sku dimension maintenance table" do
    prefix = "ERP-DIM-PAG-#{@token}"
    24.times do |index|
      Ec::Sku.create!(sku_code: "#{prefix}-#{format("%02d", index)}", product_name: "尺寸分页 #{index}")
    end

    sign_in @current_user
    get "/erp/sku_dimensions", params: { sku: prefix }, headers: { "Accept" => "text/html" }

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
    get "/erp/sku_dimensions", params: { sku: prefix, page: 2 }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-pagination-bar .pagination-chip", "第 2/3 页"
    assert_select ".inventory-pagination-bar", /显示第 11-20 条，共 24 条/
    assert_select ".inventory-pagination-bar .pg-btn.on", "2"
    assert_select ".inventory-pagination-bar a[href*='page=1'][href*='sku=ERP-DIM-PAG-']"
    assert_select ".inventory-pagination-bar a[href*='page=3'][href*='sku=ERP-DIM-PAG-']"
    assert_select ".inventory-pagination-bar form[action='/erp/sku_dimensions'] input[name='sku'][value='#{prefix}']"
  end

  test "inline update persists box packing fields" do
    patch "/erp/sku_dimensions/#{@sku.sku_code}",
      params: {
        inline_field: "outer_box_pcs",
        inline_context: {
          frame_id: "sku_dimension_#{@sku.sku_code}_outer_box_pcs_cell"
        },
        ec_sku_dimension: {
          outer_box_pcs: "12"
        }
      },
      headers: {
        "Accept" => "text/vnd.turbo-stream.html"
      }

    assert_response :success
    assert_equal 12, @dimension.reload.outer_box_pcs
    assert_select "turbo-stream[action='replace'][target='sku_dimension_#{@sku.sku_code}_outer_box_pcs_cell']" do
      assert_select "template", "12"
    end
  end

  test "inline update persists existing sku dimension field" do
    patch "/erp/sku_dimensions/#{@sku.sku_code}",
      params: {
        inline_field: "outer_length_cm",
        inline_context: {
          frame_id: "sku_dimension_#{@sku.sku_code}_outer_length_cm_cell"
        },
        ec_sku_dimension: {
          outer_length_cm: "12.50"
        }
      },
      headers: {
        "Accept" => "text/vnd.turbo-stream.html"
      }

    assert_response :success
    assert_equal BigDecimal("12.5"), @dimension.reload.outer_length_cm
    assert_select "turbo-stream[action='replace'][target='sku_dimension_#{@sku.sku_code}_outer_length_cm_cell']" do
      assert_select "template", "12.50"
    end
    assert_select "turbo-stream[action='update'][target='global_toast']"
  end

  test "inline update creates missing sku dimension record" do
    Ec::SkuDimension.where(sku_code: @sku.sku_code).delete_all

    assert_difference "Ec::SkuDimension.count", 1 do
      patch "/erp/sku_dimensions/#{@sku.sku_code}",
        params: {
          inline_field: "inner_width_cm",
          inline_context: {
            frame_id: "sku_dimension_#{@sku.sku_code}_inner_width_cm_cell"
          },
          ec_sku_dimension: {
            inner_width_cm: "21.5"
          }
        },
        headers: {
          "Accept" => "text/vnd.turbo-stream.html"
        }
    end

    assert_response :success
    assert_equal BigDecimal("21.5"), Ec::SkuDimension.find_by!(sku_code: @sku.sku_code).inner_width_cm
  end

  private

  def platform_category_source_id(suffix)
    "#{@token}-#{suffix}"
  end

  def platform_category_source_ids
    %w[parent child other-parent other-child].map { |suffix| platform_category_source_id(suffix) }
  end
end
