module Ec
  # What Ozon cross-docking really costs per unit of an SKU's goods that reach the warehouse.
  #
  # Ozon bills cross-docking once per supply (accrual type 12; `unit_number` is the supply id,
  # and the sync splits each supply-level line over the supply's SKUs by quantity x inner
  # volume), long before the goods sell. So neither "the average charge line" (a line is a box
  # or pallet, not a unit) nor "fees of the period / units sold in the period" (supplies and
  # sales do not move together) says what one unit costs. The cost of a unit is the fee of the
  # supplies it arrived in divided by the units those supplies carried:
  #
  #   per unit = sum of the SKU's cross-dock fees in the window
  #              / (units of the SKU in the supplies that carried a fee
  #                 + units of the SKU in direct supplies of the window, which carry none)
  #
  # The window is the last full weeks, widened to all history when it holds fewer than
  # MIN_UNITS fee-bearing units. Supplies are picked by the date their fee was booked: Ozon
  # books it when it accepts the supply, before the supply status turns COMPLETED.
  class SkuActualCrossDockQuery
    CROSSDOCK_TYPE_ID = 12
    WEEKS = 12
    MIN_UNITS = 20
    DEAD_SUPPLY_STATUSES = %w[CANCELLED OVERDUE].freeze

    def self.run(sku:, today:, weeks: WEEKS, min_units: MIN_UNITS)
      new(sku:, today:, weeks:, min_units:).run
    end

    def initialize(sku:, today:, weeks: WEEKS, min_units: MIN_UNITS)
      @sku = sku
      @today = today.to_date
      @weeks = Integer(weeks)
      @min_units = Integer(min_units)
      raise ArgumentError, "weeks_must_be_positive" unless @weeks.positive?
    end

    def run
      period_to = today.beginning_of_week(:monday) - 1.day
      window = summarize(from: period_to - (weeks * 7 - 1).days, to: period_to)
      expanded = false
      if window[:unit_count] < min_units
        everything = summarize(from: nil, to: period_to)
        if everything[:unit_count] > window[:unit_count]
          window = everything
          expanded = true
        end
      end

      units = window[:unit_count] + window[:direct_unit_count]
      {
        total_rub: window[:fee].round(2),
        sample_count: window[:supply_count],
        unit_count: window[:unit_count],
        direct_unit_count: window[:direct_unit_count],
        average_rub: window[:fee].positive? && units.positive? ? (window[:fee] / units).round(2) : nil,
        window_weeks: weeks,
        expanded_to_all_history: expanded,
        from_date: window[:from_date],
        to_date: period_to,
        data_through: window[:data_through],
        unmatched_supply_count: window[:unmatched_supply_count],
        unmatched_fee_rub: window[:unmatched_fee].round(2)
      }
    end

    private

    attr_reader :sku, :today, :weeks, :min_units

    def summarize(from:, to:)
      bindings = ozon_bindings
      return empty_summary if bindings.empty?

      allowed = bindings.to_set
      scope = RawOzon::AccrualByDay.where(
        account_id: bindings.map(&:first).uniq,
        ozon_sku_id: bindings.map(&:last).uniq,
        type_id: CROSSDOCK_TYPE_ID
      )
      scope = from ? scope.where(accrual_date: from..to) : scope.where(accrual_date: ..to)
      fees = Hash.new(0.to_d)
      dates = Hash.new { |hash, key| hash[key] = [] }
      scope.pluck(:account_id, :ozon_sku_id, :unit_number, :amount, :accrual_date).each do |account_id, ozon_sku_id, unit_number, amount, date|
        next unless allowed.include?([account_id, ozon_sku_id])
        next if amount.to_d.zero?

        supply_id = Integer(unit_number.to_s, exception: false)
        key = [account_id, ozon_sku_id, supply_id]
        fees[key] += -amount.to_d
        dates[key] << date
      end

      quantities = supplied_quantities(fees.keys)
      matched = fees.select { |key, fee| fee.positive? && quantities[key].to_i.positive? }
      unmatched = fees.select { |key, fee| fee.positive? && !quantities[key].to_i.positive? }
      matched_dates = matched.keys.flat_map { |key| dates[key] }

      {
        fee: matched.values.sum(0.to_d),
        unit_count: matched.keys.sum { |key| quantities.fetch(key) },
        supply_count: matched.keys.map { |account_id, _sku_id, supply_id| [account_id, supply_id] }.uniq.size,
        direct_unit_count: direct_units(allowed, from:, to:),
        unmatched_supply_count: unmatched.keys.map { |account_id, _sku_id, supply_id| [account_id, supply_id] }.uniq.size,
        unmatched_fee: unmatched.values.sum(0.to_d),
        from_date: from || matched_dates.min,
        data_through: matched_dates.max
      }
    end

    def empty_summary
      { fee: 0.to_d, unit_count: 0, supply_count: 0, direct_unit_count: 0, unmatched_supply_count: 0,
        unmatched_fee: 0.to_d, from_date: nil, data_through: nil }
    end

    # { [account_id, ozon_sku_id, supply_id] => units of that SKU in that supply }
    def supplied_quantities(keys)
      supply_ids = keys.map(&:last).compact.uniq
      return {} if supply_ids.empty?

      RawOzon::SupplyOrderItem
        .joins(:supply_order)
        .where(raw_ozon_supply_orders: { account_id: keys.map(&:first).uniq })
        .where(ozon_supply_id: supply_ids, platform_sku_id: keys.map { |key| key[1] }.uniq)
        .group("raw_ozon_supply_orders.account_id", :platform_sku_id, :ozon_supply_id)
        .sum(:quantity)
        .transform_keys { |account_id, platform_sku_id, supply_id| [account_id, platform_sku_id, supply_id] }
    end

    # Units that reached the warehouse by direct supply in the window: they cost no cross-dock
    # fee but share the average. Direct supplies carry no fee date, so their creation date is used.
    def direct_units(allowed, from:, to:)
      scope = RawOzon::SupplyOrderItem
        .joins(:supply_order)
        .where(raw_ozon_supply_orders: { account_id: allowed.map(&:first).uniq })
        .where(platform_sku_id: allowed.map(&:last).uniq)
        .where("raw_ozon_supply_order_items.is_crossdock IS NOT TRUE")
        .where.not(raw_ozon_supply_orders: { status: DEAD_SUPPLY_STATUSES })
        .where.not(state: DEAD_SUPPLY_STATUSES)
      created = from ? from.beginning_of_day..to.end_of_day : ..to.end_of_day
      scope = scope.where(raw_ozon_supply_orders: { created_at: created })
      scope.group("raw_ozon_supply_orders.account_id", :platform_sku_id).sum(:quantity).sum do |(account_id, platform_sku_id), quantity|
        allowed.include?([account_id, platform_sku_id]) ? quantity.to_i : 0
      end
    end

    def ozon_bindings
      @ozon_bindings ||= sku.sku_products
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
  end
end
