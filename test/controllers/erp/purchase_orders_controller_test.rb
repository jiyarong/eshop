require "test_helper"

class Erp::PurchaseOrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "ERP-PO-#{@token}", product_name: "ERP 采购 SKU")
    @batch = Ec::SkuBatch.create!(sku_code: @sku.sku_code, batch_code: "ERP-PO-BATCH-#{@token}", purchased_quantity: 100, purchase_unit_price_cny: 10)
    @supplier = Ec::Supplier.create!(name: "ERP 供应商 #{@token}")
    @order = Ec::PurchaseOrder.create!(order_no: "ERP-PO-#{@token}", supplier: @supplier, ordered_on: Date.new(2026, 5, 31))
    @order.items.create!(sku_code: @sku.sku_code, sku_batch: @batch, quantity: 100, unit_price_cny: 10)
  end

  teardown do
    Ec::PaymentRequest.where(purchase_order_id: @order.id).delete_all
    Ec::PurchaseOrderItem.where(purchase_order_id: @order.id).delete_all
    Ec::PurchaseOrder.where(id: @order.id).delete_all
    Ec::Supplier.where(id: @supplier.id).delete_all
    Ec::SkuBatch.where(id: @batch.id).delete_all
    @sku.destroy
  end

  test "index renders purchase orders" do
    get "/erp/purchase_orders", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "采购单"
    assert_select "td", @order.order_no
    assert_select "td", @supplier.name
  end

  test "show renders purchase order items" do
    get "/erp/purchase_orders/#{@order.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @order.order_no
    assert_select "td", @batch.batch_code
    assert_select "dt", "采购金额"
  end
end
