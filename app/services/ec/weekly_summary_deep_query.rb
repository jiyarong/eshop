module Ec
  class WeeklySummaryDeepQuery
    include WeeklySummarySupport

    def self.run(from_date:, to_date:)
      new(from_date:, to_date:).run
    end

    def initialize(from_date:, to_date:, rate: nil)
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @rate = rate || Ec::WeeklyRate.resolve(@from_date)
      raise "找不到 #{@from_date} 的汇率，请先录入 ec_weekly_rates" unless @rate
    end

    def run
      rows, unalloc_cny = collect_rows(@from_date, @to_date, @rate)
      prev_rows, = previous_rows_data
      aggregated_rows = aggregate_rows_by_sku(rows)
      prev_map = aggregate_rows_by_sku(prev_rows).index_by { |row| row[:sku] }

      {
        report_type: "wsu_deep",
        period: {
          from_date: @from_date.to_s,
          to_date: @to_date.to_s
        },
        meta: {
          rates: {
            rate_cny_rub: @rate.rate_cny_rub,
            rate_byn_rub: @rate.rate_byn_rub
          }
        },
        summary: build_wsu_deep_summary_hash(aggregated_rows, unalloc_cny, rate: @rate, from_date: @from_date, to_date: @to_date),
        rows: build_wsu_deep_row_hashes(aggregated_rows, prev_map, from_date: @from_date, to_date: @to_date),
        extras: {}
      }
    end

    private

    def previous_rows_data
      prev_from = @from_date - 7
      prev_to = @to_date - 7
      prev_rate = Ec::WeeklyRate.resolve(prev_from)
      return [[], nil] unless prev_rate

      collect_rows(prev_from, prev_to, prev_rate)
    end
  end
end
