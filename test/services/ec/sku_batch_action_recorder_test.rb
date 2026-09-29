require "test_helper"

module Ec
  class SkuBatchActionRecorderTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(6).upcase
      @admin = User.create!(email: "batch-action-#{@token.downcase}@example.com", password: "password123")
      @admin.roles << Role.find_by!(code: "super_admin")
      @sku = Ec::Sku.create!(sku_code: "BATCH-ACTION-#{@token}", product_name: "Batch action test")
      @store = Ec::Store.create!(
        platform: "wb",
        store_name: "Batch action store #{@token}",
        company_type: "small",
        is_active: true
      )
      @sku_product = Ec::SkuProduct.create!(
        sku: @sku,
        store: @store,
        product_id: "BATCH-ACTION-#{@token}",
        offer_id: @sku.sku_code
      )
    end

    teardown do
      Ec::OperationAction.where(ec_sku_id: @sku&.id).delete_all
      Ec::SkuBatch.where(sku_code: @sku&.sku_code).delete_all
      Ec::SkuOperationPlan.where(sku_id: @sku&.id).delete_all
      Ec::SkuProduct.where(id: @sku_product&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      Ec::Sku.where(id: @sku&.id).delete_all
      UserRole.where(user_id: @admin&.id).delete_all
      User.where(id: @admin&.id).delete_all
    end

    test "records a replenishment action and completes a matching plan" do
      plan = @sku.sku_operation_plans.create!(
        target: "replenishment",
        operation: "increase",
        scope: "SKU",
        scope_id: @sku.sku_code,
        referer: [ "stock_risk" ],
        message: "补充采购库存",
        created_at: 1.hour.ago
      )

      batch = @sku.batches.create!(
        batch_code: "BATCH-#{@token}",
        purchased_quantity: 24,
        purchase_unit_price_cny: 10
      )

      action = Ec::OperationAction.find_by!(ec_sku_id: @sku.id, ec_sku_product_id: @sku_product.id)
      assert_equal "supply_order", action.operation_type
      assert_equal @admin, action.operated_by_user
      assert_equal "BATCH-#{@token}", action.diff_result.dig("fields", "batch_code", "to")
      assert_equal({ "from" => "0", "to" => "24" }, action.diff_result.dig("fields", "purchased_quantity"))
      assert_equal plan, action.plan
      assert plan.reload.done?
      assert_equal batch.created_at, action.operated_at
    end

    test "does not record adjustment batches as replenishment" do
      assert_no_difference "Ec::OperationAction.count" do
        @sku.batches.create!(
          batch_code: "OFFSET-#{@token}",
          batch_type: "wb_fbw_offset",
          purchased_quantity: 24,
          purchase_unit_price_cny: 10
        )
      end
    end

    test "does not record a zero quantity batch" do
      assert_no_difference "Ec::OperationAction.count" do
        @sku.batches.create!(
          batch_code: "ZERO-#{@token}",
          purchased_quantity: 0,
          purchase_unit_price_cny: 10
        )
      end
    end
  end
end
