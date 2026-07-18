require "test_helper"

class Erp::SkuCostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-sku-costs-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @sku = Ec::Sku.create!(sku_code: "ERP-COST-#{@token}", product_name: "成本维护 SKU")
    @cost = Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      purchase_price_cny: 10,
      freight_to_by_cny: 2,
      customs_misc_cny: 1,
      customs_duty_rate: 0.1,
      import_vat_rate: 0.2
    )
  end

  teardown do
    sku_codes = Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").pluck(:sku_code)
    Ec::SkuCost.where(sku_code: sku_codes).delete_all
    Ec::SkuDimension.where(sku_code: sku_codes).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku_codes).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-sku-costs-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-sku-costs-#{@token.downcase}%").delete_all
  end

  test "index renders sku cost maintenance table" do
    get "/erp/sku_costs", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU 成本维护"
    assert_select "td", @sku.sku_code
    assert_select "th", "采购价 CNY"
    assert_select "turbo-frame#sku_cost_#{@sku.sku_code}_purchase_price_cny_cell"
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
    assert_equal BigDecimal("3.75"), Ec::SkuCost.find_by!(sku_code: @sku.sku_code).freight_to_by_cny
  end
end
