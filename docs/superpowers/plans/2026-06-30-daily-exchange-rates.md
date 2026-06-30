# Daily Exchange Rates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a CNY-anchored daily exchange-rate table and a CBR backfill service for USD, RUB, and BYN, with natural-day carry-forward.

**Architecture:** Keep the existing weekly-rate code unchanged. Add a focused `Ec::DailyExchangeRate` model backed by `ec_daily_exchange_rates`, and a separate `Ec::CbrDailyExchangeRateFetcher` service that fetches CBR RUB-based historical rates, converts them to CNY-based rates, fills natural days, and upserts rows.

**Tech Stack:** Rails 8, ActiveRecord, Minitest, Net::HTTP, CBR XML endpoints.

---

## File Structure

- Create `db/migrate/20260630000001_create_ec_daily_exchange_rates.rb`: table and unique index.
- Create `app/models/ec/daily_exchange_rate.rb`: validations and normalization.
- Create `test/models/ec/daily_exchange_rate_test.rb`: model validation, normalization, and uniqueness tests.
- Create `app/services/ec/cbr_daily_exchange_rate_fetcher.rb`: CBR range fetcher and conversion service.
- Create `test/services/ec/cbr_daily_exchange_rate_fetcher_test.rb`: conversion, natural-day carry-forward, and upsert tests.

## Task 1: Daily Exchange Rate Model

**Files:**
- Create: `db/migrate/20260630000001_create_ec_daily_exchange_rates.rb`
- Create: `app/models/ec/daily_exchange_rate.rb`
- Test: `test/models/ec/daily_exchange_rate_test.rb`

- [ ] **Step 1: Write the failing model test**

Create `test/models/ec/daily_exchange_rate_test.rb`:

```ruby
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
```

- [ ] **Step 2: Run the model test to verify it fails**

Run:

```bash
rbenv exec ruby bin/rails test test/models/ec/daily_exchange_rate_test.rb
```

Expected: FAIL because `Ec::DailyExchangeRate` or `ec_daily_exchange_rates` does not exist.

- [ ] **Step 3: Add the migration**

Create `db/migrate/20260630000001_create_ec_daily_exchange_rates.rb`:

```ruby
class CreateEcDailyExchangeRates < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_daily_exchange_rates do |t|
      t.date :rate_date, null: false
      t.string :base_currency, null: false, default: "CNY"
      t.string :currency_code, null: false
      t.decimal :rate_to_base, precision: 18, scale: 8, null: false
      t.string :source, null: false, default: "cbr"
      t.date :source_date
      t.timestamps
    end

    add_index :ec_daily_exchange_rates,
      [:rate_date, :base_currency, :currency_code],
      unique: true,
      name: "index_ec_daily_exchange_rates_unique_daily_currency"
  end
end
```

- [ ] **Step 4: Add the model**

Create `app/models/ec/daily_exchange_rate.rb`:

```ruby
module Ec
  class DailyExchangeRate < ApplicationRecord
    self.table_name = "ec_daily_exchange_rates"

    before_validation :normalize_codes

    validates :rate_date, :base_currency, :currency_code, :rate_to_base, :source, presence: true
    validates :rate_to_base, numericality: { greater_than: 0 }
    validates :currency_code, uniqueness: { scope: [:rate_date, :base_currency] }

    private

    def normalize_codes
      self.base_currency = base_currency.to_s.upcase if base_currency.present?
      self.currency_code = currency_code.to_s.upcase if currency_code.present?
      self.source = source.to_s.downcase if source.present?
    end
  end
end
```

- [ ] **Step 5: Prepare the test database and verify the model test passes**

Run:

```bash
rbenv exec ruby bin/rails db:migrate
rbenv exec ruby bin/rails test test/models/ec/daily_exchange_rate_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit the model task**

Run:

```bash
git add db/migrate/20260630000001_create_ec_daily_exchange_rates.rb db/schema.rb app/models/ec/daily_exchange_rate.rb test/models/ec/daily_exchange_rate_test.rb
git commit -m "Add daily exchange rate model"
```

## Task 2: CBR Daily Fetcher Service

**Files:**
- Create: `app/services/ec/cbr_daily_exchange_rate_fetcher.rb`
- Test: `test/services/ec/cbr_daily_exchange_rate_fetcher_test.rb`

- [ ] **Step 1: Write the failing service test**

Create `test/services/ec/cbr_daily_exchange_rate_fetcher_test.rb`:

```ruby
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

    fetcher.stub(:fetch_currency_records, stubbed_records) do
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

    fetcher.stub(:fetch_currency_records, stubbed_records.slice("USD", "CNY", "BYN")) do
      fetcher.fetch_and_store
    end

    updated = Ec::DailyExchangeRate.find_by!(rate_date: @from_date, currency_code: "USD")

    assert_equal BigDecimal("7.00000000"), updated.rate_to_base
    assert_equal "cbr", updated.source
  end

  private

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
```

- [ ] **Step 2: Run the service test to verify it fails**

Run:

```bash
rbenv exec ruby bin/rails test test/services/ec/cbr_daily_exchange_rate_fetcher_test.rb
```

Expected: FAIL because `Ec::CbrDailyExchangeRateFetcher` does not exist.

- [ ] **Step 3: Add the service**

Create `app/services/ec/cbr_daily_exchange_rate_fetcher.rb`:

```ruby
module Ec
  class CbrDailyExchangeRateFetcher
    CBR_DYNAMIC_URL = "https://www.cbr.ru/scripts/XML_dynamic.asp".freeze
    BASE_CURRENCY = "CNY".freeze
    SOURCE = "cbr".freeze
    CURRENCIES = {
      "USD" => "R01235",
      "CNY" => "R01375",
      "BYN" => "R01090B"
    }.freeze
    STORED_CURRENCIES = ["USD", "RUB", "BYN"].freeze

    def self.fetch_and_store(from_date: 1.year.ago.to_date, to_date: Date.current)
      new(from_date:, to_date:).fetch_and_store
    end

    def initialize(from_date:, to_date:)
      @from_date = from_date.to_date
      @to_date = to_date.to_date
    end

    def fetch_and_store
      raise ArgumentError, "from_date must be before or equal to to_date" if @from_date > @to_date

      records = fetch_currency_records
      rows = build_rows(records)

      Ec::DailyExchangeRate.upsert_all(
        rows,
        unique_by: :index_ec_daily_exchange_rates_unique_daily_currency
      )

      {
        from_date: @from_date,
        to_date: @to_date,
        currencies: STORED_CURRENCIES,
        rows_upserted: rows.size
      }
    end

    private

    def fetch_currency_records
      CURRENCIES.to_h do |currency, cbr_id|
        [currency, parse_records(request_xml(cbr_id))]
      end
    end

    def build_rows(records)
      latest = {}

      (@from_date..@to_date).flat_map do |date|
        CURRENCIES.each_key do |currency|
          latest[currency] = { date:, value: records.fetch(currency)[date] } if records.fetch(currency).key?(date)
        end

        build_daily_rows(date, latest)
      end
    end

    def build_daily_rows(date, latest)
      usd = latest["USD"]
      cny = latest["CNY"]
      byn = latest["BYN"]

      raise "CBR response has no CNY rate for #{date}" unless cny
      raise "CBR response has no USD rate for #{date}" unless usd
      raise "CBR response has no BYN rate for #{date}" unless byn

      now = Time.current
      cny_rub = cny.fetch(:value)

      [
        daily_row(date, "USD", usd.fetch(:value) / cny_rub, usd.fetch(:date), now),
        daily_row(date, "RUB", BigDecimal("1") / cny_rub, cny.fetch(:date), now),
        daily_row(date, "BYN", byn.fetch(:value) / cny_rub, byn.fetch(:date), now)
      ]
    end

    def daily_row(date, currency, rate, source_date, timestamp)
      {
        rate_date: date,
        base_currency: BASE_CURRENCY,
        currency_code: currency,
        rate_to_base: rate.round(8),
        source: SOURCE,
        source_date: source_date,
        created_at: timestamp,
        updated_at: timestamp
      }
    end

    def request_xml(cbr_id)
      uri = URI(CBR_DYNAMIC_URL)
      uri.query = URI.encode_www_form(
        date_req1: @from_date.strftime("%d/%m/%Y"),
        date_req2: @to_date.strftime("%d/%m/%Y"),
        VAL_NM_RQ: cbr_id
      )

      retries = 0
      begin
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
          response = http.get("#{uri.path}?#{uri.query}")
          raise "CBR HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          response.body.force_encoding("Windows-1251").encode("UTF-8")
        end
      rescue => e
        retries += 1
        raise if retries >= 3

        sleep retries * 5
        retry
      end
    end

    def parse_records(xml)
      xml.scan(/<Record\b[^>]*Date="([^"]+)"[^>]*>(.*?)<\/Record>/m).each_with_object({}) do |(date_text, content), parsed|
        date = Date.strptime(date_text, "%d.%m.%Y")
        nominal = content[/<Nominal>(.*?)<\/Nominal>/, 1].to_i
        value_text = content[/<VunitRate>(.*?)<\/VunitRate>/, 1] || content[/<Value>(.*?)<\/Value>/, 1]
        value = BigDecimal(value_text.to_s.tr(",", "."))
        parsed[date] = nominal.positive? && content.exclude?("<VunitRate>") ? value / nominal : value
      end
    end
  end
end
```

- [ ] **Step 4: Run service tests and fix only implementation mistakes**

Run:

```bash
rbenv exec ruby bin/rails test test/services/ec/cbr_daily_exchange_rate_fetcher_test.rb
```

Expected: PASS.

- [ ] **Step 5: Commit the service task**

Run:

```bash
git add app/services/ec/cbr_daily_exchange_rate_fetcher.rb test/services/ec/cbr_daily_exchange_rate_fetcher_test.rb
git commit -m "Add CBR daily exchange rate fetcher"
```

## Task 3: Final Verification

**Files:**
- Verify: `app/models/ec/daily_exchange_rate.rb`
- Verify: `app/services/ec/cbr_daily_exchange_rate_fetcher.rb`
- Verify: `test/models/ec/daily_exchange_rate_test.rb`
- Verify: `test/services/ec/cbr_daily_exchange_rate_fetcher_test.rb`

- [ ] **Step 1: Run focused tests**

Run:

```bash
rbenv exec ruby bin/rails test test/models/ec/daily_exchange_rate_test.rb test/services/ec/cbr_daily_exchange_rate_fetcher_test.rb
```

Expected: PASS.

- [ ] **Step 2: Run existing report tests to ensure weekly behavior is unchanged**

Run:

```bash
rbenv exec ruby bin/rails test test/controllers/reports_controller_test.rb test/controllers/weekly_profit_reports_controller_test.rb
```

Expected: PASS.

- [ ] **Step 3: Inspect git status**

Run:

```bash
git status --short
```

Expected: only unrelated pre-existing dirty paths remain, or a clean tree after commits.

## Self-Review

- Spec coverage: The plan covers the daily table, CNY-anchored direction, USD/RUB/BYN rows, CBR range fetching, natural-day carry-forward, source dates, compatibility with weekly rates, and focused tests.
- Placeholder scan: No placeholder task remains.
- Type consistency: The model uses `rate_to_base`, and the service writes the same column. The service API is `Ec::CbrDailyExchangeRateFetcher.fetch_and_store(from_date:, to_date:)`, matching the design.
