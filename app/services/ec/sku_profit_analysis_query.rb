module Ec
  class SkuProfitAnalysisQuery
    PERIOD_COUNT = 4

    def self.run(sku:, from_date:, to_date:)
      new(sku:, from_date:, to_date:).call
    end

    def initialize(sku:, from_date:, to_date:)
      @sku = sku
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      validate_period!
    end

    def call
      periods = PERIOD_COUNT.times.map do |offset|
        {
          key: "P-#{offset}".sub("P-0", "P0"),
          from_date: @from_date - (period_days * offset).days,
          to_date: @to_date - (period_days * offset).days
        }
      end.reverse
      series = Ec::SkuProfitPeriodSeriesQuery.run(sku: @sku, periods:)

      { periods: series, store_groups: build_store_groups(series) }
    end

    private

    def period_days
      (@to_date - @from_date).to_i + 1
    end

    def validate_period!
      valid = @from_date.cwday == 1 && @to_date.cwday == 7 && period_days.positive? && (period_days % 7).zero?
      raise ArgumentError, "invalid_profit_period" unless valid
    end

    def build_store_groups(series)
      rows = series.flat_map do |period|
        period.fetch(:store_rows).map { |row| [period.fetch(:key), row] }
      end

      rows.group_by { |_key, row| row[:store_ref].presence || [row[:platform], row[:shop]].join(":") }
        .map do |store_ref, period_rows|
          representative = period_rows.reverse.find { |_key, row| row.present? }&.last || {}
          {
            store_ref:,
            platform: representative[:platform],
            shop: representative[:store_name].presence || representative[:shop],
            sku_product_id: representative[:sku_product_id],
            listing_label: representative[:listing_label],
            rows_by_period: period_rows.to_h
          }
        end
        .sort_by do |group|
          p1_net_sales = group.dig(:rows_by_period, "P-1", :net_sales).to_i
          [-p1_net_sales, group[:platform].to_s, group[:shop].to_s]
        end
    end
  end
end
