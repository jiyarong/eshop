require "test_helper"

class Ec::SkuInventoryLevelRetentionTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(
      sku_code: "INV-RETENTION-#{@token}",
      product_name: "Inventory retention test"
    )
    @now = Time.zone.parse("2026-08-18 04:00:00")
  end

  teardown do
    Ec::SkuInventoryLevel.where(sku_code: @sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "deletes only non-latest levels older than the retention period" do
    expired = create_level(account_id: 1, synced_at: @now - 35.days - 1.second, is_latest: false)
    at_cutoff = create_level(account_id: 2, synced_at: @now - 35.days, is_latest: false)
    recent = create_level(account_id: 3, synced_at: @now - 2.days, is_latest: false)
    old_latest = create_level(account_id: 4, synced_at: @now - 60.days, is_latest: true)

    deleted_count = Ec::SkuInventoryLevelRetention.run(now: @now)

    assert_equal 1, deleted_count
    assert_not Ec::SkuInventoryLevel.exists?(expired.id)
    assert Ec::SkuInventoryLevel.exists?(at_cutoff.id)
    assert Ec::SkuInventoryLevel.exists?(recent.id)
    assert Ec::SkuInventoryLevel.exists?(old_latest.id)
  end

  private

  def create_level(account_id:, synced_at:, is_latest:)
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "wb",
      account_id: account_id,
      fulfillment_type: "fbw",
      quantity: account_id,
      synced_at: synced_at,
      is_latest: is_latest
    )
  end
end
