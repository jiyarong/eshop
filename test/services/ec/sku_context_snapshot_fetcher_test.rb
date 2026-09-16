require "test_helper"

class Ec::SkuContextSnapshotFetcherTest < ActiveSupport::TestCase
  class FakeSnapshotBuilder
    class << self
      attr_accessor :calls
    end

    def self.snapshot_type
      Ec::SkuContextSnapshot.snapshot_type
    end

    def self.retention_days
      Ec::SkuContextSnapshot.retention_days
    end

    def self.capture_for(sku:, snapshot_date:)
      self.calls = calls.to_i + 1
      {
        sku_id: sku.id,
        content: {
          sku_code: sku.sku_code,
          period: { as_of: snapshot_date.iso8601 },
          categories: {}
        }
      }
    end
  end

  class RecordingLock
    attr_reader :calls

    def initialize(&before_yield)
      @before_yield = before_yield
      @calls = []
    end

    def with_lock(name, wait:, logger:)
      calls << { name: name, wait: wait, logger: logger }
      @before_yield&.call
      yield
    end
  end

  setup do
    @sku = Ec::Sku.create!(
      sku_code: "SKU-CONTEXT-FETCHER-#{SecureRandom.hex(6)}",
      product_name: "SKU context fetcher test"
    )
    @snapshot_date = Date.new(2026, 9, 16)
    FakeSnapshotBuilder.calls = 0
  end

  teardown do
    Ec::Snapshot.where(snapshot_type: Ec::SkuContextSnapshot.snapshot_type, sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "returns today's snapshot without acquiring a lock" do
    create_snapshot(@snapshot_date, marker: "existing")
    lock = Object.new
    lock.define_singleton_method(:with_lock) { |*, **| raise "lock should not be acquired" }

    data = fetcher(lock: lock).call

    assert_equal "existing", data[:marker]
    assert_equal 0, FakeSnapshotBuilder.calls
  end

  test "generates and persists today's snapshot while holding a SKU date lock" do
    lock = RecordingLock.new

    data = fetcher(lock: lock).call

    assert_equal @sku.sku_code, data[:sku_code]
    assert_equal @snapshot_date.iso8601, data.dig(:period, :as_of)
    assert_equal 1, FakeSnapshotBuilder.calls
    assert_equal(
      [ {
        name: "ec:sku_context_snapshot:#{@sku.id}:#{@snapshot_date.iso8601}",
        wait: true,
        logger: Rails.logger
      } ],
      lock.calls
    )
    assert Ec::Snapshot.exists?(
      snapshot_type: Ec::SkuContextSnapshot.snapshot_type,
      snapshot_date: @snapshot_date,
      sku: @sku
    )
  end

  test "rechecks after acquiring the lock instead of generating twice" do
    lock = RecordingLock.new { create_snapshot(@snapshot_date, marker: "concurrent") }

    data = fetcher(lock: lock).call

    assert_equal "concurrent", data[:marker]
    assert_equal 0, FakeSnapshotBuilder.calls
  end

  test "uses the current Shanghai date by default" do
    lock = RecordingLock.new

    travel_to Time.utc(2026, 9, 16, 16, 30) do
      data = Ec::SkuContextSnapshotFetcher.new(
        sku: @sku,
        snapshot_builder: FakeSnapshotBuilder,
        lock: lock
      ).call

      assert_equal "2026-09-17", data.dig(:period, :as_of)
    end
  end

  test "prunes snapshots older than the latest ten-day window" do
    create_snapshot(@snapshot_date - 10.days, marker: "expired")
    create_snapshot(@snapshot_date - 9.days, marker: "retained")

    fetcher(lock: RecordingLock.new).call

    assert_not Ec::Snapshot.exists?(
      snapshot_type: Ec::SkuContextSnapshot.snapshot_type,
      snapshot_date: @snapshot_date - 10.days,
      sku: @sku
    )
    assert Ec::Snapshot.exists?(
      snapshot_type: Ec::SkuContextSnapshot.snapshot_type,
      snapshot_date: @snapshot_date - 9.days,
      sku: @sku
    )
  end

  private

  def fetcher(lock:)
    Ec::SkuContextSnapshotFetcher.new(
      sku: @sku,
      snapshot_date: @snapshot_date,
      snapshot_builder: FakeSnapshotBuilder,
      lock: lock
    )
  end

  def create_snapshot(date, **content)
    Ec::Snapshot.create!(
      snapshot_type: Ec::SkuContextSnapshot.snapshot_type,
      snapshot_date: date,
      sku: @sku,
      content: content
    )
  end
end
