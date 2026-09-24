module Ec
  class SkuActualStorageQuery
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
      result = platform == "ozon" ? ozon_storage(bindings, period_from:, period_to:) : wb_storage(bindings, period_from:, period_to:)
      signed_total = result.fetch(:amounts).sum(0.to_d)
      total = [platform == "ozon" ? -signed_total : signed_total, 0.to_d].max
      sale_count = result.fetch(:sale_count)

      {
        platform: platform,
        period: { from_date: period_from, to_date: period_to, data_through: result[:data_through] },
        store_count: bindings.map(&:first).uniq.size,
        listing_count: bindings.size,
        storage: {
          total_rub: total.round(2),
          sample_count: result.fetch(:amounts).size,
          sale_count: sale_count,
          average_rub: total.positive? && sale_count.positive? ? (total / sale_count).round(6) : nil
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
        .where.not(product_column => [nil, ""])
        .where.not(ec_stores: { account_column => nil })
        .pluck("ec_stores.#{account_column}", product_column)
        .filter_map do |account_id, product_id|
          numeric_id = Integer(product_id, exception: false)
          [account_id, numeric_id] if numeric_id
        end.uniq
    end

    def ozon_storage(bindings, period_from:, period_to:)
      return { amounts: [], sale_count: 0, data_through: nil } if bindings.empty?

      allowed = bindings.to_set
      rows = RawOzon::AccrualByDay.where(
        account_id: bindings.map(&:first).uniq,
        ozon_sku_id: bindings.map(&:last).uniq,
        currency_code: "RUB",
        accrual_date: period_from..period_to
      ).pluck(:account_id, :ozon_sku_id, :type_id, :type_name, :amount, :posting_number, :accrual_date)
      storage_ids = Ec::OzonProfitAttribution::STORAGE_TYPE_IDS - [Ec::OzonProfitAttribution::CROSSDOCK_TYPE_ID]
      postings = Hash.new(0.to_d)
      amounts = []
      dates = []

      rows.each do |account_id, product_id, type_id, type_name, amount, posting, date|
        next unless allowed.include?([account_id, product_id])

        dates << date
        if type_id.to_i.zero? && posting.present?
          postings[[account_id, product_id, posting]] += amount.to_d
        elsif type_id.to_i != Ec::OzonProfitAttribution::CROSSDOCK_TYPE_ID &&
            (storage_ids.include?(type_id.to_i) || Ec::OzonProfitAttribution::STORAGE_NAMES.any? { |prefix| type_name.to_s.start_with?(prefix) }) &&
            amount.to_d.nonzero?
          amounts << amount.to_d
        end
      end

      { amounts: amounts, sale_count: postings.count { |_key, amount| amount.positive? }, data_through: dates.max }
    end

    def wb_storage(bindings, period_from:, period_to:)
      return { amounts: [], sale_count: 0, data_through: nil } if bindings.empty?

      allowed = bindings.to_set
      rows = RawWb::PaidStorage.where(
        account_id: bindings.map(&:first).uniq,
        nm_id: bindings.map(&:last).uniq,
        calc_date: period_from..period_to
      ).pluck(:account_id, :nm_id, :warehouse_price_rub, :calc_date)
      amounts = rows.filter_map do |account_id, product_id, amount, _date|
        amount.to_d if allowed.include?([account_id, product_id]) && amount.to_d.nonzero?
      end

      report_ids = RawWb::SalesReport.where(account_id: bindings.map(&:first).uniq, date_to: period_from..period_to).pluck(:account_id, :wb_report_id)
      reports_by_account = report_ids.group_by(&:first).transform_values { |entries| entries.map(&:last) }
      sale_count = bindings.sum do |account_id, product_id|
        RawWb::FinanceDetail.where(
          account_id: account_id, wb_report_id: reports_by_account.fetch(account_id, []), nm_id: product_id,
          report_type: Ec::WbProfitAttribution::REPORT_TYPE_EXPORT
        ).where("seller_oper_name LIKE ?", "%#{RawWb::FinanceDetail::SALE_KEYWORD}%").sum(:quantity).to_i.then { |quantity| [quantity, 0].max }
      end

      { amounts: amounts, sale_count: sale_count, data_through: rows.map(&:last).max }
    end
  end
end
