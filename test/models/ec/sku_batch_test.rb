require "test_helper"

class Ec::SkuBatchTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "BATCH-#{@token}", product_name: "批次测试 SKU")
  end

  teardown do
    Ec::SkuBatch.where(sku_code: @sku.sku_code).delete_all if defined?(Ec::SkuBatch)
    Ec::SkuBatch.joins(:sku).where("ec_skus.sku_code LIKE ?", "%#{@token}%").delete_all if defined?(Ec::SkuBatch)
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").delete_all
    Ec::MasterSku.where("master_sku_code LIKE ?", "%#{@token}%").delete_all if defined?(Ec::MasterSku)
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

  test "generates batch code when blank on create" do
    master_sku = Ec::MasterSku.create!(master_sku_code: "SPU-#{@token}")
    sku = Ec::Sku.create!(
      master_sku: master_sku,
      sku_code: "SKU-AUTO-#{@token}",
      product_name: "自动批次号 SKU"
    )

    batch = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: " ",
      purchase_date: Date.new(2026, 6, 5),
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5
    )

    assert_equal "#{@token}-AUTO-#{@token}-2026-06-00", batch.batch_code
  end

  test "generated batch code increments by sku and purchase month" do
    master_sku = Ec::MasterSku.create!(master_sku_code: "SPU-SEQ-#{@token}")
    sku = Ec::Sku.create!(
      master_sku: master_sku,
      sku_code: "SKU-SEQ-#{@token}",
      product_name: "自动批次序列 SKU"
    )

    first_batch = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      purchase_date: Date.new(2026, 6, 5),
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5
    )
    second_batch = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      purchase_date: Date.new(2026, 6, 20),
      purchased_quantity: 50,
      purchase_unit_price_cny: 10
    )
    next_month_batch = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      purchase_date: Date.new(2026, 7, 1),
      purchased_quantity: 60,
      purchase_unit_price_cny: 10
    )

    assert_equal "SEQ-#{@token}-SEQ-#{@token}-2026-06-00", first_batch.batch_code
    assert_equal "SEQ-#{@token}-SEQ-#{@token}-2026-06-01", second_batch.batch_code
    assert_equal "SEQ-#{@token}-SEQ-#{@token}-2026-07-00", next_month_batch.batch_code
  end

  test "generated batch code skips globally duplicated candidates" do
    master_sku = Ec::MasterSku.create!(master_sku_code: "SPU-DUP-#{@token}")
    sku = Ec::Sku.create!(
      master_sku: master_sku,
      sku_code: "SKU-DUP-#{@token}",
      product_name: "自动批次冲突 SKU"
    )
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DUP-#{@token}-DUP-#{@token}-2026-06-00",
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5
    )

    batch = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      purchase_date: Date.new(2026, 6, 5),
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5
    )

    assert_equal "DUP-#{@token}-DUP-#{@token}-2026-06-01", batch.batch_code
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
