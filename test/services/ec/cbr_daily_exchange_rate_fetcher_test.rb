require "test_helper"

class Ec::CbrDailyExchangeRateFetcherTest < ActiveSupport::TestCase
  setup do
    @from_date = Date.new(2026, 6, 1)
    @to_date = Date.new(2026, 6, 3)
    Ec::DailyExchangeRate.where(rate_date: @from_date..@to_date).delete_all
  end

  teardown do
    Ec::DailyExchangeRate.where(rate_date: @from_date..@to_date).delete_all
  end

  test "stores CNY anchored daily rates and carries forward missing official days" do
    fetcher = Ec::CbrDailyExchangeRateFetcher.new(from_date: @from_date, to_date: @to_date)

    with_stubbed_records(fetcher, stubbed_records) do
      summary = fetcher.fetch_and_store

      assert_equal @from_date, summary[:from_date]
      assert_equal @to_date, summary[:to_date]
      assert_equal ["USD", "RUB", "BYN"], summary[:currencies]
      assert_equal 9, summary[:rows_upserted]
    end

    june_1_usd = Ec::DailyExchangeRate.find_by!(rate_date: @from_date, currency_code: "USD")
    june_1_rub = Ec::DailyExchangeRate.find_by!(rate_date: @from_date, currency_code: "RUB")
    june_1_byn = Ec::DailyExchangeRate.find_by!(rate_date: @from_date, currency_code: "BYN")
    june_2_usd = Ec::DailyExchangeRate.find_by!(rate_date: Date.new(2026, 6, 2), currency_code: "USD")
    june_3_usd = Ec::DailyExchangeRate.find_by!(rate_date: @to_date, currency_code: "USD")

    assert_equal BigDecimal("7.00000000"), june_1_usd.rate_to_base
    assert_equal BigDecimal("0.10000000"), june_1_rub.rate_to_base
    assert_equal BigDecimal("2.50000000"), june_1_byn.rate_to_base
    assert_equal Date.new(2026, 6, 1), june_2_usd.source_date
    assert_equal BigDecimal("8.00000000"), june_3_usd.rate_to_base
    assert_equal Date.new(2026, 6, 3), june_3_usd.source_date
  end

  test "upserts existing daily rates" do
    Ec::DailyExchangeRate.create!(
      rate_date: @from_date,
      base_currency: "CNY",
      currency_code: "USD",
      rate_to_base: 1,
      source: "manual",
      source_date: @from_date
    )

    fetcher = Ec::CbrDailyExchangeRateFetcher.new(from_date: @from_date, to_date: @from_date)

    with_stubbed_records(fetcher, stubbed_records.slice("USD", "CNY", "BYN")) do
      fetcher.fetch_and_store
    end

    updated = Ec::DailyExchangeRate.find_by!(rate_date: @from_date, currency_code: "USD")

    assert_equal BigDecimal("7.00000000"), updated.rate_to_base
    assert_equal "cbr", updated.source
  end

  test "carries forward earlier official rates when requested range starts on a non official day" do
    fetcher = Ec::CbrDailyExchangeRateFetcher.new(from_date: @from_date, to_date: @from_date)

    with_stubbed_records(fetcher, lookback_records) do
      summary = fetcher.fetch_and_store

      assert_equal @from_date, summary[:from_date]
      assert_equal @from_date, summary[:to_date]
      assert_equal 3, summary[:rows_upserted]
    end

    usd = Ec::DailyExchangeRate.find_by!(rate_date: @from_date, currency_code: "USD")
    rub = Ec::DailyExchangeRate.find_by!(rate_date: @from_date, currency_code: "RUB")
    byn = Ec::DailyExchangeRate.find_by!(rate_date: @from_date, currency_code: "BYN")

    assert_equal BigDecimal("7.00000000"), usd.rate_to_base
    assert_equal BigDecimal("0.10000000"), rub.rate_to_base
    assert_equal BigDecimal("2.50000000"), byn.rate_to_base
    assert_equal Date.new(2026, 5, 30), usd.source_date
    assert_equal Date.new(2026, 5, 30), rub.source_date
    assert_equal Date.new(2026, 5, 30), byn.source_date
  end

  test "requests lookback window and retries three times after the initial attempt" do
    fetcher = Ec::CbrDailyExchangeRateFetcher.new(from_date: @from_date, to_date: @to_date)
    attempts = 0
    request_paths = []
    test_case = self
    xml = cbr_xml

    with_no_sleep(fetcher) do
      with_stubbed_http_start(lambda do |_host, _port, _options, block|
        attempts += 1
        raise "temporary CBR failure" if attempts < 4

        block.call(test_case.send(:fake_http, request_paths, xml))
      end) do
        fetcher.send(:request_xml, "R01235")
      end
    end

    query = Rack::Utils.parse_query(request_paths.last.split("?", 2).last)

    assert_equal 4, attempts
    assert_equal "18/05/2026", query.fetch("date_req1")
    assert_equal "03/06/2026", query.fetch("date_req2")
    assert_equal "R01235", query.fetch("VAL_NM_RQ")
  end

  private

  def with_no_sleep(fetcher)
    fetcher.define_singleton_method(:sleep) { |_seconds| }
    yield
  ensure
    fetcher.singleton_class.remove_method(:sleep)
  end

  def with_stubbed_http_start(handler)
    original_method = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) do |host, port, **options, &block|
      handler.call(host, port, options, block)
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:start, original_method)
  end

  def with_stubbed_records(fetcher, records)
    original_method = fetcher.method(:fetch_currency_records)
    fetcher.define_singleton_method(:fetch_currency_records) { records }
    yield
  ensure
    fetcher.define_singleton_method(:fetch_currency_records, original_method)
  end

  def fake_http(request_paths, xml)
    http = Object.new
    response = fake_http_response(xml)
    http.define_singleton_method(:get) do |request_path|
      request_paths << request_path
      response
    end
    http
  end

  def fake_http_response(xml)
    response = Object.new
    response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess || super(klass) }
    response.define_singleton_method(:body) { xml.encode("Windows-1251") }
    response.define_singleton_method(:code) { "200" }
    response
  end

  def cbr_xml
    <<~XML
      <?xml version="1.0" encoding="windows-1251"?>
      <ValCurs>
        <Record Date="30.05.2026" Id="R01235">
          <Nominal>1</Nominal>
          <Value>70,0000</Value>
          <VunitRate>70,0000</VunitRate>
        </Record>
      </ValCurs>
    XML
  end

  def stubbed_records
    {
      "USD" => {
        Date.new(2026, 6, 1) => BigDecimal("70"),
        Date.new(2026, 6, 3) => BigDecimal("80")
      },
      "CNY" => {
        Date.new(2026, 6, 1) => BigDecimal("10"),
        Date.new(2026, 6, 3) => BigDecimal("10")
      },
      "BYN" => {
        Date.new(2026, 6, 1) => BigDecimal("25"),
        Date.new(2026, 6, 3) => BigDecimal("30")
      }
    }
  end

  def lookback_records
    {
      "USD" => {
        Date.new(2026, 5, 30) => BigDecimal("70")
      },
      "CNY" => {
        Date.new(2026, 5, 30) => BigDecimal("10")
      },
      "BYN" => {
        Date.new(2026, 5, 30) => BigDecimal("25")
      }
    }
  end
end
