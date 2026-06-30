require "net/http"
require "uri"

module Ec
  class CbrDailyExchangeRateFetcher
    CBR_DYNAMIC_URL = "https://www.cbr.ru/scripts/XML_dynamic.asp".freeze
    BASE_CURRENCY = "CNY".freeze
    SOURCE = "cbr".freeze
    CURRENCIES = { "USD" => "R01235", "CNY" => "R01375", "BYN" => "R01090B" }.freeze
    STORED_CURRENCIES = ["USD", "RUB", "BYN"].freeze
    LOOKBACK_DAYS = 14

    def self.fetch_and_store(from_date: 1.year.ago.to_date, to_date: Date.current)
      new(from_date: from_date, to_date: to_date).fetch_and_store
    end

    def initialize(from_date:, to_date:)
      @from_date = from_date.to_date
      @to_date = to_date.to_date
    end

    def fetch_and_store
      raise ArgumentError, "from_date must be on or before to_date" if @from_date > @to_date

      rows = build_rows(fetch_currency_records)
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

    def fetch_currency_records
      CURRENCIES.to_h do |currency_code, cbr_code|
        [currency_code, parse_currency_records(request_xml(cbr_code))]
      end
    end

    private

    def build_rows(records)
      rows = []
      latest = {}
      now = Time.current

      (@from_date..@to_date).each do |date|
        CURRENCIES.each_key do |currency_code|
          source_date = records.fetch(currency_code).keys.select { |record_date| record_date <= date }.max
          if source_date
            latest[currency_code] = {
              rate: records.fetch(currency_code).fetch(source_date),
              source_date: source_date
            }
          end
        end

        rows.concat(rows_for_date(date, latest, now))
      end

      rows
    end

    def rows_for_date(date, latest, timestamp)
      cny = latest.fetch("CNY")
      usd = latest.fetch("USD")
      byn = latest.fetch("BYN")
      cny_rub = cny.fetch(:rate)

      [
        row_for(date, "USD", usd.fetch(:rate) / cny_rub, usd.fetch(:source_date), timestamp),
        row_for(date, "RUB", BigDecimal("1") / cny_rub, cny.fetch(:source_date), timestamp),
        row_for(date, "BYN", byn.fetch(:rate) / cny_rub, byn.fetch(:source_date), timestamp)
      ]
    end

    def row_for(date, currency_code, rate_to_base, source_date, timestamp)
      {
        rate_date: date,
        base_currency: BASE_CURRENCY,
        currency_code: currency_code,
        rate_to_base: rate_to_base.round(8),
        rate_from_base: (BigDecimal("1") / rate_to_base).round(8),
        source: SOURCE,
        source_date: source_date,
        created_at: timestamp,
        updated_at: timestamp
      }
    end

    def request_xml(cbr_code)
      uri = URI(CBR_DYNAMIC_URL)
      uri.query = URI.encode_www_form(
        date_req1: (@from_date - LOOKBACK_DAYS.days).strftime("%d/%m/%Y"),
        date_req2: @to_date.strftime("%d/%m/%Y"),
        VAL_NM_RQ: cbr_code
      )

      retries = 0
      begin
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
          resp = http.get("#{uri.path}?#{uri.query}")
          raise "CBR HTTP #{resp.code}" unless resp.is_a?(Net::HTTPSuccess)

          resp.body.force_encoding("Windows-1251").encode("UTF-8")
        end
      rescue => e
        retries += 1
        raise e if retries > 3

        sleep retries * 5
        retry
      end
    end

    def parse_currency_records(xml)
      xml.scan(/<Record\b([^>]*)>(.*?)<\/Record>/m).each_with_object({}) do |(attributes, content), records|
        date = parse_record_date(attributes)
        nominal = decimal_from_xml(content, "Nominal")
        next if nominal.blank? || nominal.zero?

        value = decimal_from_xml(content, "VunitRate") || decimal_from_xml(content, "Value") / nominal
        records[date] = value
      end
    end

    def parse_record_date(attributes)
      Date.strptime(attributes[/Date="([^"]+)"/, 1], "%d.%m.%Y")
    end

    def decimal_from_xml(content, tag_name)
      raw_value = content[/<#{tag_name}>(.*?)<\/#{tag_name}>/m, 1]
      return unless raw_value

      BigDecimal(raw_value.tr(",", "."))
    end
  end
end
