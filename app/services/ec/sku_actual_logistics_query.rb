module Ec
  class SkuActualLogisticsQuery
    DEFAULT_WEEKS = 4
    PLATFORMS = %w[ozon wb].freeze
    WB_DELIVERY_MODES = %w[fbo fbs].freeze
    WB_OUTBOUND_BONUS_PREFIXES = ["К клиенту при продаже", "К клиенту при отмене"].freeze
    WB_RETURN_BONUS_PREFIXES = ["От клиента при возврате", "От клиента при отмене"].freeze

    def self.run(sku:, today:, platform: "ozon", delivery_mode: nil, weeks: DEFAULT_WEEKS)
      new(sku:, today:, platform:, delivery_mode:, weeks:).run
    end

    def initialize(sku:, today:, platform: "ozon", delivery_mode: nil, weeks: DEFAULT_WEEKS)
      @sku = sku
      @today = today.to_date
      @platform = platform.to_s.downcase
      @delivery_mode = delivery_mode.to_s.downcase.presence
      @weeks = Integer(weeks)
      raise ArgumentError, "unsupported_platform" unless PLATFORMS.include?(@platform)
      if @platform == "wb" && @delivery_mode && !WB_DELIVERY_MODES.include?(@delivery_mode)
        raise ArgumentError, "unsupported_delivery_mode"
      end
      raise ArgumentError, "weeks_must_be_positive" unless @weeks.positive?
    end

    def run
      period_to = today.beginning_of_week(:monday) - 1.day
      period_from = period_to - (weeks * 7 - 1).days

      return wb_payload(period_from:, period_to:) if platform == "wb"

      ozon_payload(period_from:, period_to:)
    end

    private

    attr_reader :sku, :today, :platform, :delivery_mode, :weeks

    def ozon_payload(period_from:, period_to:)
      bindings = ozon_bindings
      rows = accrual_rows(bindings, period_from:, period_to:)
      grouped_fees = grouped_logistics_fees(rows, bindings)

      {
        platform: "ozon",
        period: {
          from_date: period_from,
          to_date: period_to,
          data_through: rows.filter_map(&:accrual_date).max
        },
        store_count: bindings.map(&:first).uniq.size,
        listing_count: bindings.size,
        outbound: metric_payload(grouped_fees.fetch(:outbound)),
        return: metric_payload(grouped_fees.fetch(:return)),
        cross_dock: cross_dock_payload(rows, bindings),
        return_rate: return_rate_payload(rows, bindings)
      }
    end

    def wb_payload(period_from:, period_to:)
      bindings = wb_bindings
      rows = wb_finance_rows(bindings, period_from:, period_to:)
      grouped_fees, missing_rate_count = grouped_wb_logistics_fees(rows, bindings)
      allowed_bindings = bindings.to_set
      matched_rows = rows.select do |row|
        allowed_bindings.include?([row.account_id, row.nm_id]) &&
          wb_delivery_mode_matches?(row.delivery_method) &&
          wb_logistics_category(row.bonus_type_name)
      end

      {
        platform: "wb",
        delivery_mode: delivery_mode,
        period: {
          from_date: period_from,
          to_date: period_to,
          data_through: matched_rows.filter_map(&:rr_dt).max
        },
        store_count: bindings.map(&:first).uniq.size,
        listing_count: bindings.size,
        outbound: positive_metric_payload(grouped_fees.fetch(:outbound)),
        return: positive_metric_payload(grouped_fees.fetch(:return)),
        source_currency: "BYN",
        output_currency: "RUB",
        missing_exchange_rate_row_count: missing_rate_count
      }
    end

    def ozon_bindings
      sku.sku_products
        .active
        .joins(:store)
        .merge(Ec::Store.active.where(platform: "ozon"))
        .where.not(platform_sku_id: [nil, ""])
        .where.not(ec_stores: { ozon_raw_account_id: nil })
        .pluck("ec_stores.ozon_raw_account_id", :platform_sku_id)
        .filter_map do |account_id, platform_sku_id|
          ozon_sku_id = Integer(platform_sku_id, exception: false)
          [account_id, ozon_sku_id] if ozon_sku_id
        end
        .uniq
    end

    def wb_bindings
      sku.sku_products
        .active
        .joins(:store)
        .merge(Ec::Store.active.where(platform: "wb"))
        .where.not(product_id: [nil, ""])
        .where.not(ec_stores: { wb_raw_account_id: nil })
        .pluck("ec_stores.wb_raw_account_id", :product_id)
        .filter_map do |account_id, product_id|
          nm_id = Integer(product_id, exception: false)
          [account_id, nm_id] if nm_id
        end
        .uniq
    end

    def accrual_rows(bindings, period_from:, period_to:)
      return [] if bindings.empty?

      RawOzon::AccrualByDay
        .where(
          account_id: bindings.map(&:first).uniq,
          ozon_sku_id: bindings.map(&:last).uniq,
          accrual_date: period_from..period_to
        )
        .select(:account_id, :ozon_sku_id, :posting_number, :accrual_date, :type_id, :type_name, :amount)
        .to_a
    end

    def wb_finance_rows(bindings, period_from:, period_to:)
      return [] if bindings.empty?

      RawWb::FinanceDetail
        .where(
          account_id: bindings.map(&:first).uniq,
          nm_id: bindings.map(&:last).uniq,
          rr_dt: period_from..period_to
        )
        .where(
          "seller_oper_name LIKE :logistics OR seller_oper_name LIKE :correction",
          logistics: "%#{RawWb::FinanceDetail::LOGISTIC_KEYWORD}%",
          correction: "%#{RawWb::FinanceDetail::CORR_LOGISTIC_KEYWORD}%"
        )
        .where.not(delivery_rub: [nil, 0])
        .select(:account_id, :nm_id, :shk_id, :srid, :rr_dt, :bonus_type_name, :delivery_method, :delivery_rub)
        .to_a
    end

    def grouped_logistics_fees(rows, bindings)
      allowed_bindings = bindings.to_set
      grouped = {
        outbound: Hash.new(0.to_d),
        return: Hash.new(0.to_d)
      }

      rows.each do |row|
        next unless allowed_bindings.include?([row.account_id, row.ozon_sku_id])
        next if row.posting_number.blank?

        category = logistics_category(row.type_id, row.type_name)
        next unless category

        key = [row.account_id, row.ozon_sku_id, row.posting_number]
        grouped.fetch(category)[key] += row.amount.to_d
      end

      grouped
    end

    def grouped_wb_logistics_fees(rows, bindings)
      allowed_bindings = bindings.to_set
      grouped = {
        outbound: Hash.new(0.to_d),
        return: Hash.new(0.to_d)
      }
      rates = wb_rates_by_week(rows)
      missing_rate_count = 0

      rows.each do |row|
        next unless allowed_bindings.include?([row.account_id, row.nm_id])
        next unless wb_delivery_mode_matches?(row.delivery_method)

        category = wb_logistics_category(row.bonus_type_name)
        next unless category

        rate = rates[row.rr_dt.beginning_of_week(:monday)]
        unless rate&.positive?
          missing_rate_count += 1
          next
        end

        reference = row.srid.presence || ("shk:#{row.shk_id}" if row.shk_id.to_i.positive?)
        next unless reference

        key = [row.account_id, row.nm_id, reference]
        grouped.fetch(category)[key] += row.delivery_rub.to_d * rate
      end

      [grouped, missing_rate_count]
    end

    def wb_delivery_mode_matches?(raw_delivery_method)
      return true unless delivery_mode

      prefix = delivery_mode == "fbo" ? "FBW" : "FBS"
      raw_delivery_method.to_s.start_with?(prefix)
    end

    def wb_rates_by_week(rows)
      rows.filter_map(&:rr_dt).map { |date| date.beginning_of_week(:monday) }.uniq.index_with do |week|
        Ec::WeeklyRate.for_week(week)&.rate_byn_rub&.to_d
      end
    end

    def wb_logistics_category(bonus_type_name)
      name = bonus_type_name.to_s
      return :outbound if WB_OUTBOUND_BONUS_PREFIXES.any? { |prefix| name.start_with?(prefix) }
      return :return if WB_RETURN_BONUS_PREFIXES.any? { |prefix| name.start_with?(prefix) }
    end

    def logistics_category(type_id, type_name)
      id = type_id.to_i
      return :outbound if Ec::OzonProfitAttribution::DELIVERY_TYPE_IDS.include?(id)
      return :return if Ec::OzonProfitAttribution::RETURN_TYPE_IDS.include?(id)

      known_non_logistics_ids =
        Ec::OzonProfitAttribution::STORAGE_TYPE_IDS |
        Ec::OzonProfitAttribution::DISPATCH_TYPE_IDS |
        Ec::OzonProfitAttribution::PACKING_TYPE_IDS |
        Ec::OzonProfitAttribution::DEFECT_TYPE_IDS |
        Ec::OzonProfitAttribution::AD_TYPE_IDS |
        Ec::OzonProfitAttribution::UNALLOCATED_TYPE_IDS |
        [0, 1, 69].to_set
      return if known_non_logistics_ids.include?(id)

      name = type_name.to_s
      return :outbound if Ec::OzonProfitAttribution::DELIVERY_NAMES.any? { |prefix| name.start_with?(prefix) }
      return :return if Ec::OzonProfitAttribution::RETURN_NAMES.any? { |prefix| name.start_with?(prefix) }
    end

    def metric_payload(grouped_amounts)
      amounts = grouped_amounts.values.reject(&:zero?)
      total = -amounts.sum(0.to_d)
      average = total.positive? && amounts.any? ? total / amounts.size : nil

      {
        total_rub: total.round(2),
        sample_count: amounts.size,
        average_rub: average&.round(2)
      }
    end

    def positive_metric_payload(grouped_amounts)
      amounts = grouped_amounts.values.select(&:positive?)
      total = amounts.sum(0.to_d)
      average = total / amounts.size if total.positive? && amounts.any?

      {
        total_rub: total.round(2),
        sample_count: amounts.size,
        average_rub: average&.round(2)
      }
    end

    def return_rate_payload(rows, bindings)
      allowed_bindings = bindings.to_set
      posting_revenue = Hash.new(0.to_d)

      rows.each do |row|
        next unless allowed_bindings.include?([row.account_id, row.ozon_sku_id])
        next unless row.type_id.to_i.zero? && row.posting_number.present?

        key = [row.account_id, row.ozon_sku_id, row.posting_number]
        posting_revenue[key] += row.amount.to_d
      end

      order_count = posting_revenue.count { |_key, net| net >= 0 }
      return_count = posting_revenue.count { |_key, net| net <= 0 }
      rate = return_count.to_d / order_count if order_count.positive?

      {
        order_count: order_count,
        return_count: return_count,
        rate: rate&.round(10)
      }
    end

    def cross_dock_payload(rows, bindings)
      allowed_bindings = bindings.to_set
      amounts = rows.filter_map do |row|
        next unless allowed_bindings.include?([row.account_id, row.ozon_sku_id])
        next unless row.type_id.to_i == Ec::OzonProfitAttribution::CROSSDOCK_TYPE_ID

        amount = row.amount.to_d
        amount unless amount.zero?
      end
      total = amounts.sum(0.to_d).abs
      average = total / amounts.size if total.positive? && amounts.any?

      {
        total_rub: total.round(2),
        sample_count: amounts.size,
        average_rub: average&.round(2)
      }
    end
  end
end
