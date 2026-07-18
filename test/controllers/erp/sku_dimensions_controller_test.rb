require "test_helper"

class Erp::SkuDimensionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-sku-dimensions-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @sku = Ec::Sku.create!(sku_code: "ERP-DIM-#{@token}", product_name: "尺寸维护 SKU")
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
    Ec::SkuCost.where(sku_code: sku_codes).delete_all
    Ec::SkuDimension.where(sku_code: sku_codes).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku_codes).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-sku-dimensions-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-sku-dimensions-#{@token.downcase}%").delete_all
  end

  test "index renders sku dimension maintenance table" do
    get "/erp/sku_dimensions", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU 尺寸维护"
    assert_select "td", @sku.sku_code
    assert_select "th", "内长 cm"
    assert_select "th", "外长 cm"
    assert_select "th", "内箱重量 kg"
    assert_select "th", "外箱重量 kg"
    assert_select "th", "外箱 pcs"
    assert_select "turbo-frame#sku_dimension_#{@sku.sku_code}_inner_length_cm_cell"
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
end
