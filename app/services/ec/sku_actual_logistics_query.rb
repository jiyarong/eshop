module Ec
  class SkuActualLogisticsQuery
    DEFAULT_WEEKS = 4
    PLATFORMS = %w[ozon wb].freeze
    WB_DELIVERY_MODES = %w[fbo fbs].freeze
    OZON_DELIVERY_MODES = %w[fbo fbs].freeze
    WB_MARKETS = Ec::WbLedgerMarket::MARKET_REPORT_TYPES.keys.freeze
    # Ozon FBS books its fees under three groups: the direct-flow leg (the outbound fee proper), the
    # hand-over of the parcel by the seller (drop-off at a pickup point or sorting centre, delivery to
    # the hand-over place, last mile) and the return leg. FBO has no hand-over.
    OZON_FBS_HANDOVER_TYPE_IDS = [ 16, 29, 98 ].to_set.freeze
    WB_OUTBOUND_BONUS_PREFIXES = ["К клиенту при продаже", "К клиенту при отмене"].freeze
    WB_RETURN_BONUS_PREFIXES = ["От клиента при возврате", "От клиента при отмене"].freeze
    # Goods sent back to the seller ("Возврат ... (К продавцу)") travel as their own parcels with
    # their own srid, so they cannot be tied to a single order. They are part of what a returned
    # order costs and are spread over the returned orders of the period.
    WB_RETURN_TO_SELLER_BONUS_PREFIXES = ["Возврат"].freeze

    # delivery_mode narrows to FBW/FBS (WB) or FBO/FBS (Ozon); market (WB only) to the Belarus-local
    # or export-to-Russia part of the ledger. Nil means every parcel of the platform.
    def self.run(sku:, today:, platform: "ozon", delivery_mode: nil, market: nil, weeks: DEFAULT_WEEKS)
      new(sku:, today:, platform:, delivery_mode:, market:, weeks:).run
    end

    def initialize(sku:, today:, platform: "ozon", delivery_mode: nil, market: nil, weeks: DEFAULT_WEEKS)
      @sku = sku
      @today = today.to_date
      @platform = platform.to_s.downcase
      @delivery_mode = delivery_mode.to_s.downcase.presence
      @market = market.to_s.downcase.presence
      @weeks = Integer(weeks)
      raise ArgumentError, "unsupported_platform" unless PLATFORMS.include?(@platform)
      modes = @platform == "wb" ? WB_DELIVERY_MODES : OZON_DELIVERY_MODES
      raise ArgumentError, "unsupported_delivery_mode" if @delivery_mode && !modes.include?(@delivery_mode)
      raise ArgumentError, "unsupported_market" if @market && !(@platform == "wb" && WB_MARKETS.include?(@market))
      raise ArgumentError, "weeks_must_be_positive" unless @weeks.positive?
    end

    def run
      period_to = today.beginning_of_week(:monday) - 1.day
      period_from = period_to - (weeks * 7 - 1).days

      return wb_payload(period_from:, period_to:) if platform == "wb"

      ozon_payload(period_from:, period_to:)
    end

    private

    attr_reader :sku, :today, :platform, :delivery_mode, :market, :weeks

    def ozon_payload(period_from:, period_to:)
      bindings = ozon_bindings
      rows = accrual_rows(bindings, period_from:, period_to:)
      rows = rows_of_delivery_mode(rows) if delivery_mode
      grouped_fees = grouped_logistics_fees(rows, bindings)

      {
        platform: "ozon",
        delivery_mode: delivery_mode,
        period: {
          from_date: period_from,
          to_date: period_to,
          data_through: rows.filter_map(&:accrual_date).max
        },
        store_count: bindings.map(&:first).uniq.size,
        listing_count: bindings.size,
        outbound: metric_payload(grouped_fees.fetch(:outbound)),
        handover: metric_payload(grouped_fees.fetch(:handover)),
        return: metric_payload(grouped_fees.fetch(:return)),
        cross_dock: delivery_mode == "fbs" ? nil : Ec::SkuActualCrossDockQuery.run(sku: sku, today: today),
        return_rate: return_rate_payload(grouped_fees)
      }
    end

    # Ozon FBS postings are the ones in the FBS posting table; every other posting is FBO.
    def rows_of_delivery_mode(rows)
      posting_numbers = rows.filter_map(&:posting_number).uniq
      fbs_numbers = RawOzon::PostingFbs.where(posting_number: posting_numbers).pluck(:posting_number).to_set
      rows.select { |row| (fbs_numbers.include?(row.posting_number) ? "fbs" : "fbo") == delivery_mode }
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
        market: market,
        period: {
          from_date: period_from,
          to_date: period_to,
          data_through: matched_rows.filter_map(&:rr_dt).max
        },
        store_count: bindings.map(&:first).uniq.size,
        listing_count: bindings.size,
        outbound: positive_metric_payload(grouped_fees.fetch(:outbound)),
        return: wb_return_payload(grouped_fees.fetch(:return), grouped_fees.fetch(:return_to_seller)),
        return_to_seller: positive_metric_payload(grouped_fees.fetch(:return_to_seller)),
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
        .then { |scope| market ? scope.where(report_type: Ec::WbLedgerMarket.report_type_for(market)) : scope }
        .select(:account_id, :nm_id, :shk_id, :srid, :rr_dt, :bonus_type_name, :delivery_method, :delivery_rub)
        .to_a
    end

    def grouped_logistics_fees(rows, bindings)
      allowed_bindings = bindings.to_set
      grouped = {
        outbound: Hash.new(0.to_d),
        handover: Hash.new(0.to_d),
        return: Hash.new(0.to_d)
      }

      rows.each do |row|
        next unless allowed_bindings.include?([row.account_id, row.ozon_sku_id])
        next if row.posting_number.blank?

        category = logistics_category(row.type_id, row.type_name)
        next unless category

        category = :handover if category == :outbound && delivery_mode == "fbs" && OZON_FBS_HANDOVER_TYPE_IDS.include?(row.type_id.to_i)
        key = [row.account_id, row.ozon_sku_id, row.posting_number]
        grouped.fetch(category)[key] += row.amount.to_d
      end

      grouped
    end

    def grouped_wb_logistics_fees(rows, bindings)
      allowed_bindings = bindings.to_set
      grouped = {
        outbound: Hash.new(0.to_d),
        return: Hash.new(0.to_d),
        return_to_seller: Hash.new(0.to_d)
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
      return :return_to_seller if WB_RETURN_TO_SELLER_BONUS_PREFIXES.any? { |prefix| name.start_with?(prefix) }
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

    # Cost of a returned order = what the customer leg cost plus the share of parcels sent back
    # to the seller. Seller parcels have their own references, so they are added to the total and
    # divided by the returned orders (references with a customer return leg).
    def wb_return_payload(customer_returns, seller_returns)
      customer = customer_returns.values.select(&:positive?)
      seller_total = seller_returns.values.select(&:positive?).sum(0.to_d)
      total = customer.sum(0.to_d) + seller_total
      average = total / customer.size if total.positive? && customer.any?

      {
        total_rub: total.round(2),
        sample_count: customer.size,
        average_rub: average&.round(2)
      }
    end

    # Return rate = postings billed a return leg / postings billed an outbound leg.
    # A posting that was never delivered (not picked up, cancelled) books no SaleRevenue yet
    # pays both legs, so a revenue-reversal count would miss it. This is the ratio the
    # calculator's amortization needs: per net sale it adds (outbound + return) x r / (1 - r).
    # `order_count` is the number of outbound postings, `return_count` the number of returns.
    def return_rate_payload(grouped_fees)
      order_count = grouped_fees.fetch(:outbound).values.count { |amount| !amount.zero? }
      return_count = grouped_fees.fetch(:return).values.count { |amount| !amount.zero? }
      rate = return_count.to_d / order_count if order_count.positive?

      {
        order_count: order_count,
        return_count: return_count,
        rate: rate&.round(10)
      }
    end
  end
end
