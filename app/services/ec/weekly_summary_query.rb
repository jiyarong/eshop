module Ec
  class WeeklySummaryQuery
    include WeeklySummarySupport

    COMPARISON_SUMMARY_KEYS = %i[
      total_sales_revenue total_after_tax total_margin_pct wb_sales_revenue wb_ads wb_goods_cost
      wb_pre_tax wb_after_tax ozon_sales_revenue ozon_ads ozon_goods_cost ozon_pre_tax
      ozon_after_tax wb_unallocated ozon_unallocated unallocated_total after_tax_with_unallocated
      margin_with_unallocated_pct
    ].freeze
    COMPARISON_ROW_KEYS = %i[net_sales revenue ads goods_cost pre_tax tax after_tax margin_pct].freeze

    def self.run(from_date:, to_date:, sku_codes: [])
      new(from_date:, to_date:, sku_codes:).run
    end

    def initialize(from_date:, to_date:, rate: nil, sku_codes: [])
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @rate = rate || Ec::WeeklyRate.resolve(@from_date)
      @sku_codes = sku_codes
      raise "找不到 #{@from_date} 的汇率，请先录入 ec_weekly_rates" unless @rate
    end

    def run
      rows, unalloc_cny = collect_rows(@from_date, @to_date, @rate)
      current_rows = build_wsu_row_hashes(rows)
      current_summary = build_wsu_summary_hash(rows, unalloc_cny, rate: @rate, from_date: @from_date, to_date: @to_date)
      prev_from, prev_to = previous_period_range(@from_date, @to_date)
      prev_rows, prev_unalloc, prev_rate = previous_rows_data
      previous_rows = build_wsu_row_hashes(prev_rows)
      previous_summary = prev_rate ? build_wsu_summary_hash(prev_rows, prev_unalloc, rate: prev_rate, from_date: prev_from, to_date: prev_to) : nil

      {
        report_type: "wsu",
        period: {
          from_date: @from_date.to_s,
          to_date: @to_date.to_s
        },
        comparison: {
          period: {
            from_date: prev_from.to_s,
            to_date: prev_to.to_s
          },
          summary: build_summary_comparison(current_summary, previous_summary, COMPARISON_SUMMARY_KEYS),
          rows: build_row_comparison_map(
            current_rows,
            previous_rows,
            key_builder: ->(row) { [row[:sku], row[:platform], row[:shop]].join("|") },
            metric_keys: COMPARISON_ROW_KEYS
          )
        },
        meta: {
          rates: {
            rate_cny_rub: @rate.rate_cny_rub,
            rate_byn_rub: @rate.rate_byn_rub
          }
        },
        summary: current_summary,
        rows: current_rows,
        extras: {}
      }
    end

    private

    def previous_rows_data
      prev_from, prev_to = previous_period_range(@from_date, @to_date)
      prev_rate = Ec::WeeklyRate.resolve(prev_from)
      return [[], nil, nil] unless prev_rate

      rows, unalloc = collect_rows(prev_from, prev_to, prev_rate)
      [rows, unalloc, prev_rate]
    end
  end
end
