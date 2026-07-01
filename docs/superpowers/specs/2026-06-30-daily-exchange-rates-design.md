# Daily Exchange Rates Design

## Goal

Add a daily exchange-rate store anchored to CNY. The first supported quote currencies are USD, RUB, and BYN. Each natural calendar day should have one row per quote currency so business code can query a date directly without handling weekends or CBR holidays.

## Assumptions

- The base currency is CNY.
- Stored direction is `1 quote currency = rate_to_base CNY`.
- Natural days are filled. When CBR has no official rate for a day, the system uses the most recent earlier official CBR rate and records that official date in `source_date`.
- Initial source is the Central Bank of Russia XML API because the project already uses CBR for weekly RUB-based rates.

## Data Model

Create `ec_daily_exchange_rates`.

```ruby
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
```

Model validations:

- `rate_date`, `base_currency`, `currency_code`, `rate_to_base`, and `source` are required.
- `rate_to_base` must be greater than zero.
- `base_currency`, `currency_code`, and `source` should be normalized to uppercase/lowercase consistently before validation.
- Uniqueness is enforced on `rate_date + base_currency + currency_code`.

## CBR Fetching

Use CBR dynamic XML endpoints for historical ranges:

- USD: `VAL_NM_RQ=R01235`
- CNY: `VAL_NM_RQ=R01375`
- BYN: `VAL_NM_RQ=R01090B`

For each requested range:

1. Fetch USD/RUB, CNY/RUB, and BYN/RUB records from `XML_dynamic.asp`.
2. Parse each official record date and `VunitRate` or `Value / Nominal`.
3. Walk every natural day in the requested range.
4. For each day, use that day's official CBR record when present; otherwise carry forward the latest earlier official record.
5. Upsert three rows for the natural day:
   - `USD`: `usd_rub / cny_rub`
   - `RUB`: `1 / cny_rub`
   - `BYN`: `byn_rub / cny_rub`

The service should fail if it cannot find a CNY/RUB official rate to anchor a day. It should also fail if USD or BYN is missing after carry-forward, because partial daily rows would make later reporting ambiguous.

## API Shape

Add an `Ec::DailyExchangeRate` model.

Add an `Ec::CbrDailyExchangeRateFetcher` service with:

```ruby
Ec::CbrDailyExchangeRateFetcher.fetch_and_store(
  from_date: 1.year.ago.to_date,
  to_date: Date.current
)
```

The service should return a small summary hash, such as:

```ruby
{
  from_date:,
  to_date:,
  currencies: ["USD", "RUB", "BYN"],
  rows_upserted:
}
```

## Compatibility

Keep `ec_weekly_rates` and `Ec::CbrRateFetcher` unchanged for the first implementation. Weekly profit report pages already depend on the weekly table and should not change as part of this feature unless a later task explicitly migrates them to daily rates.

## Verification

Add focused tests for:

- Model validations and uniqueness.
- Correct conversion from CBR RUB-based rates into CNY-based rates.
- Natural-day carry-forward over a missing CBR day.
- Upsert behavior when a day is fetched again.

Use unique dates in tests and clean up created rows because transactional tests are disabled in this project.
