require "test_helper"

class Ec::SnapshotRunnerTest < ActiveSupport::TestCase
  setup do
    @snapshot_type = "snapshot-runner-test-#{SecureRandom.hex(6)}"
    @snapshot_date = Date.new(2026, 7, 24)
    @quantity = 3
    quantity = -> { @quantity }
    snapshot_type = @snapshot_type

    @snapshot_module = Class.new do
      define_singleton_method(:snapshot_type) { snapshot_type }
      define_singleton_method(:capture) do |snapshot_date:|
        { date: snapshot_date.iso8601, quantity: quantity.call }
      end
    end
  end

  teardown do
    Ec::Snapshot.where(snapshot_type: @snapshot_type).delete_all
  end

  test "captures registered modules for the requested date" do
    count = Ec::SnapshotRunner.new(
      snapshot_date: @snapshot_date,
      modules: [ @snapshot_module ]
    ).run

    assert_equal 1, count
    assert_equal(
      { "date" => @snapshot_date.iso8601, "quantity" => 3 },
      Ec::Snapshot.find_by!(snapshot_type: @snapshot_type, snapshot_date: @snapshot_date).content
    )
  end

  test "replaces the same type and date when rerun" do
    runner = Ec::SnapshotRunner.new(snapshot_date: @snapshot_date, modules: [ @snapshot_module ])
    runner.run
    @quantity = 8

    runner.run

    snapshots = Ec::Snapshot.where(snapshot_type: @snapshot_type, snapshot_date: @snapshot_date)
    assert_equal 1, snapshots.count
    assert_equal 8, snapshots.first.data[:quantity]
  end

  test "uses the current Shanghai date by default" do
    travel_to Time.utc(2026, 7, 24, 19) do
      Ec::SnapshotRunner.new(modules: [ @snapshot_module ]).run
    end

    assert Ec::Snapshot.exists?(snapshot_type: @snapshot_type, snapshot_date: Date.new(2026, 7, 25))
  end
end
