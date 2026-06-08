require "test_helper"

class Erp::SkuBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-batches-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
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
    batch_ids = Ec::SkuBatch.where(sku_code: @sku.sku_code).pluck(:id)
    Ec::CostAllocationItem.where(sku_batch_id: batch_ids).delete_all
    Ec::PurchaseOrderItem.where(sku_batch_id: batch_ids).delete_all
    Ec::SkuBatch.where(id: batch_ids).delete_all
    @sku.destroy
    UserRole.joins(:user).where("users.email LIKE ?", "erp-batches-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-batches-#{@token.downcase}%").delete_all
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

  test "new renders form" do
    get "/erp/sku_batches/new", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "新增 SKU 批次"
    assert_select "form[action='/erp/sku_batches']"
  end

  test "modal new renders batch form with selected sku" do
    get "/erp/sku_batches/new", params: { sku_code: @sku.sku_code }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "form[action='/erp/sku_batches'][data-turbo-frame='_top']"
    assert_select "select[name='ec_sku_batch[sku_code]'] option[selected='selected'][value=?]", @sku.sku_code
  end

  test "create batch" do
    assert_difference "Ec::SkuBatch.count", 1 do
      post "/erp/sku_batches", params: {
        ec_sku_batch: {
          sku_code: @sku.sku_code,
          batch_code: "created-batch-#{@token}",
          status: "ordered",
          purchased_quantity: "120",
          received_quantity: "20",
          purchase_unit_price_cny: "11.5",
          expected_arrival_on: "2026-06-15",
          memo: "手动录入"
        }
      }
    end

    created = Ec::SkuBatch.find_by!(batch_code: "CREATED-BATCH-#{@token}")
    assert_redirected_to "/erp/sku_batches/#{created.id}"
    assert_equal "ordered", created.status
    assert_equal 120, created.purchased_quantity
  end

  test "invalid modal create rerenders batch form" do
    post "/erp/sku_batches", params: {
      ec_sku_batch: {
        sku_code: @sku.sku_code,
        batch_code: "",
        purchased_quantity: "120",
        purchase_unit_price_cny: "11.5"
      }
    }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select ".error-box"
  end

  test "edit and update batch" do
    get "/erp/sku_batches/#{@batch.id}/edit", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "编辑 SKU 批次"

    sign_in @current_user
    patch "/erp/sku_batches/#{@batch.id}", params: {
      ec_sku_batch: {
        status: "received",
        received_quantity: "100",
        received_on: "2026-06-20"
      }
    }

    assert_redirected_to "/erp/sku_batches/#{@batch.id}"
    @batch.reload
    assert_equal "received", @batch.status
    assert_equal 100, @batch.received_quantity
    assert_equal Date.new(2026, 6, 20), @batch.received_on
  end
end
