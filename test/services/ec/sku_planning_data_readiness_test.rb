require "test_helper"

class Ec::SkuPlanningDataReadinessTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "READINESS-#{@token}", product_name: "Readiness")
    @start = Date.new(2026, 9, 21)
    @zone = Time.find_zone!(Ec::SkuOperationPlan::TIME_ZONE)
    @account = RawWb::SellerAccount.create!(name: "Ready #{@token}", api_token: "test-#{@token}", company_type: "small")
    @store = Ec::Store.create!(platform: "wb", store_name: "Ready #{@token}", company_type: "small", is_active: true, wb_raw_account_id: @account.id)
    @product = @sku.sku_products.create!(store: @store, product_id: "READY-#{@token}")
    @original_rate = Ec::WeeklyRate.method(:exists?)
    @original_report = Ec::WeeklyProfitReportQuery.method(:run)
    Ec::WeeklyRate.define_singleton_method(:exists?) { |**| true }
    Ec::WeeklyProfitReportQuery.define_singleton_method(:run) { |**| { rows: [] } }
    travel_to @zone.local(2026, 9, 29, 3, 30)
  end

  teardown do
    travel_back
    Ec::WeeklyRate.define_singleton_method(:exists?, @original_rate)
    Ec::WeeklyProfitReportQuery.define_singleton_method(:run, @original_report)
    RawWb::SyncTask.where(account_id: @account.id).delete_all
    RawWb::StatsSale.where(account_id: @account.id).delete_all
    @sku.sku_operation_plans.delete_all
    @product.delete
    @store.delete
    @account.delete
    @sku.delete
  end

  test "rejects missing, stale, failed or incomplete source syncs" do
    assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
    task = source_task(created_at: @zone.local(2026, 9, 28, 16))
    assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
    task.update!(created_at: @zone.local(2026, 9, 28, 19), status: "partial",
      results: task.results.merge("sync_finance_details" => { "error" => "late report" }))
    assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
    task.update!(status: "running")
    assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
  end

  test "accepts a completed refresh including a valid zero activity report" do
    source_task
    assert check!
  end

  test "does not proceed before Monday 18 even with successful sources" do
    source_task
    travel_to @zone.local(2026, 9, 28, 17) do
      assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
    end
  end

  test "rejects a sync that does not cover the previous week" do
    task = source_task
    task.update!(results: task.results.merge("period" => { "from_date" => "2026-09-28", "to_date" => "2026-09-28" }))
    assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
  end

  test "does not shorten an open historical deadline or block other plans" do
    source_task
    @sku.sku_operation_plans.create!(plan_date: @start, execution_deadline: @start + 8.days,
      target: "price", operation: "maintain", referer: ["risk"], message: "Keep price")
    assert check!
  end

  test "waits for a local rate and records report failures" do
    source_task
    Ec::WeeklyRate.define_singleton_method(:exists?) { |**| false }
    assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
    Ec::WeeklyRate.define_singleton_method(:exists?) { |**| true }
    Ec::WeeklyProfitReportQuery.define_singleton_method(:run) { |**| raise "missing profit dependency" }
    error = assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
    assert_includes error.message, "missing profit dependency"
  end

  test "waits for publication when WB has sales but no weekly settlement report" do
    source_task
    RawWb::StatsSale.create!(account: @account, sale_id: @token, sale_date: @zone.local(2026, 9, 27, 23), nm_id: 123)
    error = assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
    assert_includes error.message, "not published"
  end

  test "waits for Ozon accrual and optional performance completion" do
    source_task
    account = RawOzon::SellerAccount.create!(client_id: "ready-#{@token}", api_key: @token, company_type: "small")
    store = Ec::Store.create!(platform: "ozon", store_name: "Ozon ready #{@token}", company_type: "small",
      is_active: true, ozon_raw_account_id: account.id, ozon_performance_client_id: "perf-#{@token}")
    product = @sku.sku_products.create!(store: store, product_id: @token)
    assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
    task = RawOzon::SyncTask.create!(account: account, sync_type: "daily", status: "done",
      started_at: @zone.local(2026, 9, 28, 19), finished_at: @zone.local(2026, 9, 28, 20),
      results: { sync_finance_accrual_by_day: { ok: 0 }, period: { from_date: @start.iso8601, to_date: (@start + 7.days).iso8601 } })
    assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
    task.dup.tap do |ads|
      ads.sync_type = "performance"
      ads.results = Ec::SkuPlanningDataReadiness::OZON_AD_STEPS.index_with { { ok: 0 } }
        .merge(period: { from_date: @start.iso8601, to_date: (@start + 6.days).iso8601 })
      ads.save!
    end
    assert check!
  ensure
    RawOzon::SyncTask.where(account_id: account&.id).delete_all
    product&.delete
    store&.delete
    account&.delete
  end

  private

  def check!
    Ec::SkuPlanningDataReadiness.check!(as_of_date: @start + 8.days, sku_code: @sku.sku_code)
  end

  def source_task(created_at: @zone.local(2026, 9, 28, 19))
    results = Ec::SkuPlanningDataReadiness::WB_STEPS.index_with { { ok: 0 } }
    RawWb::SyncTask.create!(account: @account, task_type: "weekly_sync", status: "done",
      created_at: created_at, completed_at: created_at + 1.hour,
      results: results.merge(period: { from_date: @start.iso8601, to_date: (@start + 7.days).iso8601 }))
  end
end
