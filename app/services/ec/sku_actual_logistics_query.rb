module Ec
  class SkuActualLogisticsQuery
    DEFAULT_WEEKS = 4

    def self.run(sku:, today:, weeks: DEFAULT_WEEKS)
      new(sku:, today:, weeks:).run
    end

    def initialize(sku:, today:, weeks: DEFAULT_WEEKS)
      @sku = sku
      @today = today.to_date
      @weeks = Integer(weeks)
      raise ArgumentError, "weeks_must_be_positive" unless @weeks.positive?
    end

    def run
      period_to = today.beginning_of_week(:monday) - 1.day
      period_from = period_to - (weeks * 7 - 1).days
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

    private

    attr_reader :sku, :today, :weeks

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
