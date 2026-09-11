require "test_helper"

class ErpAI::V3::SupplyOrdersFullPeriodContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    @sku = Ec::Sku.create!(sku_code: "V3-SUPPLY-#{@token}", product_name: "V3 Supply context")
    @wb_account = RawWb::SellerAccount.create!(
      name: "V3 Supply WB #{@token}", api_token: "wb-#{@token}", company_type: :small
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "V3 Supply Ozon #{@token}", client_id: "oz-#{@token}", api_key: "key-#{@token}",
      company_type: :small
    )
    @wb_store = Ec::Store.create!(
      platform: "wb", store_name: "V3 WB #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon", store_name: "V3 Ozon #{@token}", company_type: "small",
      ozon_raw_account_id: @ozon_account.id
    )
    @wb_product = Ec::SkuProduct.create!(sku: @sku, store: @wb_store, product_id: "71001")
    @ozon_product = Ec::SkuProduct.create!(
      sku: @sku, store: @ozon_store, product_id: "OZON-#{@token}", platform_sku_id: "81001"
    )
  end

  teardown do
    RawWb::SupplyItem.where(account_id: @wb_account&.id).delete_all
    RawWb::Supply.where(account_id: @wb_account&.id).delete_all
    RawOzon::WarehouseCluster.where(account_id: @ozon_account&.id).delete_all
    RawOzon::SupplyOrderItem.where(supply_order_id: RawOzon::SupplyOrder.where(account_id: @ozon_account&.id)).delete_all
    RawOzon::SupplyOrder.where(account_id: @ozon_account&.id).delete_all
    Ec::SkuProduct.where(id: [@wb_product&.id, @ozon_product&.id]).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id]).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "returns supply rows using the current drawer report columns within the requested period" do
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
    ozon_order = RawOzon::SupplyOrder.create!(
      account: @ozon_account, supply_order_id: "OZON-#{@token}", status: "IN_TRANSIT",
      items: { "81001" => 8 },
      created_at: @time_zone.parse("2026-08-04 09:00"),
      timeslot: { "from" => "2026-08-06T10:00:00Z", "to" => "2026-08-06T12:00:00Z" },
      raw_json: {
        "order_number" => "ORDER-#{@token}",
        "drop_off_warehouse" => { "name" => "Minsk drop-off" },
        "state_updated_date" => "2026-08-04T12:00:00Z"
      },
      synced_at: Time.current
    )
    RawOzon::WarehouseCluster.create!(
      account: @ozon_account, warehouse_id: 91_001, warehouse_name: "Minsk cluster warehouse",
      cluster_name: "Minsk cluster", macrolocal_cluster_id: 4007, synced_at: Time.current
    )
    ozon_order.supply_order_items.create!(
      ozon_supply_id: 2_000_064_845_539, bundle_id: "bundle-context", state: "IN_TRANSIT",
      platform_sku_id: 81_001, quantity: 8, macrolocal_cluster_id: 4007,
      storage_warehouse_id: 82_001, storage_warehouse_name: "Minsk storage", synced_at: Time.current
    )
    RawOzon::SupplyOrder.create!(
      account: @ozon_account, supply_order_id: "OUTSIDE-#{@token}", status: "COMPLETED",
      items: { "81001" => 50 }, created_at: @time_zone.parse("2026-07-31 09:00"), raw_json: {}
    )

    result = ErpAI::V3::SupplyOrdersFullPeriodContext.new(
      sku: @sku, period_from: Date.new(2026, 8, 3), period_to: Date.new(2026, 8, 9), time_zone: @time_zone
    ).call

    assert_equal 2, result.size
    wb = result.find { |row| row[:platform] == "wb" }
    assert_equal "V3 WB #{@token}", wb.fetch(:store_name)
    assert_equal SupplyOrderReports::ReportQuery::WB_COLUMNS, wb.except(:platform, :store_id, :store_name).keys
    assert_equal({ supply_id: wb_supply.wb_supply_id, packaging: 1, quantity: 12, accepted_quantity: 5, remaining_quantity: 7 },
      wb.slice(:supply_id, :packaging, :quantity, :accepted_quantity, :remaining_quantity))

    ozon = result.find { |row| row[:platform] == "ozon" }
    assert_equal SupplyOrderReports::ReportQuery::OZON_COLUMNS, ozon.except(:platform, :store_id, :store_name).keys
    assert_equal(
      {
        order_number: "ORDER-#{@token}",
        supply_id: 2_000_064_845_539,
        status: "IN_TRANSIT",
        platform_item_id: "81001",
        quantity: 8,
        destination_cluster: "Minsk cluster",
        destination_warehouse: "Minsk storage",
        timeslot: { "from" => "2026-08-06T10:00:00Z", "to" => "2026-08-06T12:00:00Z" },
        origin_warehouse: "Minsk drop-off",
        state_updated_at: "2026-08-04T12:00:00Z"
      },
      ozon.slice(:order_number, :supply_id, :status, :platform_item_id, :quantity, :destination_cluster,
        :destination_warehouse, :timeslot, :origin_warehouse, :state_updated_at)
    )
    assert_not ozon.key?(:parent_supply_order_id)
    assert_not ozon.key?(:bundle_id)
    assert_not ozon.key?(:timeslot_from)
    assert_not ozon.key?(:destination_warehouse_id)
  end
end
