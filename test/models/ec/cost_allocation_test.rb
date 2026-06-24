require "test_helper"

class Ec::CostAllocationTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "ALLOC-#{@token}", product_name: "分摊测试 SKU")
    @batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "ALLOC-BATCH-#{@token}",
      purchased_quantity: 100,
      purchase_unit_price_cny: 10
    )
  end

  teardown do
    if defined?(Ec::CostAllocationItem)
      Ec::CostAllocationItem.joins(:sku_batch).where(ec_sku_batches: { sku_code: @sku.sku_code }).delete_all
    end
    Ec::CostAllocation.where(allocation_no: "ALLOC-#{@token}").delete_all if defined?(Ec::CostAllocation)
    Ec::SkuBatch.where(id: @batch.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "locked allocation requires item total to match total amount" do
    allocation = Ec::CostAllocation.new(
      allocation_no: "ALLOC-#{@token}",
      cost_type: "international_freight",
      allocation_method: "manual",
      total_amount_cny: 500,
      status: "locked"
    )
    allocation.items.build(sku_batch: @batch, amount_cny: 400)

    assert_not allocation.valid?
    assert_includes allocation.errors[:base], "分摊明细合计必须等于费用总额"
  end
end
