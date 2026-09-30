require "test_helper"

class RawWb::SalesReportsSyncTest < ActiveSupport::TestCase
  setup do
    unique = SecureRandom.hex(4)
    @account = RawWb::SellerAccount.create!(
      name: "WB report sync #{unique}",
      api_token: "wb-report-sync-#{unique}",
      is_active: true,
      company_type: :small
    )
    @sync = RawWb::WeeklySync.new(@account, days: 7)
  end

  teardown do
    RawWb::SyncTask.where(account_id: @account.id).delete_all
    RawWb::FinanceDetail.where(account_id: @account.id).delete_all
    RawWb::SalesReport.where(account_id: @account.id).destroy_all
    @account.destroy
  end

  test "maps current camel case settlement report fields" do
    row = @sync.send(:build_sales_report, {
      "reportId" => 835_651_868,
      "dateFrom" => "2026-09-01",
      "dateTo" => "2026-09-06",
      "createDate" => "2026-09-07",
      "retailAmountSum" => "40100.00",
      "forPaySum" => "30167.99",
      "deliveryServiceSum" => "4327.89",
      "paidStorageSum" => "66.79",
      "deductionSum" => "4233.00",
      "penaltySum" => "310.65",
      "additionalPaymentSum" => "0.00",
      "bankPaymentSum" => "21229.66"
    })

    assert_equal 835_651_868, row[:wb_report_id]
    assert_equal "2026-09-01", row[:date_from]
    assert_equal BigDecimal("30167.99"), row[:for_pay_sum]
    assert_equal BigDecimal("21229.66"), row[:bank_payment_sum]
    assert_equal row[:bank_payment_sum], row[:net_payable]
  end

  test "maps report ownership and settlement dates on finance details" do
    row = @sync.send(:build_finance_detail, {
      "rrdId" => 123_456,
      "reportId" => 835_651_868,
      "nmId" => 987_654,
      "sellerOperName" => "Продажа",
      "forPay" => "100.25",
      "additionalPayment" => "3.10",
      "saleDt" => "2026-08-31",
      "rrDate" => "2026-09-01"
    })

    assert_equal 835_651_868, row[:wb_report_id]
    assert_equal Date.new(2026, 8, 31), row[:sale_dt]
    assert_equal Date.new(2026, 9, 1), row[:rr_dt]
    assert_equal 3.10, row[:additional_payment]
  end

  test "retries only the current finance chunk after rate limiting" do
    calls = 0
    response = [{
      "rrdId" => 987_654,
      "reportId" => 835_651_868,
      "nmId" => 123_456,
      "sellerOperName" => "Продажа",
      "forPay" => "42.50",
      "saleDt" => Date.current.iso8601,
      "rrDate" => Date.current.iso8601
    }]
    client = Object.new
    client.define_singleton_method(:post) do |*_args|
      calls += 1
      raise RawWb::WbClient::RetryableError.new("limited", retry_after: 1) if calls == 1

      response
    end
    @sync.instance_variable_set(:@client, client)
    @sync.instance_variable_set(:@from, Date.current)
    @sync.define_singleton_method(:sleep) { |_seconds| }

    assert_equal 1, @sync.send(:sync_finance_details)
    assert_equal 2, calls
    detail = RawWb::FinanceDetail.find_by!(account_id: @account.id, rrdid: 987_654)
    assert_equal 835_651_868, detail.wb_report_id
    assert_equal Date.current, detail.rr_dt
  end

  test "persists completed source coverage and records failed steps" do
    @sync.define_singleton_method(:sleep) { |_| }
    @sync.define_singleton_method(:sync_sales_reports) { 0 }
    @sync.define_singleton_method(:sync_finance_details) { raise "late finance report" }
    result = @sync.run(sync_keys: %i[sync_sales_reports sync_finance_details])
    task = RawWb::SyncTask.where(account_id: @account.id).sole
    assert_equal "partial", task.status
    assert_equal "weekly_sync", task.task_type
    assert_equal 0, task.results.dig("sync_sales_reports", "ok")
    assert_equal "late finance report", task.results.dig("sync_finance_details", "error")
    assert_equal Date.current.iso8601, task.results.dig("period", "to_date")
    assert task.completed_at.present?
    assert_equal({ error: "late finance report" }, result[:sync_finance_details])
  end

  test "does not treat exhausted storage download retries as a successful empty report" do
    client = Object.new
    client.define_singleton_method(:get) { |*| raise RawWb::WbClient::RetryableError.new("limited", retry_after: 1) }
    @sync.instance_variable_set(:@client, client)
    @sync.define_singleton_method(:sleep) { |_| }
    assert_raises(RawWb::WbClient::RetryableError) { @sync.send(:download_and_store_paid_storage, "task") }
  end
end
