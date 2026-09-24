module Ec
  class SkuActualAdvertisingQuery
    DEFAULT_WEEKS = 4
    PLATFORMS = %w[wb ozon].freeze

    def self.run(sku:, platform:, today:, weeks: DEFAULT_WEEKS)
      new(sku:, platform:, today:, weeks:).run
    end

    def initialize(sku:, platform:, today:, weeks: DEFAULT_WEEKS)
      @sku = sku
      @platform = platform.to_s.downcase
      @today = today.to_date
      @weeks = Integer(weeks)

      raise ArgumentError, "unsupported_platform" unless PLATFORMS.include?(@platform)
      raise ArgumentError, "weeks_must_be_positive" unless @weeks.positive?
    end

    def run
      period_to = today.beginning_of_week(:monday) - 1.day
      period_from = period_to - (weeks * 7 - 1).days
      result = platform == "ozon" ? ozon_result(period_from:, period_to:) : wb_result(period_from:, period_to:)
      advertising = result.fetch(:advertising_rub)
      sales = result.fetch(:sales_rub)

      {
        platform: platform,
        period: {
          from_date: period_from,
          to_date: period_to,
          data_through: result[:data_through]
        },
        store_count: result.fetch(:store_count),
        listing_count: result.fetch(:listing_count),
        advertising: { total: advertising.round(2), currency: "RUB" },
        sales: { total: sales.round(2), currency: "RUB" },
        rate: sales.positive? ? (advertising / sales).round(10) : nil,
        coverage: result.fetch(:coverage)
      }
    end

    private

    attr_reader :sku, :platform, :today, :weeks

    def week_pairs(period_from)
      weeks.times.map do |index|
        week_from = period_from + index.weeks
        [week_from, week_from + 6.days]
      end
    end

    def ozon_result(period_from:, period_to:)
      bindings = platform_bindings("ozon", :ozon_raw_account_id, :platform_sku_id)
        .filter_map do |account_id, platform_sku_id|
          ozon_sku_id = Integer(platform_sku_id, exception: false)
          [account_id, ozon_sku_id] if ozon_sku_id
        end
        .uniq
      account_bindings = bindings.group_by(&:first)
      advertising_rub = 0.to_d
      sales_rub = 0.to_d
      covered_periods = 0
      performance_total = 0.to_d
      financial_ad_total = 0.to_d
      data_through = nil

      account_bindings.each do |account_id, pairs|
        ozon_sku_ids = pairs.map(&:last).uniq
        week_pairs(period_from).each do |week_from, week_to|
          spends = RawOzon::PerformanceSkuSpend.where(
            account_id: account_id,
            period_from: week_from,
            period_to: week_to
          )
          next unless spends.exists?

          covered_periods += 1
          data_through = [data_through, week_to].compact.max
          advertising_rub += spends.where(ozon_sku_id: ozon_sku_ids).sum(:spend).to_d
          performance_total += spends.sum(:spend).to_d

          accruals = RawOzon::AccrualByDay.where(account_id: account_id, accrual_date: week_from..week_to)
          sales_rub += accruals.where(ozon_sku_id: ozon_sku_ids, type_id: 0).sum(:amount).to_d
          financial_ad_total += accruals
            .where(type_id: Ec::OzonProfitAttribution::AD_TYPE_IDS.to_a)
            .pluck(:amount)
            .sum(0.to_d) { |amount| amount.to_d.abs }
        end
      end

      attribution_rate = performance_total / financial_ad_total if financial_ad_total.positive?
      {
        advertising_rub: advertising_rub,
        sales_rub: sales_rub,
        data_through: data_through,
        store_count: account_bindings.keys.size,
        listing_count: bindings.size,
        coverage: base_coverage(account_bindings.keys.size, covered_periods).merge(
          attribution_rate: attribution_rate&.round(10),
          allocation_fallback: false,
          currency_conversion_fallback: false
        )
      }
    end

    def wb_result(period_from:, period_to:)
      bindings = platform_bindings("wb", :wb_raw_account_id, :product_id)
        .filter_map do |account_id, product_id|
          nm_id = Integer(product_id, exception: false)
          [account_id, nm_id] if nm_id
        end
        .uniq
      account_bindings = bindings.group_by(&:first)
      advertising_rub = 0.to_d
      sales_rub = 0.to_d
      covered_periods = 0
      allocation_fallback = false
      currency_conversion_fallback = false
      data_through = nil

      account_bindings.each do |account_id, pairs|
        nm_ids = pairs.map(&:last).uniq
        week_pairs(period_from).each do |week_from, week_to|
          fees = RawWb::AdSettledFee.where(
            account_id: account_id,
            period_from: week_from,
            period_to: week_to
          ).to_a
          next if fees.empty?

          covered_periods += 1
          data_through = [data_through, week_to].compact.max
          allocation = allocate_wb_advertising(fees, nm_ids, week_from:, week_to:)
          advertising_rub += allocation.fetch(:advertising_rub)
          allocation_fallback ||= allocation.fetch(:fallback_used)

          finance_rows = wb_finance_rows(account_id, week_from:, week_to:)
          net_sales_byn = wb_net_sales(finance_rows, nm_ids)
          conversion_rate = wb_implied_byn_rub_rate(fees, finance_rows)
          unless conversion_rate&.positive?
            conversion_rate = Ec::WeeklyRate.for_week(week_from)&.rate_byn_rub&.to_d
            currency_conversion_fallback = true
          end
          sales_rub += net_sales_byn * conversion_rate if conversion_rate&.positive?
        end
      end

      {
        advertising_rub: advertising_rub,
        sales_rub: sales_rub,
        data_through: data_through,
        store_count: account_bindings.keys.size,
        listing_count: bindings.size,
        coverage: base_coverage(account_bindings.keys.size, covered_periods).merge(
          attribution_rate: nil,
          allocation_fallback: allocation_fallback,
          currency_conversion_fallback: currency_conversion_fallback
        )
      }
    end

    def platform_bindings(platform_name, account_column, product_column)
      sku.sku_products
        .active
        .joins(:store)
        .merge(Ec::Store.active.where(platform: platform_name))
        .where.not(product_column => [nil, ""])
        .where.not(ec_stores: { account_column => nil })
        .pluck("ec_stores.#{account_column}", product_column)
    end

    def base_coverage(account_count, covered_periods)
      {
        covered_account_weeks: covered_periods,
        expected_account_weeks: account_count * weeks
      }
    end

    def allocate_wb_advertising(fees, target_nm_ids, week_from:, week_to:)
      campaigns = RawWb::AdCampaign
        .where(account_id: fees.first.account_id, wb_advert_id: fees.map(&:advert_id))
        .pluck(:wb_advert_id, :id)
        .to_h
      campaign_ids = campaigns.values
      spends = RawWb::AdSkuSpend
        .where(campaign_id: campaign_ids, stat_date: week_from..week_to)
        .group(:campaign_id, :nm_id)
        .sum(:spend)
      totals = spends.each_with_object(Hash.new(0.to_d)) do |((campaign_id, _nm_id), amount), memo|
        memo[campaign_id] += amount.to_d
      end
      products = RawWb::AdCampaignProduct
        .where(campaign_id: campaign_ids)
        .pluck(:campaign_id, :nm_id)
        .group_by(&:first)
        .transform_values { |rows| rows.map(&:last).uniq }
      target_ids = target_nm_ids.to_set
      advertising_rub = 0.to_d
      fallback_used = false

      fees.each do |fee|
        campaign_id = campaigns[fee.advert_id]
        next unless campaign_id

        fee_amount = fee.upd_sum_rub.to_d
        total_spend = totals[campaign_id]
        if total_spend.positive?
          target_spend = spends.sum do |(key, amount)|
            key.first == campaign_id && target_ids.include?(key.last) ? amount.to_d : 0.to_d
          end
          advertising_rub += fee_amount * target_spend / total_spend
        else
          campaign_products = products.fetch(campaign_id, [])
          target_count = campaign_products.count { |nm_id| target_ids.include?(nm_id) }
          next if campaign_products.empty? || target_count.zero?

          advertising_rub += fee_amount * target_count / campaign_products.size
          fallback_used = true
        end
      end

      { advertising_rub: advertising_rub, fallback_used: fallback_used }
    end

    def wb_finance_rows(account_id, week_from:, week_to:)
      report_ids = RawWb::SalesReport
        .where(account_id: account_id, date_to: week_from..week_to)
        .pluck(:wb_report_id)
      RawWb::FinanceDetail.where(account_id: account_id, wb_report_id: report_ids).to_a
    end

    def wb_net_sales(rows, nm_ids)
      target_ids = nm_ids.to_set
      rows.sum(0.to_d) do |row|
        next 0.to_d unless target_ids.include?(row.nm_id)

        operation = row.seller_oper_name.to_s
        amount = row.retail_amount.to_d * row.quantity.to_i.abs
        if operation.include?(RawWb::FinanceDetail::RETURN_KEYWORD)
          -amount
        elsif operation.include?(RawWb::FinanceDetail::SALE_KEYWORD)
          amount
        else
          0.to_d
        end
      end
    end

    def wb_implied_byn_rub_rate(fees, rows)
      advertising_deduction_byn = rows.sum(0.to_d) do |row|
        operation = row.seller_oper_name.to_s
        bonus = row.bonus_type_name.to_s
        if operation.include?(RawWb::FinanceDetail::DEDUCT_KEYWORD) &&
            bonus.include?(RawWb::FinanceDetail::DEDUCT_AD_KEYWORD)
          row.deduction.to_d
        else
          0.to_d
        end
      end
      return unless advertising_deduction_byn.positive?

      fees.sum { |fee| fee.upd_sum_rub.to_d } / advertising_deduction_byn
    end
  end
end
