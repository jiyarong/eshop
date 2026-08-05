require "test_helper"
require "securerandom"

module Ec
  class WbSupplyOrderChangeRecorderTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(6)
      @account = RawWb::SellerAccount.create!(
        name: "wb-supply-action-#{@token}",
        api_token: "token-#{@token}",
        company_type: "small"
      )
      @store = Ec::Store.create!(
        platform: "wb",
        store_name: "WB supply action #{@token}",
        company_type: "small",
        wb_raw_account_id: @account.id,
        is_active: true
      )
      @sku = Ec::Sku.create!(sku_code: "WB-SUPPLY-#{@token}", product_name: "WB supply action test")
      @sku_product = Ec::SkuProduct.create!(
        sku: @sku,
        store: @store,
        product_id: "123456",
        offer_id: @sku.sku_code
      )
      @operator = User.create!(
        email: "wb-supply-action-#{@token}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
      Ec::SkuProductOperator.create!(sku_product: @sku_product, user: @operator)
      RawWb::SupplyItem.create!(
        account: @account,
        wb_supply_id: "400001",
        nm_id: 123456,
        quantity: 36,
        accepted_qty: 12,
        synced_at: Time.current
      )
    end

    teardown do
      Ec::OperationAction.where(ec_sku_product_id: @sku_product&.id).delete_all
      RawWb::SupplyItem.where(account_id: @account&.id).delete_all
      RawWb::Supply.where(account_id: @account&.id).delete_all
      Ec::SkuProductOperator.where(sku_product_id: @sku_product&.id).delete_all
      Ec::SkuProduct.where(id: @sku_product&.id).delete_all
      Ec::Sku.where(id: @sku&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      RawWb::SellerAccount.where(id: @account&.id).delete_all
      User.where(id: @operator&.id).delete_all
    end

    test "records a WB supply status change with supply and item details" do
      updated_at = "2026-08-04T08:23:58Z"
      supply = {
        "supplyID" => 400001,
        "preorderID" => 500001,
        "statusID" => 5,
        "boxTypeID" => 2,
        "isBoxOnPallet" => false,
        "createDate" => "2026-07-29T01:14:10Z",
        "supplyDate" => "2026-08-01T00:00:00Z",
        "factDate" => "2026-08-02T10:00:00Z",
        "updatedDate" => updated_at
      }

      assert_difference "Ec::OperationAction.count", 1 do
        Ec::WbSupplyOrderChangeRecorder.record(
          account: @account,
          changes: [{ previous_status_id: 4, supply: supply }]
        )
      end

      action = Ec::OperationAction.order(:id).last
      assert_equal "supply_order", action.operation_type
      assert_equal @operator, action.operated_by_user
      assert_equal Time.zone.parse(updated_at), action.operated_at
      assert_equal({ "from" => "accepting", "to" => "accepted" },
        action.diff_result.dig("fields", "supply_order_status"))
      assert_equal "400001", action.diff_result.dig("supply_order", "id")
      assert_equal "500001", action.diff_result.dig("supply_order", "preorder_id")
      assert_equal "123456.0", action.diff_result.dig("supply_order", "nm_id")
      assert_equal "36.0", action.diff_result.dig("supply_order", "sku_quantity")
      assert_equal "12.0", action.diff_result.dig("supply_order", "accepted_quantity")
      assert_equal "24.0", action.diff_result.dig("supply_order", "remaining_quantity")
      assert_equal "4.0", action.diff_result.dig("supply_order", "status_id_from")
      assert_equal "5.0", action.diff_result.dig("supply_order", "status_id_to")
    end

    test "supply upsert records only a real status transition" do
      RawWb::Supply.create!(
        account: @account,
        wb_supply_id: "400001",
        preorder_id: 500001,
        status_id: 4,
        supply_created_at: Time.zone.parse("2026-07-29T01:14:10Z"),
        synced_at: 1.day.ago
      )
      supply = {
        "supplyID" => 400001,
        "preorderID" => 500001,
        "statusID" => "5",
        "boxTypeID" => 2,
        "createDate" => "2026-07-29T01:14:10Z",
        "updatedDate" => "2026-08-04T08:23:58Z"
      }
      sync = RawWb::DailySync.new(@account, days: 2)

      assert_difference "Ec::OperationAction.count", 1 do
        sync.send(:upsert_supplies_from_v1, [supply])
      end
      assert_equal 5, RawWb::Supply.find_by!(account: @account, preorder_id: 500001).status_id

      assert_no_difference "Ec::OperationAction.count" do
        sync.send(:upsert_supplies_from_v1, [supply])
      end
    end
  end
end
