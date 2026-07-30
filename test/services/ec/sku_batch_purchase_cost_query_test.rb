require "test_helper"

class Ec::SkuBatchPurchaseCostQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "BATCH-COST-#{@token}", product_name: "批次采购成本测试")
    @dated_batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "BATCH-COST-DATED-#{@token}",
      purchase_date: Date.new(2026, 6, 10)
    )
    @undated_batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "BATCH-COST-UNDATED-#{@token}"
    )
  end

  teardown do
    Ec::SkuBatch.where(id: [@dated_batch.id, @undated_batch.id]).delete_all
    Ec::SkuCost.where(sku_code: @sku.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "loads the latest cost strictly before each batch purchase date in one query" do
    Ec::SkuCost.create!(sku_code: @sku.sku_code, effective_on: Date.new(2026, 5, 1), purchase_price_cny: 10)
    Ec::SkuCost.create!(sku_code: @sku.sku_code, effective_on: Date.new(2026, 6, 1), purchase_price_cny: 12.5)
    Ec::SkuCost.create!(sku_code: @sku.sku_code, effective_on: @dated_batch.purchase_date, purchase_price_cny: 20)

    query_count = 0
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      query_count += 1 if payload[:sql].include?("DISTINCT ON (b.id)")
    end

    prices = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      Ec::SkuBatchPurchaseCostQuery.call([@dated_batch, @undated_batch])
    end

    assert_equal 1, query_count
    assert_equal BigDecimal("12.5"), prices[@dated_batch.id]
    assert_nil prices[@undated_batch.id]
  end
end
