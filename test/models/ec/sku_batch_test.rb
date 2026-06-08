require "test_helper"

class Ec::SkuBatchTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "BATCH-#{@token}", product_name: "批次测试 SKU")
  end

  teardown do
    Ec::SkuBatch.where(sku_code: @sku.sku_code).delete_all if defined?(Ec::SkuBatch)
    @sku.destroy
  end

  test "belongs to sku and normalizes batch code" do
    batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: " batch-#{@token.downcase} ",
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5
    )

    assert_equal "BATCH-#{@token}", batch.batch_code
    assert_equal @sku, batch.sku
  end

  test "requires unique batch code" do
    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "BATCH-#{@token}",
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5
    )

    duplicate = Ec::SkuBatch.new(
      sku_code: @sku.sku_code,
      batch_code: "BATCH-#{@token}",
      purchased_quantity: 50,
      purchase_unit_price_cny: 10
    )

    assert_not duplicate.valid?
  end

  test "rejects negative quantities" do
    batch = Ec::SkuBatch.new(
      sku_code: @sku.sku_code,
      batch_code: "NEG-#{@token}",
      purchased_quantity: -1,
      received_quantity: -1,
      purchase_unit_price_cny: 10
    )

    assert_not batch.valid?
    assert_predicate batch.errors[:purchased_quantity], :present?
    assert_predicate batch.errors[:received_quantity], :present?
  end
end
