require "test_helper"

class Ec::SkuInventorySnapshotSyncTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "INV-SYNC-#{@token}", product_name: "库存同步测试")
  end

  teardown do
    Ec::SkuInventoryLevel.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuInventoryLevel)
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
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
        metadata: { "source" => "test" }
      }
    ]

    Ec::SkuInventorySnapshotSync.new(snapshot_fetcher: -> { rows }, now: now).run

    first = Ec::SkuInventoryLevel.find_by!(sku_code: @sku.sku_code, platform: "wb", fulfillment_type: "fbw")
    assert first.is_latest?
    assert_equal 7, first.quantity
    assert_equal now, first.synced_at

    Ec::SkuInventorySnapshotSync.new(
      snapshot_fetcher: -> {
        rows.map { |row| row.merge(quantity: 11, synced_at: now + 1.hour) }
      },
      now: now + 1.hour
    ).run

    levels = Ec::SkuInventoryLevel.where(sku_code: @sku.sku_code, platform: "wb", fulfillment_type: "fbw").order(:synced_at)
    assert_equal 2, levels.count
    assert_not levels.first.is_latest?
    assert levels.last.is_latest?
    assert_equal 11, levels.last.quantity
  end
end
