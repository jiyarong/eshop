require "test_helper"
require "securerandom"

module Ec
  class SupplyOrderChangeRecorderTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(6)
      @account = RawOzon::SellerAccount.create!(
        client_id: "supply-action-#{@token}",
        api_key: "token-#{@token}",
        company_type: "general",
        raw_json: {}
      )
      @store = Ec::Store.create!(
        platform: "ozon",
        store_name: "Supply action store #{@token}",
        company_type: "general",
        ozon_raw_account_id: @account.id,
        is_active: true
      )
      @sku = Ec::Sku.create!(sku_code: "SUPPLY-#{@token}", product_name: "Supply action test")
      @sku_product = Ec::SkuProduct.create!(
        sku: @sku,
        store: @store,
        product_id: "product-#{@token}",
        platform_sku_id: "123456",
        offer_id: @sku.sku_code
      )
      @operator = User.create!(
        email: "supply-action-#{@token}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
      Ec::SkuProductOperator.create!(sku_product: @sku_product, user: @operator)
    end

    teardown do
      Ec::OperationAction.where(ec_sku_product_id: @sku_product&.id).delete_all
      Ec::SkuProductOperator.where(sku_product_id: @sku_product&.id).delete_all
      Ec::SkuProduct.where(id: @sku_product&.id).delete_all
      Ec::Sku.where(id: @sku&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      RawOzon::SellerAccount.where(id: @account&.id).delete_all
      User.where(id: @operator&.id).delete_all
    end

    test "records an Ozon supply order status change for each bound SKU" do
      state_updated_at = "2026-08-04T07:23:58Z"
      row = {
        account_id: @account.id,
        supply_order_id: "119923443",
        status: "ACCEPTANCE_AT_STORAGE_WAREHOUSE",
        timeslot: { "timeslot" => { "from" => "2026-07-30T14:00:00Z" } },
        items: { "123456" => 36, "unmatched" => 2 },
        raw_json: {
          "order_number" => "2000061215904",
          "drop_off_warehouse" => { "name" => "Minsk" },
          "state_updated_date" => state_updated_at
        },
        created_at: Time.zone.parse("2026-07-29T01:14:10Z")
      }

      assert_difference "Ec::OperationAction.count", 1 do
        Ec::SupplyOrderChangeRecorder.record(
          account: @account,
          changes: [{ previous_status: "IN_TRANSIT", previous_items: nil, row: row }]
        )
      end

      action = Ec::OperationAction.order(:id).last
      assert_equal "supply_order", action.operation_type
      assert_equal @operator, action.operated_by_user
      assert_equal Time.zone.parse(state_updated_at), action.operated_at
      assert_equal({ "from" => "IN_TRANSIT", "to" => "ACCEPTANCE_AT_STORAGE_WAREHOUSE" },
        action.diff_result.dig("fields", "supply_order_status"))
      assert_equal "119923443", action.diff_result.dig("supply_order", "id")
      assert_equal "2000061215904", action.diff_result.dig("supply_order", "number")
      assert_equal "123456", action.diff_result.dig("supply_order", "platform_sku_id")
      assert_equal "36.0", action.diff_result.dig("supply_order", "sku_quantity")
      assert_equal "38.0", action.diff_result.dig("supply_order", "total_quantity")
      assert_equal({ "name" => "Minsk" }, action.diff_result.dig("supply_order", "drop_off_warehouse"))
    end

    test "uses previous items when a cancelled order no longer returns bundle items" do
      row = {
        account_id: @account.id,
        supply_order_id: "cancelled-order",
        status: "CANCELLED",
        timeslot: nil,
        items: nil,
        raw_json: { "order_number" => "cancelled-number" },
        created_at: Time.current
      }

      assert_difference "Ec::OperationAction.count", 1 do
        Ec::SupplyOrderChangeRecorder.record(
          account: @account,
          changes: [{ previous_status: "READY_TO_SUPPLY", previous_items: { "123456" => 5 }, row: row }]
        )
      end

      action = Ec::OperationAction.order(:id).last
      assert_equal "CANCELLED", action.diff_result.dig("fields", "supply_order_status", "to")
      assert_equal "5.0", action.diff_result.dig("supply_order", "sku_quantity")
    end
  end
end
