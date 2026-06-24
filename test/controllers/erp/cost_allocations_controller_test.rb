require "test_helper"

class Erp::CostAllocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-allocations-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @sku = Ec::Sku.create!(sku_code: "ERP-ALLOC-#{@token}", product_name: "ERP 分摊 SKU")
    @batch = Ec::SkuBatch.create!(sku_code: @sku.sku_code, batch_code: "ERP-ALLOC-BATCH-#{@token}", purchased_quantity: 100, purchase_unit_price_cny: 10)
    @allocation = Ec::CostAllocation.create!(
      allocation_no: "ERP-ALLOC-#{@token}",
      cost_type: "international_freight",
      allocation_method: "manual",
      total_amount_cny: 500,
      status: "draft"
    )
    @allocation.items.create!(sku_batch: @batch, amount_cny: 500)
    @allocation.update!(status: "locked")
  end

  teardown do
    allocation_ids = Ec::CostAllocation.where("allocation_no LIKE ?", "%#{@token}%").pluck(:id)
    Ec::CostAllocationItem.where(cost_allocation_id: allocation_ids).delete_all
    Ec::CostAllocation.where(id: allocation_ids).delete_all
    Ec::SkuBatch.where(id: @batch.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-allocations-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-allocations-#{@token.downcase}%").delete_all
  end

  test "index renders cost allocations" do
    get "/erp/cost_allocations", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "费用分摊"
    assert_select "td", @allocation.allocation_no
    assert_select "td", @allocation.cost_type
  end

  test "show renders cost allocation items" do
    get "/erp/cost_allocations/#{@allocation.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @allocation.allocation_no
    assert_select "td", @batch.batch_code
    assert_select "dt", "分摊金额"
  end

  test "new renders form" do
    get "/erp/cost_allocations/new", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "新增费用分摊"
    assert_select "form[action='/erp/cost_allocations']"
  end

  test "create cost allocation with item" do
    assert_difference "Ec::CostAllocation.count", 1 do
      assert_difference "Ec::CostAllocationItem.count", 1 do
        post "/erp/cost_allocations", params: {
          ec_cost_allocation: {
            allocation_no: "created-alloc-#{@token}",
            cost_type: "warehouse",
            allocation_method: "manual",
            total_amount_cny: "260",
            allocated_on: "2026-06-02",
            status: "draft",
            memo: "手动录入",
            items_attributes: {
              "0" => {
                sku_batch_id: @batch.id,
                amount_cny: "260",
                memo: "仓储费"
              }
            }
          }
        }
      end
    end

    created = Ec::CostAllocation.find_by!(allocation_no: "CREATED-ALLOC-#{@token}")
    assert_redirected_to "/erp/cost_allocations/#{created.id}"
    assert_equal "warehouse", created.cost_type
    assert_equal 260.to_d, created.items.first.amount_cny
  end

  test "edit and update cost allocation item" do
    get "/erp/cost_allocations/#{@allocation.id}/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "编辑费用分摊"

    @allocation.update!(status: "draft")
    item = @allocation.items.first
    sign_in @current_user
    patch "/erp/cost_allocations/#{@allocation.id}", params: {
      ec_cost_allocation: {
        total_amount_cny: "300",
        status: "locked",
        items_attributes: {
          "0" => {
            id: item.id,
            sku_batch_id: @batch.id,
            amount_cny: "300"
          }
        }
      }
    }

    assert_redirected_to "/erp/cost_allocations/#{@allocation.id}"
    @allocation.reload
    assert_equal "locked", @allocation.status
    assert_equal 300.to_d, @allocation.total_amount_cny
    assert_equal 300.to_d, @allocation.items.first.amount_cny
  end
end
