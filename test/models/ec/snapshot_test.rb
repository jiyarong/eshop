require "test_helper"

class Ec::SnapshotTest < ActiveSupport::TestCase
  setup do
    @snapshot_type = "snapshot-test-#{SecureRandom.hex(6)}"
    @snapshot_date = Date.new(2026, 7, 24)
  end

  teardown do
    Ec::Snapshot.where(snapshot_type: @snapshot_type).delete_all
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

  test "allows only one snapshot per type and date" do
    Ec::Snapshot.create!(
      snapshot_date: @snapshot_date,
      snapshot_type: @snapshot_type,
      content: {}
    )

    duplicate = Ec::Snapshot.new(
      snapshot_date: @snapshot_date,
      snapshot_type: @snapshot_type,
      content: {}
    )

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:snapshot_type, :taken)
  end
end
