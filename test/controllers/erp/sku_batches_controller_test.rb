require "test_helper"

class Erp::SkuBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "ERP-BATCH-#{@token}", product_name: "ERP 批次 SKU")
    @batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "ERP-BATCH-#{@token}",
      purchased_quantity: 100,
      received_quantity: 80,
      purchase_unit_price_cny: 12.5
    )
  end

  teardown do
    Ec::CostAllocationItem.where(sku_batch_id: @batch.id).delete_all
    Ec::SkuBatch.where(id: @batch.id).delete_all
    @sku.destroy
  end

  test "index renders sku batches" do
    get "/erp/sku_batches", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU 批次"
    assert_select "td", @batch.batch_code
    assert_select "td", @sku.sku_code
  end

  test "show renders batch cost summary" do
    get "/erp/sku_batches/#{@batch.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @batch.batch_code
    assert_select "dt", "单件批次成本"
  end
end
