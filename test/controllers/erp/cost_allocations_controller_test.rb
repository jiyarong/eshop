require "test_helper"

class Erp::CostAllocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
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
    Ec::CostAllocationItem.where(cost_allocation_id: @allocation.id).delete_all
    Ec::CostAllocation.where(id: @allocation.id).delete_all
    Ec::SkuBatch.where(id: @batch.id).delete_all
    @sku.destroy
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
end
