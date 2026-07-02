module Ec
  class ProjectedStockRoiCalculator
    PROJECTED_DAYS = BigDecimal("180")
    DAYS_PER_WEEK = BigDecimal("7")
    WEEKS_PER_MONTH = BigDecimal("4.33")
    STORAGE_FEE_CNY_PER_M3_MONTH = BigDecimal("100")
    MONTHLY_INTEREST_RATE = BigDecimal("0.01")
    LITERS_PER_CUBIC_METER = BigDecimal("1000")

    def self.call(...)
      new(...).call
    end

    def initialize(net_sales_quantity:, operating_profit_cny:, days_count:, unit_goods_cost_cny:, unit_volume_l:)
      @net_sales_quantity = decimal(net_sales_quantity)
      @operating_profit_cny = decimal(operating_profit_cny)
      @days_count = decimal(days_count)
      @unit_goods_cost_cny = decimal(unit_goods_cost_cny)
      @unit_volume_l = decimal(unit_volume_l)
    end

    def call
      return invalid_payload(missing_cost: true) if unit_goods_cost_cny <= 0
      return invalid_payload(missing_volume: true) if unit_volume_l <= 0
      return invalid_payload(invalid_date_range: true) if days_count <= 0
      return invalid_payload(non_positive_net_sales: true) if net_sales_quantity <= 0

      average_daily_net_sales = net_sales_quantity / days_count
      projected_stock_qty_180d = average_daily_net_sales * PROJECTED_DAYS
      average_inventory_qty = projected_stock_qty_180d / 2
      projected_weekly_sales = average_daily_net_sales * DAYS_PER_WEEK
      projected_weeks_to_clear = projected_stock_qty_180d / projected_weekly_sales
      projected_months_to_clear = projected_weeks_to_clear / WEEKS_PER_MONTH
      unit_volume_m3 = unit_volume_l / LITERS_PER_CUBIC_METER
      predicted_storage_cost_cny =
        average_inventory_qty *
        projected_months_to_clear *
        unit_volume_m3 *
        STORAGE_FEE_CNY_PER_M3_MONTH
      predicted_interest_cost_cny =
        average_inventory_qty *
        projected_months_to_clear *
        unit_goods_cost_cny *
        MONTHLY_INTEREST_RATE
      cost_base_cny = projected_stock_qty_180d * unit_goods_cost_cny
      adjusted_operating_net_profit_cny =
        operating_profit_cny -
        predicted_storage_cost_cny -
        predicted_interest_cost_cny

      {
        missing_cost: false,
        missing_volume: false,
        invalid_date_range: false,
        non_positive_net_sales: false,
        calculable: true,
        average_daily_net_sales: average_daily_net_sales,
        projected_stock_qty_180d: projected_stock_qty_180d,
        average_inventory_qty: average_inventory_qty,
        projected_months_to_clear: projected_months_to_clear,
        predicted_storage_cost_cny: predicted_storage_cost_cny,
        predicted_interest_cost_cny: predicted_interest_cost_cny,
        cost_base_cny: cost_base_cny,
        adjusted_operating_net_profit_cny: adjusted_operating_net_profit_cny,
        roi: Ec::RoiCalculator.for_profit_and_cost_base(
          operating_profit: adjusted_operating_net_profit_cny,
          cost_base: cost_base_cny
        )[:roi]
      }
    end

    private

    attr_reader :net_sales_quantity, :operating_profit_cny, :days_count, :unit_goods_cost_cny, :unit_volume_l

    def invalid_payload(missing_cost: false, missing_volume: false, invalid_date_range: false, non_positive_net_sales: false)
      {
        missing_cost: missing_cost,
        missing_volume: missing_volume,
        invalid_date_range: invalid_date_range,
        non_positive_net_sales: non_positive_net_sales,
        calculable: false,
        average_daily_net_sales: nil,
        projected_stock_qty_180d: nil,
        average_inventory_qty: nil,
        projected_months_to_clear: nil,
        predicted_storage_cost_cny: nil,
        predicted_interest_cost_cny: nil,
        cost_base_cny: nil,
        adjusted_operating_net_profit_cny: nil,
        roi: nil
      }
    end

    def decimal(value)
      BigDecimal(value.to_s)
    end
  end
end
