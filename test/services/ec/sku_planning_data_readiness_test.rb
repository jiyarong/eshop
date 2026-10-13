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
    @original_report = Ec::WeeklyProfitReportQuery.method(:run)
    @report_calls = []
    calls = @report_calls
    Ec::WeeklyProfitReportQuery.define_singleton_method(:run) do |**arguments|
      calls << arguments
      { rows: [] }
    end
    travel_to @zone.local(2026, 9, 29, 3, 30)
  end

  teardown do
    travel_back
    Ec::WeeklyProfitReportQuery.define_singleton_method(:run, @original_report)
    RawWb::StatsSale.where(account_id: @account.id).delete_all
    @product.delete
    @store.delete
    @account.delete
    @sku.delete
  end

  test "accepts a queryable zero activity report without source sync logs" do
    assert check!
    assert_equal({
      store_ref: "wb:#{@account.id}", from_date: @start, to_date: @start + 6.days,
      sku_codes: [@sku.sku_code], include_comparison: false
    }, @report_calls.sole)
  end

  test "accepts a queryable WB report without a weekly settlement publication check" do
    RawWb::StatsSale.create!(account: @account, sale_id: @token, sale_date: @zone.local(2026, 9, 27, 23), nm_id: 123)

    assert check!
  end

  test "accepts a queryable report before Monday 18" do
    travel_to @zone.local(2026, 9, 28, 13, 30) do
      assert check!
    end
  end

  test "waits when the weekly profit report cannot be queried" do
    Ec::WeeklyProfitReportQuery.define_singleton_method(:run) { |**| raise "missing profit dependency" }

    error = assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
    assert_includes error.message, "profit report failed: RuntimeError: missing profit dependency"
  end

  test "missing exchange rate is reported through the profit query" do
    Ec::WeeklyProfitReportQuery.define_singleton_method(:run, @original_report)
    original_rate = Ec::WeeklyRate.method(:find_by)
    requested_week = nil
    Ec::WeeklyRate.define_singleton_method(:find_by) do |week_start:|
      requested_week = week_start
      nil
    end

    error = assert_raises(Ec::SkuPlanningDataReadiness::NotReady) { check! }
    assert_includes error.message, "missing_weekly_rate"
    assert_equal @start, requested_week
  ensure
    Ec::WeeklyRate.define_singleton_method(:find_by, original_rate) if original_rate
  end

  test "queries only active stores linked to the requested SKU" do
    @store.update!(is_active: false)

    assert check!
    assert_empty @report_calls
  end

  test "accepts an actual Ozon report without accrual or advertising sync completion checks" do
    account = RawOzon::SellerAccount.create!(client_id: "ready-#{@token}", api_key: @token, company_type: "small", is_active: true)
    store = Ec::Store.create!(platform: "ozon", store_name: "Ozon ready #{@token}", company_type: "small",
      is_active: true, ozon_raw_account_id: account.id, ozon_performance_client_id: "perf-#{@token}")
    platform_sku_id = rand(10_000_000..99_999_999)
    product = @sku.sku_products.create!(store: store, product_id: @token, platform_sku_id: platform_sku_id)
    RawOzon::AccrualByDay.create!(account: account, accrual_date: @start, type_id: 0,
      ozon_sku_id: platform_sku_id, posting_number: "posting-#{@token}", amount: 100,
      accrued_category: "POSTING", synced_at: Time.current)
    original_rate = Ec::WeeklyRate.method(:find_by)
    rate = Ec::WeeklyRate.new(week_start: @start, rate_cny_rub: 10, rate_byn_rub: 5)
    Ec::WeeklyRate.define_singleton_method(:find_by) { |**| rate }
    original_report = @original_report
    reports = []
    Ec::WeeklyProfitReportQuery.define_singleton_method(:run) do |**arguments|
      if arguments[:store_ref] == "ozon:#{account.id}"
        original_report.call(**arguments).tap { |report| reports << report }
      else
        { rows: [] }
      end
    end

    assert check!
    assert_equal @sku.sku_code, reports.sole[:rows].sole[:sku_code]
    assert_equal 100, reports.sole[:rows].sole[:sales_revenue]
  ensure
    Ec::WeeklyRate.define_singleton_method(:find_by, original_rate) if original_rate
    RawOzon::AccrualByDay.where(account_id: account.id).delete_all if account
    product&.delete
    store&.delete
    account&.delete
  end

  private

  def check!
    Ec::SkuPlanningDataReadiness.check!(as_of_date: @start + 8.days, sku_code: @sku.sku_code)
  end
end
