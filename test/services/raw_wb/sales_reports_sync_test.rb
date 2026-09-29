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

  test "requests finance details one day at a time with small pages" do
    bodies = []
    item = method(:finance_item)
    client = Object.new
    client.define_singleton_method(:post) do |_service, _path, body|
      bodies << body
      [item.call(900_000 + bodies.size)]
    end
    stub_finance_client(client, from: Date.current - 2)

    assert_equal 3, @sync.send(:sync_finance_details)
    assert_equal 3, bodies.size
    bodies.each do |body|
      assert_equal body[:dateFrom], body[:dateTo]
      assert_equal RawWb::Syncs::FinanceDetails::FINANCE_PAGE_SIZE, body[:limit]
    end
    assert_equal [Date.current, Date.current - 1, Date.current - 2].map(&:iso8601), bodies.map { |b| b[:dateFrom] }
  end

  test "pages within a day by rrdid until a short page" do
    page_size = RawWb::Syncs::FinanceDetails::FINANCE_PAGE_SIZE
    full_page = (1..page_size).map { |i| finance_item(100_000 + i) }
    bodies = []
    last_page = [finance_item(200_000)]
    client = Object.new
    client.define_singleton_method(:post) do |_service, _path, body|
      bodies << body
      bodies.size == 1 ? full_page : last_page
    end
    stub_finance_client(client, from: Date.current)

    assert_equal page_size + 1, @sync.send(:sync_finance_details)
    assert_equal [0, 100_000 + page_size], bodies.map { |b| b[:rrdid] }
  end

  test "retries only the current page after a network error" do
    page_size = RawWb::Syncs::FinanceDetails::FINANCE_PAGE_SIZE
    full_page = (1..page_size).map { |i| finance_item(300_000 + i) }
    bodies = []
    last_page = [finance_item(400_000)]
    client = Object.new
    client.define_singleton_method(:post) do |_service, _path, body|
      bodies << body
      case bodies.size
      when 1 then full_page
      when 2 then raise Net::OpenTimeout
      when 3 then raise OpenSSL::SSL::SSLError, "SSL_read: unexpected eof while reading"
      else last_page
      end
    end
    stub_finance_client(client, from: Date.current)

    assert_equal page_size + 1, @sync.send(:sync_finance_details)
    assert_equal [0, 300_000 + page_size, 300_000 + page_size, 300_000 + page_size], bodies.map { |b| b[:rrdid] }
  end

  test "raises after exhausting network retries so the step is marked failed" do
    calls = 0
    client = Object.new
    client.define_singleton_method(:post) do |*_args|
      calls += 1
      raise Errno::ECONNRESET
    end
    stub_finance_client(client, from: Date.current)

    assert_raises(Errno::ECONNRESET) { @sync.send(:sync_finance_details) }
    assert_equal RawWb::Syncs::FinanceDetails::NETWORK_RETRY_LIMIT + 1, calls
  end

  private

  def stub_finance_client(client, from:)
    @sync.instance_variable_set(:@client, client)
    @sync.instance_variable_set(:@from, from)
    @sync.define_singleton_method(:sleep) { |_seconds| }
  end

  def finance_item(rrdid)
    {
      "rrdId" => rrdid,
      "reportId" => 835_651_868,
      "nmId" => 123_456,
      "sellerOperName" => "Продажа",
      "forPay" => "1.00",
      "rrDate" => Date.current.iso8601
    }
  end
end
