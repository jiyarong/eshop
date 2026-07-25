require "test_helper"

class BackfillInventorySnapshotsTest < ActiveSupport::TestCase
  SCRIPT_PATH = Rails.root.join("script/backfill_inventory_snapshots.rb")

  test "runs the snapshot runner for every requested date" do
    captured_dates = []

    with_environment("FROM_DATE" => "2026-07-22", "TO_DATE" => "2026-07-24") do
      with_stubbed_snapshot_runner_constructor(captured_dates) { load SCRIPT_PATH }
    end

    assert_equal(
      [ Date.new(2026, 7, 22), Date.new(2026, 7, 23), Date.new(2026, 7, 24) ],
      captured_dates
    )
  end

  private

  def with_environment(values)
    previous_values = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous_values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def with_stubbed_snapshot_runner_constructor(captured_dates)
    singleton_class = Ec::SnapshotRunner.singleton_class
    original_method = singleton_class.instance_method(:new)
    singleton_class.send(:define_method, :new) do |snapshot_date:, modules:|
      captured_dates << snapshot_date
      raise "unexpected snapshot modules" unless modules == [ Ec::InventorySnapshot ]

      Struct.new(:run).new(1)
    end

    yield
  ensure
    singleton_class.send(:define_method, :new, original_method)
  end
end
