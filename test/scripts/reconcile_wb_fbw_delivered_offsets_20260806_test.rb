# frozen_string_literal: true

require "test_helper"

ENV["SKIP_WB_FBW_RECONCILE_RUN"] = "1"
load Rails.root.join("script/reconcile_wb_fbw_delivered_offsets_20260806.rb")
ENV.delete("SKIP_WB_FBW_RECONCILE_RUN")

class ReconcileWbFbwDeliveredOffsets20260806Test < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku_code = "FBW-REC-#{@token}"
    Ec::Sku.create!(sku_code: @sku_code, product_name: "FBW reconciliation test")
  end

  teardown do
    Ec::SkuBatch.where(sku_code: @sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku_code).delete_all
  end

  test "sets a deterministic adjustment and remains idempotent" do
    Ec::SkuBatch.create!(
      sku_code: @sku_code,
      batch_code: "EXISTING-#{@token}",
      batch_type: :wb_fbw_offset,
      status: "closed",
      purchased_quantity: -3,
      received_quantity: -3,
      purchase_unit_price_cny: 0
    )

    rows = { @sku_code => [20, 5, 4] }
    reconciler = WbFbwDeliveredOffsetReconciler20260806.new(rows: rows, apply: true)

    assert_difference "Ec::SkuBatch.count", 1 do
      reconciler.call
    end
    assert_no_difference "Ec::SkuBatch.count" do
      reconciler.call
    end

    batch = Ec::SkuBatch.find_by!(batch_code: "WB-FBW-DELIVERED-20260806-#{@sku_code}")
    assert_equal(-8, batch.received_quantity)
    assert_equal(-11, Ec::SkuBatch.wb_fbw_offset.where(sku_code: @sku_code).sum(:received_quantity))
  end

  test "preview does not write" do
    assert_no_difference "Ec::SkuBatch.count" do
      WbFbwDeliveredOffsetReconciler20260806.new(rows: { @sku_code => [10, 4, 3] }, apply: false).call
    end
  end
end
