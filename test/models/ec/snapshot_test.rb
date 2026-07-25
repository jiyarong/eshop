require "test_helper"

class Ec::SnapshotTest < ActiveSupport::TestCase
  setup do
    @snapshot_type = "snapshot-test-#{SecureRandom.hex(6)}"
    @snapshot_date = Date.new(2026, 7, 24)
    @sku = Ec::Sku.create!(sku_code: "SNAPSHOT-#{SecureRandom.hex(6)}", product_name: "Snapshot test")
  end

  teardown do
    Ec::Snapshot.where(snapshot_type: @snapshot_type).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "fetch returns nested content with indifferent access" do
    Ec::Snapshot.create!(
      snapshot_date: @snapshot_date,
      snapshot_type: @snapshot_type,
      content: { "summary" => { "quantity" => 12 } }
    )

    content = Ec::Snapshot.fetch(@snapshot_type, on: @snapshot_date)

    assert_equal 12, content.dig(:summary, :quantity)
    assert_equal 12, content.dig("summary", "quantity")
  end

  test "fetch returns content for a specific sku" do
    Ec::Snapshot.create!(
      snapshot_date: @snapshot_date,
      snapshot_type: @snapshot_type,
      sku: @sku,
      content: { "quantity" => 12 }
    )

    assert_equal 12, Ec::Snapshot.fetch(@snapshot_type, on: @snapshot_date, sku: @sku)[:quantity]
    assert_equal @sku, Ec::Snapshot.for_sku(@sku).find_by!(snapshot_type: @snapshot_type).sku
    assert_equal 1, @sku.snapshots.of_type(@snapshot_type).count
  end

  test "allows one global and one snapshot per sku for each type and date" do
    Ec::Snapshot.create!(
      snapshot_date: @snapshot_date,
      snapshot_type: @snapshot_type,
      content: {}
    )

    sku_snapshot = Ec::Snapshot.create!(
      snapshot_date: @snapshot_date,
      snapshot_type: @snapshot_type,
      sku: @sku,
      content: {}
    )
    duplicate = sku_snapshot.dup

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:snapshot_type, :taken)
    assert_equal 1, Ec::Snapshot.global.of_type(@snapshot_type).count
  end
end
