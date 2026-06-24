require "test_helper"

class Ec::CostAllocationBuilderTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "CAB-#{@token}", product_name: "分摊生成 SKU")
    @batch_a = Ec::SkuBatch.create!(sku_code: @sku.sku_code, batch_code: "CAB-A-#{@token}", purchased_quantity: 100, purchase_unit_price_cny: 10)
    @batch_b = Ec::SkuBatch.create!(sku_code: @sku.sku_code, batch_code: "CAB-B-#{@token}", purchased_quantity: 300, purchase_unit_price_cny: 20)
  end

  teardown do
    Ec::SkuBatch.where(sku_code: @sku.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "allocates by quantity" do
    items = Ec::CostAllocationBuilder.new(
      total_amount_cny: 400,
      allocation_method: "by_quantity",
      batches: [@batch_a, @batch_b]
    ).call

    assert_equal 100.to_d, items.fetch(@batch_a.id)
    assert_equal 300.to_d, items.fetch(@batch_b.id)
  end

  test "allocates by purchase amount" do
    items = Ec::CostAllocationBuilder.new(
      total_amount_cny: 700,
      allocation_method: "by_purchase_amount",
      batches: [@batch_a, @batch_b]
    ).call

    assert_equal 100.to_d, items.fetch(@batch_a.id)
    assert_equal 600.to_d, items.fetch(@batch_b.id)
  end
end
