require "test_helper"

class Ec::PurchaseOrderTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "PO-#{@token}", product_name: "采购测试 SKU")
    @batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "PO-BATCH-#{@token}",
      purchased_quantity: 100,
      purchase_unit_price_cny: 10
    )
    @supplier = Ec::Supplier.create!(name: "供应商 #{@token}")
  end

  teardown do
    if defined?(Ec::PurchaseOrderItem)
      Ec::PurchaseOrderItem.where(sku_code: @sku.sku_code).delete_all
    end
    Ec::PurchaseOrder.where(order_no: "PO-#{@token}").delete_all if defined?(Ec::PurchaseOrder)
    Ec::Supplier.where(id: @supplier.id).delete_all if defined?(Ec::Supplier)
    Ec::SkuBatch.where(id: @batch.id).delete_all
    @sku.destroy
  end

  test "purchase order has items linked to sku batches" do
    order = Ec::PurchaseOrder.create!(
      order_no: "PO-#{@token}",
      supplier: @supplier,
      ordered_on: Date.new(2026, 5, 31)
    )

    item = order.items.create!(
      sku_code: @sku.sku_code,
      sku_batch: @batch,
      quantity: 100,
      unit_price_cny: 10
    )

    assert_equal @supplier, order.supplier
    assert_equal @batch, item.sku_batch
    assert_equal 1000.to_d, order.goods_amount_cny
  end

  test "purchase order item requires positive quantity" do
    order = Ec::PurchaseOrder.create!(order_no: "PO-#{@token}", supplier: @supplier)
    item = order.items.build(sku_code: @sku.sku_code, sku_batch: @batch, quantity: 0, unit_price_cny: 10)

    assert_not item.valid?
  end
end
