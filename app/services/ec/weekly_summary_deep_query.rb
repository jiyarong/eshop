module Ec
  class WeeklySummaryDeepQuery
    include WeeklySummarySupport

    COMPARISON_SUMMARY_KEYS = %i[
      total_sku_count total_net_sales total_sales_revenue total_ads total_goods_cost
      total_pre_tax total_after_tax total_margin_pct unallocated_total after_tax_with_unallocated
    ].freeze
    COMPARISON_ROW_KEYS = %i[
      net_sales revenue ads goods_cost pre_tax tax after_tax margin_pct average_profit_per_order
      ad_ratio_pct cost_return_pct projected_roi_pct annualized_return_pct annualized_net_profit_cny
    ].freeze

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
      aggregated_rows = aggregate_rows_by_sku(rows)
      current_rows = build_wsu_deep_row_hashes(aggregated_rows, from_date: @from_date, to_date: @to_date)
      current_summary = build_wsu_deep_summary_hash(aggregated_rows, unalloc_cny, rate: @rate, from_date: @from_date, to_date: @to_date)
      prev_from, prev_to = previous_period_range(@from_date, @to_date)
      prev_rows, prev_unalloc, prev_rate = previous_rows_data
      previous_aggregated_rows = aggregate_rows_by_sku(prev_rows)
      previous_rows = build_wsu_deep_row_hashes(previous_aggregated_rows, from_date: prev_from, to_date: prev_to)
      previous_summary = prev_rate ? build_wsu_deep_summary_hash(previous_aggregated_rows, prev_unalloc, rate: prev_rate, from_date: prev_from, to_date: prev_to) : nil

      {
        report_type: "wsu_deep",
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
            key_builder: ->(row) { row[:sku].to_s },
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
