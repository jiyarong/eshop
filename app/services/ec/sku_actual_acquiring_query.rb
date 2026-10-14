module Ec
  # Acquiring (payment) fee as a share of what the platform charges commission on, over the
  # last full weeks. The calculators price acquiring as rate x commission base, so the ratio is
  # measured on the same base: Ozon SaleRevenue postings, WB sale rows' retail_price_with_disc.
  class SkuActualAcquiringQuery
    DEFAULT_WEEKS = 4
    PLATFORMS = %w[ozon wb].freeze

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
      bindings = platform_bindings
      result = platform == "ozon" ? ozon_totals(bindings, period_from:, period_to:) : wb_totals(bindings, period_from:, period_to:)
      fee = result.fetch(:fee)
      base = result.fetch(:base)

      {
        platform: platform,
        period: { from_date: period_from, to_date: period_to, data_through: result[:data_through] },
        store_count: bindings.map(&:first).uniq.size,
        listing_count: bindings.size,
        acquiring: {
          fee: fee.round(2),
          base: base.round(2),
          sample_count: result.fetch(:sample_count),
          rate: base.positive? && fee.positive? ? (fee / base).round(10) : nil
        }
      }
    end

    private

    attr_reader :sku, :platform, :today, :weeks

    def platform_bindings
      account_column = platform == "ozon" ? :ozon_raw_account_id : :wb_raw_account_id
      product_column = platform == "ozon" ? :platform_sku_id : :product_id
      sku.sku_products.active.joins(:store)
        .merge(Ec::Store.active.where(platform: platform))
        .where.not(product_column => [ nil, "" ])
        .where.not(ec_stores: { account_column => nil })
        .pluck("ec_stores.#{account_column}", product_column)
        .filter_map do |account_id, product_id|
          numeric_id = Integer(product_id, exception: false)
          [ account_id, numeric_id ] if numeric_id
        end.uniq
    end

    def empty_totals
      { fee: 0.to_d, base: 0.to_d, sample_count: 0, data_through: nil }
    end

    # Acquiring is only attributed to postings that also have SaleRevenue in the period, the
    # same rule the profit attribution uses; returns reduce both sides.
    def ozon_totals(bindings, period_from:, period_to:)
      return empty_totals if bindings.empty?

      allowed = bindings.to_set
      rows = RawOzon::AccrualByDay.where(
        account_id: bindings.map(&:first).uniq,
        ozon_sku_id: bindings.map(&:last).uniq,
        currency_code: "RUB",
        accrual_date: period_from..period_to,
        type_id: [ 0, 1 ]
      ).pluck(:account_id, :ozon_sku_id, :type_id, :amount, :posting_number, :accrual_date)
      rows = rows.select { |account_id, product_id, *| allowed.include?([ account_id, product_id ]) }

      revenue_postings = rows.filter_map do |account_id, product_id, type_id, _amount, posting, _date|
        [ account_id, product_id, posting_key(posting) ] if type_id.to_i.zero? && posting.present?
      end.to_set
      base = 0.to_d
      fee = 0.to_d
      count = 0
      rows.each do |account_id, product_id, type_id, amount, posting, _date|
        if type_id.to_i.zero?
          base += amount.to_d
        elsif revenue_postings.include?([ account_id, product_id, posting_key(posting) ])
          fee += -amount.to_d
          count += 1
        end
      end

      { fee:, base:, sample_count: count, data_through: rows.map(&:last).max }
    end

    def wb_totals(bindings, period_from:, period_to:)
      return empty_totals if bindings.empty?

      allowed = bindings.to_set
      rows = RawWb::FinanceDetail.where(
        account_id: bindings.map(&:first).uniq,
        nm_id: bindings.map(&:last).uniq,
        rr_dt: period_from..period_to
      ).where("seller_oper_name LIKE ?", "%#{RawWb::FinanceDetail::SALE_KEYWORD}%")
        .pluck(:account_id, :nm_id, :acquiring_fee, :retail_price_with_disc, :quantity, :rr_dt)
        .select { |account_id, nm_id, *| allowed.include?([ account_id, nm_id ]) }

      fee = 0.to_d
      base = 0.to_d
      count = 0
      rows.each do |_account_id, _nm_id, acquiring_fee, price, quantity, _date|
        next unless acquiring_fee.to_d.positive? && price.to_d.positive?

        fee += acquiring_fee.to_d
        base += price.to_d * [ quantity.to_i, 1 ].max
        count += 1
      end

      { fee:, base:, sample_count: count, data_through: rows.map(&:last).max }
    end

    def posting_key(posting_number)
      return nil unless posting_number

      parts = posting_number.to_s.split("-")
      parts.length >= 2 ? "#{parts[0]}-#{parts[1]}" : posting_number
    end
  end
end
