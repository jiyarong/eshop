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
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
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

  test "index localizes visible chrome in english" do
    get "/erp/sku_batches", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "SKU Batches"
    assert_select "a[href=?]", erp_new_sku_batch_path(locale: "en"), "Add SKU batch"
    assert_select "th", "Batch number"
    assert_select "th", "Product name"
    assert_select "th", "Purchased quantity"
    assert_select "th", "Received quantity"
    assert_select "th", "Purchase unit price"
  end

  test "show renders batch cost summary" do
    get "/erp/sku_batches/#{@batch.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @batch.batch_code
    assert_select "dt", "单件批次成本"
  end

  test "show localizes visible chrome in english" do
    get "/erp/sku_batches/#{@batch.id}", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @batch.batch_code
    assert_select "a[href=?]", erp_edit_sku_batch_path(@batch, locale: "en"), "Edit"
    assert_select "dt", "Product name"
    assert_select "dt", "Purchase cost"
    assert_select "dt", "Allocated cost"
    assert_select "dt", "Unit batch cost"
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

  test "modal edit renders batch form" do
    get "/erp/sku_batches/#{@batch.id}/edit", headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "编辑批次"
    assert_select "form[action='#{erp_sku_batch_path(@batch)}'][data-turbo-frame='_top']"
  end

  test "batch modal form localizes visible chrome in english" do
    get "/erp/sku_batches/#{@batch.id}/edit", params: { locale: "en" }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "h2", "Edit batch"
    assert_select "button[aria-label=?]", "Close"
    assert_select "label", "Batch number"
    assert_select "label", "Status"
    assert_select "label", "Expected arrival"
    assert_select "label", "Actual arrival"
    assert_select "input[type='submit'][value=?]", "Save"
  end

  test "create batch returns to sku list" do
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
    assert_redirected_to "/erp/skus"
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

  test "edit and update batch returns to sku list" do
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

    assert_redirected_to "/erp/skus"
    @batch.reload
    assert_equal "received", @batch.status
    assert_equal 100, @batch.received_quantity
    assert_equal Date.new(2026, 6, 20), @batch.received_on
  end

  test "invalid modal update rerenders batch form" do
    patch "/erp/sku_batches/#{@batch.id}", params: {
      ec_sku_batch: {
        batch_code: "",
        purchased_quantity: "100"
      }
    }, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#erp_modal"
    assert_select ".erp-modal"
    assert_select "h2", "编辑批次"
    assert_select ".error-box"
  end

  test "inline update returns turbo stream cell and feedback on success" do
    patch "/erp/sku_batches/#{@batch.id}",
      params: {
        inline_field: "status",
        inline_context: {
          frame_id: "sku_batch_#{@batch.id}_status_cell",
          feedback_target: "batch-inline-feedback--sku-#{@sku.id}"
        },
        ec_sku_batch: {
          status: "received"
        }
      },
      headers: {
        "Accept" => "text/vnd.turbo-stream.html"
    }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type

    @batch.reload
    assert_equal "received", @batch.status
    assert_includes response.body, %(target="sku_batch_#{@batch.id}_status_cell")
    assert_select "turbo-stream[action='replace'][target='sku_batch_#{@batch.id}_status_cell']" do
      assert_select "template .badge.badge-sec", I18n.t("erp.sku_batches.statuses.received")
    end
    assert_includes response.body, "received"
    assert_includes response.body, %(target="batch-inline-feedback--sku-#{@sku.id}")
    assert_select "turbo-stream[action='update'][target='batch-inline-feedback--sku-#{@sku.id}']" do
      assert_select "template", /success|saved|updated|#{Regexp.escape(I18n.t('erp.common.status'))}/i
    end
  end

  test "inline update keeps edit state and feedback on failure" do
    patch "/erp/sku_batches/#{@batch.id}",
      params: {
        inline_field: "batch_code",
        inline_context: {
          frame_id: "sku_batch_#{@batch.id}_batch_code_cell",
          feedback_target: "batch-inline-feedback--sku-#{@sku.id}"
        },
        ec_sku_batch: {
          batch_code: ""
        }
      },
      headers: {
        "Accept" => "text/vnd.turbo-stream.html"
      }

    assert_response :unprocessable_entity

    @batch.reload
    assert_equal "ERP-BATCH-#{@token}", @batch.batch_code
    assert_includes response.body, %(target="sku_batch_#{@batch.id}_batch_code_cell")
    assert_select "turbo-stream[action='replace'][target='sku_batch_#{@batch.id}_batch_code_cell']" do
      assert_select "template form[action='#{erp_sku_batch_path(@batch)}']" do
        assert_select "input[name='ec_sku_batch[batch_code]'][value='']"
        assert_select ".error-box", /.+/
      end
    end
    assert_includes response.body, %(target="batch-inline-feedback--sku-#{@sku.id}")
    assert_includes response.body, "error-box"
    assert_select "turbo-stream[action='update'][target='batch-inline-feedback--sku-#{@sku.id}']" do
      assert_select "template .error-box"
    end
  end
end
