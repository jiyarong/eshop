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

  private

  def with_stubbed_records(fetcher, records)
    original_method = fetcher.method(:fetch_currency_records)
    fetcher.define_singleton_method(:fetch_currency_records) { records }
    yield
  ensure
    fetcher.define_singleton_method(:fetch_currency_records, original_method)
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
end
