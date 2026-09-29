require "test_helper"

class Ec::SkuPlanningCycleLockTest < ActiveSupport::TestCase
  setup do
    @sku = Ec::Sku.create!(sku_code: "CYCLE-#{SecureRandom.hex(4)}", product_name: "Cycle test")
    @period_start = Date.new(2026, 9, 28)
  end

  teardown do
    @sku.sku_operation_plans.delete_all
    @sku.planning_cycles.delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "requires a monday through sunday period" do
    cycle = @sku.planning_cycles.new(period_start: @period_start + 1.day, period_end: @period_start + 8.days)

    assert_not cycle.valid?
    assert cycle.errors[:period_start].any?
    assert cycle.errors[:period_end].any?
  end

  test "reuses the current cycle idempotently" do
    first = Ec::SkuPlanningCycleLock.acquire(sku: @sku, period_start: @period_start)
    second = Ec::SkuPlanningCycleLock.acquire(sku: @sku, period_start: @period_start)

    assert_equal first.id, second.id
    assert_equal 1, @sku.planning_cycles.count
    assert first.is_current?
    assert_equal "pending", first.status
  end

  test "rerun creates a new current revision and preserves history" do
    first = Ec::SkuPlanningCycleLock.acquire(sku: @sku, period_start: @period_start, status: "active")
    second = Ec::SkuPlanningCycleLock.acquire(sku: @sku, period_start: @period_start, rerun: true)

    assert_equal 2, second.revision
    assert_not first.reload.is_current?
    assert second.is_current?
    assert_equal [ 1, 2 ], @sku.planning_cycles.order(:revision).pluck(:revision)
  end

  test "plans can be associated with a cycle" do
    cycle = Ec::SkuPlanningCycleLock.acquire(sku: @sku, period_start: @period_start)
    plan = @sku.sku_operation_plans.create!(
      planning_cycle: cycle,
      target: "price", operation: "maintain", referer: [ "event-1" ], message: "Keep price",
      reason: "Stable", baseline: "Current", constraints: "None", expected_effect: "Stable"
    )

    assert_equal [ plan.id ], cycle.reload.operation_plans.pluck(:id)
  end
end
