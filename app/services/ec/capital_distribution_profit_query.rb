module Ec
  class CapitalDistributionProfitQuery
    def initialize(sku_codes:, from_date:, to_date:, as_of_date:, weekly_summary_query: Ec::WeeklySummaryDeepQuery, week_starts: nil)
      @sku_codes = Array(sku_codes).filter_map { |code| code.to_s.strip.upcase.presence }.uniq
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @from_date, @to_date = @to_date, @from_date if @from_date > @to_date
      @as_of_date = as_of_date.to_date
      @weekly_summary_query = weekly_summary_query
      @week_starts = week_starts
    end

    def call
      rows_by_sku = sku_codes.index_with { zero_metrics }
      processed_week_starts = []
      missing_week_starts = []
      unallocated_total_cny = BigDecimal("0")

      source_week_starts.each do |week_start|
        rate = Ec::WeeklyRate.find_by(week_start: week_start)
        unless rate
          missing_week_starts << week_start
          next
        end

        report = weekly_summary_query.new(
          from_date: week_start,
          to_date: week_start.end_of_week(:monday),
          rate: rate,
          sku_codes: sku_codes,
          include_comparison: false
        ).run
        merge_report_rows!(rows_by_sku, report.fetch(:rows), week_start)
        unallocated_total_cny += report.dig(:summary, :unallocated_total).to_d
        processed_week_starts << week_start
      end

      {
        rows_by_sku: rows_by_sku.transform_values { |row| rounded_metrics(row) },
        period_from: processed_week_starts.min,
        period_to: processed_week_starts.max&.end_of_week(:monday),
        cutoff_date: financial_cutoff_date,
        unallocated_total_cny: unallocated_total_cny.round(2),
        missing_week_starts: missing_week_starts
      }
    end

    private

    attr_reader :sku_codes, :from_date, :to_date, :as_of_date, :weekly_summary_query

    def source_week_starts
      @source_week_starts ||= Array(@week_starts || discovered_source_dates)
        .map { |date| date.to_date.beginning_of_week(:monday) }
        .select { |week_start| week_start >= from_date && week_start.end_of_week(:monday) <= financial_cutoff_date }
        .uniq
        .sort
    end

    def discovered_source_dates
      return [] if financial_cutoff_date < from_date

      wb_source_dates + ozon_source_dates
    end

    def wb_source_dates
      products_by_account("wb", :wb_raw_account_id, :product_id).flat_map do |account_id, product_ids|
        report_ids = RawWb::FinanceDetail
          .where(account_id: account_id, nm_id: product_ids)
          .where.not(wb_report_id: nil)
          .distinct
          .pluck(:wb_report_id)
        report_dates = RawWb::SalesReport
          .where(account_id: account_id, wb_report_id: report_ids)
          .where(date_to: from_date..financial_cutoff_date)
          .distinct
          .pluck(:date_to)
        ad_dates = RawWb::AdSkuSpend
          .where(nm_id: product_ids, stat_date: from_date..financial_cutoff_date)
          .distinct
          .pluck(:stat_date)

        report_dates + ad_dates
      end
    end

    def ozon_source_dates
      products_by_account("ozon", :ozon_raw_account_id, :platform_sku_id).flat_map do |account_id, platform_sku_ids|
        accrual_dates = RawOzon::AccrualByDay
          .where(account_id: account_id, ozon_sku_id: platform_sku_ids)
          .where(accrual_date: from_date..financial_cutoff_date)
          .distinct
          .pluck(:accrual_date)
        ad_dates = RawOzon::PerformanceSkuSpend
          .where(account_id: account_id, ozon_sku_id: platform_sku_ids)
          .where(period_from: from_date..financial_cutoff_date)
          .distinct
          .pluck(:period_from)

        accrual_dates + ad_dates
      end
    end

    def products_by_account(platform, account_key, product_key)
      Ec::SkuProduct
        .where(sku_code: sku_codes, platform: platform)
        .includes(:store)
        .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |product, grouped|
          account_id = product.store&.public_send(account_key)
          product_id = product.public_send(product_key)
          next if account_id.blank? || product_id.blank?

          grouped[account_id] << product_id
        end
        .transform_values(&:uniq)
    end

    def merge_report_rows!(rows_by_sku, rows, week_start)
      costs_by_sku = Ec::SkuCost.latest_by_sku_as_of(sku_codes, week_start).index_by(&:sku_code)

      Array(rows).each do |row|
        sku_code = row[:sku].to_s.upcase
        next unless rows_by_sku.key?(sku_code)

        totals = rows_by_sku.fetch(sku_code)
        weekly_goods_cost = row[:goods_cost].to_d
        weekly_sold_goods_cost = sold_goods_component(weekly_goods_cost, costs_by_sku[sku_code])
        totals[:net_sales_quantity] += row[:net_sales].to_i
        totals[:sales_revenue_cny] += row[:revenue].to_d
        totals[:sold_goods_cost_cny] += weekly_sold_goods_cost
        totals[:sold_customs_tax_cost_cny] += weekly_goods_cost - weekly_sold_goods_cost
        totals[:goods_cost_cny] += weekly_goods_cost
        totals[:net_profit_cny] += row[:after_tax].to_d
      end
    end

    def sold_goods_component(weekly_goods_cost, cost)
      return weekly_goods_cost unless cost

      total_unit_cost = cost.goods_cost_cny
      return weekly_goods_cost if total_unit_cost.zero?

      weekly_goods_cost * cost.goods_and_freight_cost_cny / total_unit_cost
    end

    def zero_metrics
      {
        net_sales_quantity: 0,
        sales_revenue_cny: BigDecimal("0"),
        sold_goods_cost_cny: BigDecimal("0"),
        sold_customs_tax_cost_cny: BigDecimal("0"),
        goods_cost_cny: BigDecimal("0"),
        net_profit_cny: BigDecimal("0")
      }
    end

    def rounded_metrics(row)
      goods_cost_cny = row[:goods_cost_cny].round(2)
      sold_goods_cost_cny = row[:sold_goods_cost_cny].round(2)
      row.merge(
        sales_revenue_cny: row[:sales_revenue_cny].round(2),
        sold_goods_cost_cny: sold_goods_cost_cny,
        sold_customs_tax_cost_cny: goods_cost_cny - sold_goods_cost_cny,
        goods_cost_cny: goods_cost_cny,
        net_profit_cny: row[:net_profit_cny].round(2)
      )
    end

    def latest_completed_sunday
      @latest_completed_sunday ||= as_of_date.beginning_of_week(:monday) - 1.day
    end

    def financial_cutoff_date
      @financial_cutoff_date ||= [ to_date, latest_completed_sunday ].min
    end
  end
end
