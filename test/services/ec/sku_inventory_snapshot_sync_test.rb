require "test_helper"

class Ec::SkuInventorySnapshotSyncTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "INV-SYNC-#{@token}", product_name: "库存同步测试")
  end

  teardown do
    Ec::OperationAction.where(ec_sku_id: @sku&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::SkuInventoryLevel.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuInventoryLevel)
    Ec::Store.where(id: @store&.id).delete_all if @store
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserRole.where(user_id: @admin&.id).delete_all if @admin
    @admin&.delete
  end

  test "creates historical rows and keeps only the newest row latest per sku store and kind" do
    now = Time.zone.parse("2026-06-22 10:00:00")
    rows = [
      {
        sku_code: @sku.sku_code,
        platform: "wb",
        account_id: 1,
        store_name: "WB Test #{@token}",
        fulfillment_type: "fbw",
        quantity: 7,
        synced_at: now,
        metadata: { "source" => "test" },
        warehouse_breakdown: [
          { "warehouse_name" => "WB Warehouse A", "quantity" => 4 },
          { "warehouse_name" => "WB Warehouse B", "quantity" => 3 }
        ]
      }
    ]

    Ec::SkuInventorySnapshotSync.new(snapshot_fetcher: -> { rows }, now: now).run

    first = Ec::SkuInventoryLevel.find_by!(sku_code: @sku.sku_code, platform: "wb", fulfillment_type: "fbw")
    assert first.is_latest?
    assert_equal 7, first.quantity
    assert_equal now, first.synced_at
    assert_equal [
      { "warehouse_name" => "WB Warehouse A", "quantity" => 4 },
      { "warehouse_name" => "WB Warehouse B", "quantity" => 3 }
    ], first.warehouse_breakdown

    Ec::SkuInventorySnapshotSync.new(
      snapshot_fetcher: -> {
        rows.map do |row|
          row.merge(
            quantity: 11,
            synced_at: now + 1.hour,
            warehouse_breakdown: [
              { "warehouse_name" => "WB Warehouse A", "quantity" => 8 },
              { "warehouse_name" => "WB Warehouse B", "quantity" => 3 }
            ]
          )
        end
      },
      now: now + 1.hour
    ).run

    levels = Ec::SkuInventoryLevel.where(sku_code: @sku.sku_code, platform: "wb", fulfillment_type: "fbw").order(:synced_at)
    assert_equal 2, levels.count
    assert_not levels.first.is_latest?
    assert levels.last.is_latest?
    assert_equal 11, levels.last.quantity
    assert_equal [
      { "warehouse_name" => "WB Warehouse A", "quantity" => 8 },
      { "warehouse_name" => "WB Warehouse B", "quantity" => 3 }
    ], levels.last.warehouse_breakdown
  end

  test "skips invalid rows without blocking valid inventory refresh" do
    now = Time.zone.parse("2026-06-22 11:00:00")
    invalid_sku_code = "INV-MISSING-#{@token}"
    rows = [
      {
        sku_code: invalid_sku_code,
        platform: "ozon",
        account_id: 1,
        store_name: "Ozon Test #{@token}",
        fulfillment_type: "fbo",
        quantity: 9,
        synced_at: now,
        metadata: { "source" => "missing_sku" }
      },
      {
        sku_code: @sku.sku_code,
        platform: "ozon",
        account_id: 1,
        store_name: "Ozon Test #{@token}",
        fulfillment_type: "fbo",
        quantity: 48,
        synced_at: now,
        metadata: { "source" => "valid_sku" }
      }
    ]

    count = Ec::SkuInventorySnapshotSync.new(snapshot_fetcher: -> { rows }, now: now).run

    assert_equal 1, count
    assert_nil Ec::SkuInventoryLevel.find_by(sku_code: invalid_sku_code)
    level = Ec::SkuInventoryLevel.find_by!(sku_code: @sku.sku_code, platform: "ozon", fulfillment_type: "fbo")
    assert level.is_latest?
    assert_equal 48, level.quantity
  end

  test "records successful inbound quantity increases and decreases after the baseline snapshot" do
    @admin = User.create!(email: "inventory-action-#{@token}@example.com", password: "password123")
    @admin.roles << Role.find_by!(code: "super_admin")
    @store = Ec::Store.create!(
      platform: "wb", store_name: "WB inbound #{@token}", company_type: "small", is_active: true
    )
    Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "INBOUND-#{@token}")
    start_time = Time.zone.parse("2026-07-30 10:00:00")

    assert_no_difference "Ec::OperationAction.count" do
      sync_inbound_snapshot(quantity: 0, now: start_time)
    end

    assert_difference "Ec::OperationAction.count", 1 do
      sync_inbound_snapshot(quantity: 12, now: start_time + 1.hour)
    end
    increase = Ec::OperationAction.order(:id).last
    assert_equal "sku_inbound_change", increase.operation_type
    assert_equal "12.0", increase.diff_result.dig("inbound_change", "delta")
    assert_equal "shipment_started", increase.diff_result.dig("inbound_change", "inferred_event")
    assert_equal({ "from" => "0.0", "to" => "12.0" }, increase.diff_result.dig("fields", "platform_inbound_quantity"))

    assert_difference "Ec::OperationAction.count", 1 do
      sync_inbound_snapshot(quantity: 5, now: start_time + 2.hours)
    end
    decrease = Ec::OperationAction.order(:id).last
    assert_equal "-7.0", decrease.diff_result.dig("inbound_change", "delta")
    assert_equal "shipment_arrived", decrease.diff_result.dig("inbound_change", "inferred_event")
    assert_equal({ "from" => "12.0", "to" => "5.0" }, decrease.diff_result.dig("fields", "platform_inbound_quantity"))
  end

  private

  def sync_inbound_snapshot(quantity:, now:)
    row = {
      sku_code: @sku.sku_code,
      platform: "wb",
      account_id: 99,
      store_id: @store.id,
      store_name: @store.store_name,
      fulfillment_type: "inbound",
      quantity:,
      synced_at: now,
      metadata: { source: "test" }
    }
    Ec::SkuInventorySnapshotSync.new(snapshot_fetcher: -> { [row] }, now:).run
  end
end
