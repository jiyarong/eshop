require "test_helper"

class Ec::SkuBatchTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "BATCH-#{@token}", product_name: "批次测试 SKU")
  end

  teardown do
    Ec::SkuBatch.where(sku_code: @sku.sku_code).delete_all if defined?(Ec::SkuBatch)
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
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

  test "allows negative quantities for adjustment batches" do
    batch = Ec::SkuBatch.new(
      sku_code: @sku.sku_code,
      batch_code: "NEG-#{@token}",
      batch_type: :wb_fbw_offset,
      purchased_quantity: -1,
      received_quantity: -1,
      purchase_unit_price_cny: 10
    )

    assert_predicate batch, :valid?
  end

  test "defaults batch type to normal" do
    batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "DEFAULT-#{@token}",
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5
    )

    assert_equal "normal", batch.batch_type
    assert_nil batch.defect_offset_note
    assert_predicate batch, :normal?
  end

  test "allows assigning a non-default batch type and note" do
    batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "OFFSET-#{@token}",
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5,
      batch_type: :wb_fbw_offset,
      defect_offset_note: "FBW inventory reconciliation"
    )

    assert_equal "wb_fbw_offset", batch.batch_type
    assert_equal "FBW inventory reconciliation", batch.defect_offset_note
    assert_predicate batch, :wb_fbw_offset?
  end

  test "rejects invalid batch type values" do
    batch = Ec::SkuBatch.new(
      sku_code: @sku.sku_code,
      batch_code: "INVALID-#{@token}",
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5,
      batch_type: :not_real
    )

    assert_not batch.valid?
    assert_predicate batch.errors[:batch_type], :present?
  end
end
