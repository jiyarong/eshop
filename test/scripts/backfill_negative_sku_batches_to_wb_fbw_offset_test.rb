require "test_helper"

class BackfillNegativeSkuBatchesToWbFbwOffsetTest < ActiveSupport::TestCase
  SCRIPT_PATH = Rails.root.join("script/backfill_negative_sku_batches_to_wb_fbw_offset.rb")

  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "BATCH-BACKFILL-#{@token}", product_name: "批次回刷测试")

    @negative_batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "NEG-#{@token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 0,
      received_quantity: -5,
      purchase_unit_price_cny: 1
    )
    @positive_batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "POS-#{@token}",
      status: "received",
      batch_type: :other,
      purchased_quantity: 0,
      received_quantity: 8,
      purchase_unit_price_cny: 1
    )
  end

  teardown do
    Ec::SkuBatch.where(sku_code: @sku.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "backfills negative received quantity batches to wb_fbw_offset only" do
    load SCRIPT_PATH

    assert_equal "wb_fbw_offset", @negative_batch.reload.batch_type
    assert_equal "other", @positive_batch.reload.batch_type
  end
end
