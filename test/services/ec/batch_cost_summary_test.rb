require "test_helper"

class Ec::BatchCostSummaryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "BCS-#{@token}", product_name: "批次成本 SKU")
    @batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "BCS-BATCH-#{@token}",
      purchased_quantity: 100,
      purchase_unit_price_cny: 10
    )
    allocation = Ec::CostAllocation.create!(
      allocation_no: "BCS-ALLOC-#{@token}",
      cost_type: "international_freight",
      allocation_method: "manual",
      total_amount_cny: 500,
      status: "draft"
    )
    allocation.items.create!(sku_batch: @batch, amount_cny: 500)
    allocation.update!(status: "locked")
  end

  teardown do
    if defined?(Ec::CostAllocationItem)
      Ec::CostAllocationItem.joins(:sku_batch).where(ec_sku_batches: { sku_code: @sku.sku_code }).delete_all
    end
    Ec::CostAllocation.where(allocation_no: "BCS-ALLOC-#{@token}").delete_all if defined?(Ec::CostAllocation)
    Ec::SkuBatch.where(id: @batch.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "calculates batch unit cost with locked allocations" do
    summary = Ec::BatchCostSummary.new(@batch).call

    assert_equal 500.to_d, summary[:allocated_cost_cny]
    assert_equal 15.to_d, summary[:unit_cost_cny]
  end
end
