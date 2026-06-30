require "test_helper"

class Ec::DailyExchangeRateTest < ActiveSupport::TestCase
  setup do
    @date = Date.new(2026, 6, 30)
    Ec::DailyExchangeRate.where(rate_date: @date).delete_all if defined?(Ec::DailyExchangeRate)
  end

  teardown do
    Ec::DailyExchangeRate.where(rate_date: @date).delete_all if defined?(Ec::DailyExchangeRate)
  end

  test "normalizes currencies and source before validation" do
    rate = Ec::DailyExchangeRate.create!(
      rate_date: @date,
      base_currency: "cny",
      currency_code: "usd",
      rate_to_base: 7.12345678,
      source: "CBR",
      source_date: @date
    )

    assert_equal "CNY", rate.base_currency
    assert_equal "USD", rate.currency_code
    assert_equal "cbr", rate.source
  end

  test "requires positive rate_to_base" do
    rate = Ec::DailyExchangeRate.new(
      rate_date: @date,
      base_currency: "CNY",
      currency_code: "USD",
      rate_to_base: 0,
      source: "cbr"
    )

    assert_not rate.valid?
    assert_includes rate.errors[:rate_to_base], "must be greater than 0"
  end

  test "enforces one rate per date base and currency" do
    Ec::DailyExchangeRate.create!(
      rate_date: @date,
      base_currency: "CNY",
      currency_code: "USD",
      rate_to_base: 7.1,
      source: "cbr",
      source_date: @date
    )

    duplicate = Ec::DailyExchangeRate.new(
      rate_date: @date,
      base_currency: "CNY",
      currency_code: "USD",
      rate_to_base: 7.2,
      source: "cbr",
      source_date: @date
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:currency_code], "has already been taken"
  end
end
