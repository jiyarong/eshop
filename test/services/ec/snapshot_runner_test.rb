require "test_helper"

class Ec::SnapshotRunnerTest < ActiveSupport::TestCase
  setup do
    @snapshot_type = "snapshot-runner-test-#{SecureRandom.hex(6)}"
    @snapshot_date = Date.new(2026, 7, 24)
    @quantity = 3
    @sku = Ec::Sku.create!(sku_code: "SNAPSHOT-RUNNER-#{SecureRandom.hex(6)}", product_name: "Snapshot runner test")
    quantity = -> { @quantity }
    snapshot_type = @snapshot_type
    sku_id = @sku.id

    @snapshot_module = Class.new do
      define_singleton_method(:snapshot_type) { snapshot_type }
      define_singleton_method(:capture) do |snapshot_date:|
        [
          {
            content: { date: snapshot_date.iso8601, scope: "global" }
          },
          {
            sku_id: sku_id,
            content: { date: snapshot_date.iso8601, quantity: quantity.call }
          }
        ]
      end
    end
  end

  teardown do
    Ec::Snapshot.where(snapshot_type: @snapshot_type).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "captures registered modules for the requested date" do
    count = Ec::SnapshotRunner.new(
      snapshot_date: @snapshot_date,
      modules: [ @snapshot_module ]
    ).run

    assert_equal 2, count
    assert_equal(
      { "date" => @snapshot_date.iso8601, "quantity" => 3 },
      Ec::Snapshot.find_by!(snapshot_type: @snapshot_type, snapshot_date: @snapshot_date, sku: @sku).content
    )
    assert_equal "global", Ec::Snapshot.global.find_by!(snapshot_type: @snapshot_type).data[:scope]
  end

  test "replaces the same type and date when rerun" do
    runner = Ec::SnapshotRunner.new(snapshot_date: @snapshot_date, modules: [ @snapshot_module ])
    runner.run
    @quantity = 8

    runner.run

    snapshots = Ec::Snapshot.where(snapshot_type: @snapshot_type, snapshot_date: @snapshot_date, sku: @sku)
    assert_equal 1, snapshots.count
    assert_equal 8, snapshots.first.data[:quantity]
    assert_equal 1, Ec::Snapshot.global.of_type(@snapshot_type).where(snapshot_date: @snapshot_date).count
  end

  test "uses the current Shanghai date by default" do
    travel_to Time.utc(2026, 7, 24, 19) do
      Ec::SnapshotRunner.new(modules: [ @snapshot_module ]).run
    end

    assert Ec::Snapshot.exists?(snapshot_type: @snapshot_type, snapshot_date: Date.new(2026, 7, 25), sku: @sku)
  end

  test "persists each module before capturing the next module" do
    first_type = "#{@snapshot_type}-first"
    second_type = "#{@snapshot_type}-second"
    snapshot_date = @snapshot_date
    sku_id = @sku.id
    first_module = Class.new do
      define_singleton_method(:snapshot_type) { first_type }
      define_singleton_method(:capture) do |snapshot_date:|
        [ { sku_id: sku_id, content: { date: snapshot_date.iso8601 } } ]
      end
    end
    second_module = Class.new do
      define_singleton_method(:snapshot_type) { second_type }
      define_singleton_method(:capture) do |snapshot_date:|
        first_snapshot = Ec::Snapshot.find_by!(
          snapshot_type: first_type,
          snapshot_date: snapshot_date,
          sku_id: sku_id
        )
        [ { sku_id: sku_id, content: { first_snapshot_id: first_snapshot.id } } ]
      end
    end

    assert_equal 2, Ec::SnapshotRunner.new(
      snapshot_date: snapshot_date,
      modules: [ first_module, second_module ]
    ).run
    assert Ec::Snapshot.exists?(snapshot_type: second_type, snapshot_date: snapshot_date, sku_id: sku_id)
  ensure
    Ec::Snapshot.where(snapshot_type: [ first_type, second_type ]).delete_all
  end

  test "prunes snapshots outside a module retention window after writing" do
    retained_module = @snapshot_module
    retained_module.define_singleton_method(:retention_days) { 10 }
    Ec::Snapshot.create!(
      snapshot_type: @snapshot_type,
      snapshot_date: @snapshot_date - 10.days,
      sku: @sku,
      content: { quantity: 1 }
    )
    Ec::Snapshot.create!(
      snapshot_type: @snapshot_type,
      snapshot_date: @snapshot_date - 9.days,
      sku: @sku,
      content: { quantity: 2 }
    )

    Ec::SnapshotRunner.new(snapshot_date: @snapshot_date, modules: [ retained_module ]).run

    assert_not Ec::Snapshot.exists?(
      snapshot_type: @snapshot_type,
      snapshot_date: @snapshot_date - 10.days,
      sku: @sku
    )
    assert Ec::Snapshot.exists?(
      snapshot_type: @snapshot_type,
      snapshot_date: @snapshot_date - 9.days,
      sku: @sku
    )
  end

  test "prunes retained snapshots when a module captures no rows" do
    snapshot_type = @snapshot_type
    empty_module = Class.new do
      define_singleton_method(:snapshot_type) { snapshot_type }
      define_singleton_method(:retention_days) { 10 }
      define_singleton_method(:capture) { |snapshot_date:| [] }
    end
    Ec::Snapshot.create!(
      snapshot_type: @snapshot_type,
      snapshot_date: @snapshot_date - 10.days,
      sku: @sku,
      content: { quantity: 1 }
    )
    Ec::Snapshot.create!(
      snapshot_type: @snapshot_type,
      snapshot_date: @snapshot_date,
      sku: @sku,
      content: { quantity: 2 }
    )

    assert_equal 0, Ec::SnapshotRunner.new(modules: [ empty_module ]).run

    assert_not Ec::Snapshot.exists?(
      snapshot_type: @snapshot_type,
      snapshot_date: @snapshot_date - 10.days,
      sku: @sku
    )
    assert Ec::Snapshot.exists?(
      snapshot_type: @snapshot_type,
      snapshot_date: @snapshot_date,
      sku: @sku
    )
  end
end
