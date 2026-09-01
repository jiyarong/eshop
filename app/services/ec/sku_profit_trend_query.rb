module Ec
  class SkuProfitTrendQuery
    WEEKS = 8

    def self.run(sku:, anchor_to:, store_ref: nil)
      new(sku:, anchor_to:, store_ref:).call
    end

    def initialize(sku:, anchor_to:, store_ref: nil)
      @sku = sku
      @anchor_to = anchor_to.to_date
      @store_ref = store_ref.presence
    end

    def call
      last_week_start = @anchor_to.beginning_of_week(:monday)
      periods = WEEKS.times.map do |index|
        from_date = last_week_start - (WEEKS - index - 1).weeks
        { key: from_date.iso8601, from_date:, to_date: from_date.end_of_week(:monday) }
      end
      series = Ec::SkuProfitPeriodSeriesQuery.run(sku: @sku, periods:)

      {
        weeks: series,
        store_ref: @store_ref,
        store_groups: build_store_groups(series),
        store_rows: series.map do |period|
          period.fetch(:store_rows).find { |row| row[:store_ref] == @store_ref } || {}
        end
      }
    end

    def build_store_groups(series)
      refs = series.flat_map { |period| period[:store_rows].map { |row| row[:store_ref] } }.compact.uniq
      refs.map do |store_ref|
        rows = series.map { |period| period[:store_rows].find { |row| row[:store_ref] == store_ref } || {} }
        representative = rows.reverse.find(&:present?) || {}
        { store_ref:, platform: representative[:platform], shop: representative[:store_name].presence || representative[:shop], rows: }
      end
    end
  end
end
