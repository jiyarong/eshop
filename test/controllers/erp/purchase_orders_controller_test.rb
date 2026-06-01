require "test_helper"

class Erp::PurchaseOrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-orders-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @sku = Ec::Sku.create!(sku_code: "ERP-PO-#{@token}", product_name: "ERP 采购 SKU")
    @batch = Ec::SkuBatch.create!(sku_code: @sku.sku_code, batch_code: "ERP-PO-BATCH-#{@token}", purchased_quantity: 100, purchase_unit_price_cny: 10)
    @supplier = Ec::Supplier.create!(name: "ERP 供应商 #{@token}")
    @order = Ec::PurchaseOrder.create!(order_no: "ERP-PO-#{@token}", supplier: @supplier, ordered_on: Date.new(2026, 5, 31))
    @order.items.create!(sku_code: @sku.sku_code, sku_batch: @batch, quantity: 100, unit_price_cny: 10)
  end

  teardown do
    order_ids = Ec::PurchaseOrder.where("order_no LIKE ?", "%#{@token}%").pluck(:id)
    Ec::PaymentRequest.where(purchase_order_id: order_ids).delete_all
    Ec::PurchaseOrderItem.where(purchase_order_id: order_ids).delete_all
    Ec::PurchaseOrder.where(id: order_ids).delete_all
    Ec::Supplier.where(id: @supplier.id).delete_all
    Ec::SkuBatch.where(id: @batch.id).delete_all
    @sku.destroy
    UserRole.joins(:user).where("users.email LIKE ?", "erp-orders-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-orders-#{@token.downcase}%").delete_all
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

  test "new renders form" do
    get "/erp/purchase_orders/new", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "新增采购单"
    assert_select "form[action='/erp/purchase_orders']"
  end

  test "create purchase order with item" do
    assert_difference "Ec::PurchaseOrder.count", 1 do
      assert_difference "Ec::PurchaseOrderItem.count", 1 do
        post "/erp/purchase_orders", params: {
          ec_purchase_order: {
            order_no: "created-po-#{@token}",
            supplier_id: @supplier.id,
            ordered_on: "2026-06-01",
            status: "ordered",
            currency: "CNY",
            memo: "手动录入",
            items_attributes: {
              "0" => {
                sku_batch_id: @batch.id,
                quantity: "50",
                unit_price_cny: "9.8",
                memo: "首批"
              }
            }
          }
        }
      end
    end

    created = Ec::PurchaseOrder.find_by!(order_no: "CREATED-PO-#{@token}")
    assert_redirected_to "/erp/purchase_orders/#{created.id}"
    assert_equal "ordered", created.status
    assert_equal @sku.sku_code, created.items.first.sku_code
  end

  test "edit and update purchase order item" do
    get "/erp/purchase_orders/#{@order.id}/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "编辑采购单"

    item = @order.items.first
    sign_in @current_user
    patch "/erp/purchase_orders/#{@order.id}", params: {
      ec_purchase_order: {
        status: "received",
        items_attributes: {
          "0" => {
            id: item.id,
            sku_batch_id: @batch.id,
            quantity: "80",
            unit_price_cny: "8.5"
          }
        }
      }
    }

    assert_redirected_to "/erp/purchase_orders/#{@order.id}"
    @order.reload
    assert_equal "received", @order.status
    assert_equal 80, @order.items.first.quantity
    assert_equal 8.5.to_d, @order.items.first.unit_price_cny
  end
end
