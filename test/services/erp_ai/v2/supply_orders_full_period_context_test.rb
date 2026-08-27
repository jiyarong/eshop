require "test_helper"

class ErpAI::V2::SupplyOrdersFullPeriodContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    @sku = Ec::Sku.create!(sku_code: "SUPPLY-CONTEXT-#{@token}", product_name: "Supply context")
    @wb_account = RawWb::SellerAccount.create!(name: "Supply WB #{@token}", api_token: "wb-#{@token}", company_type: :small)
    @ozon_account = RawOzon::SellerAccount.create!(company_name: "Supply Ozon #{@token}", client_id: "oz-#{@token}", api_key: "key-#{@token}", company_type: :small)
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "Supply WB #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Supply Ozon #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id)
    @wb_product = Ec::SkuProduct.create!(sku: @sku, store: @wb_store, product_id: "71001")
    @ozon_product = Ec::SkuProduct.create!(sku: @sku, store: @ozon_store, product_id: "OZON-#{@token}", platform_sku_id: "81001")
  end

  teardown do
    RawWb::SupplyItem.where(account_id: @wb_account&.id).delete_all
    RawWb::Supply.where(account_id: @wb_account&.id).delete_all
    RawOzon::SupplyOrder.where(account_id: @ozon_account&.id).delete_all
    Ec::SkuProduct.where(id: [@wb_product&.id, @ozon_product&.id]).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id]).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "returns the same WB and Ozon fields shown by the supply report within the requested period" do
    wb_supply = RawWb::Supply.create!(
      account: @wb_account, wb_supply_id: "WB-#{@token}", preorder_id: 12_345, status_id: 4,
      supply_created_at: @time_zone.parse("2026-08-03 09:00"), supply_date: @time_zone.parse("2026-08-05 10:00"),
      warehouse_name: "Ryazan", actual_warehouse_name: "Obukhovo", box_type_id: 1,
      detail_quantity: 12, accepted_quantity: 5, synced_at: Time.current
    )
    RawWb::SupplyItem.create!(
      account: @wb_account, wb_supply_id: wb_supply.wb_supply_id, nm_id: 71_001,
      quantity: 12, accepted_qty: 5, synced_at: Time.current
    )
    RawOzon::SupplyOrder.create!(
      account: @ozon_account, supply_order_id: "OZON-#{@token}", status: "IN_TRANSIT",
      items: { "81001" => 8, "99999" => 99 },
      created_at: @time_zone.parse("2026-08-04 09:00"),
      timeslot: { "from" => "2026-08-06T10:00:00Z", "to" => "2026-08-06T12:00:00Z" },
      raw_json: {
        "order_number" => "ORDER-#{@token}",
        "drop_off_warehouse" => { "name" => "Minsk drop-off" },
        "supplies" => [{ "storage_warehouse" => { "name" => "Minsk storage" } }]
      },
      synced_at: Time.current
    )
    RawOzon::SupplyOrder.create!(
      account: @ozon_account, supply_order_id: "OUTSIDE-#{@token}", status: "COMPLETED",
      items: { "81001" => 50 }, created_at: @time_zone.parse("2026-07-31 09:00"), raw_json: {}
    )

    result = ErpAI::V2::SupplyOrdersFullPeriodContext.new(
      sku: @sku, period_from: Date.new(2026, 8, 3), period_to: Date.new(2026, 8, 9), time_zone: @time_zone
    ).call

    assert_equal 2, result.size
    wb = result.find { |row| row[:platform] == "wb" }
    assert_equal({ supply_id: wb_supply.wb_supply_id, quantity: 12, accepted_quantity: 5, remaining_quantity: 7 }, wb.slice(:supply_id, :quantity, :accepted_quantity, :remaining_quantity))
    assert_equal "boxes", wb.fetch(:packaging)
    assert_equal "Ryazan", wb.fetch(:warehouse_name)
    ozon = result.find { |row| row[:platform] == "ozon" }
    assert_equal({ supply_id: "OZON-#{@token}", quantity: 8, platform_item_id: "81001" }, ozon.slice(:supply_id, :quantity, :platform_item_id))
    assert_equal "Minsk drop-off", ozon.fetch(:origin_warehouse)
    assert_equal "Minsk storage", ozon.fetch(:destination_warehouses)
    assert_equal "2026-08-06T10:00:00Z", ozon.fetch(:timeslot_from)
  end
end
