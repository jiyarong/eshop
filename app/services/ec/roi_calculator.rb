module Ec
  class RoiCalculator
    WEEKS_PER_MONTH = BigDecimal("4.33")
    WEEKS_PER_YEAR = BigDecimal("52")
    CUBIC_CM_PER_CUBIC_METER = BigDecimal("1000000")
    PERCENT_DIVISOR = BigDecimal("100")

    def self.call(...)
      new(...).call
    end

    def self.for_profit_and_cost_base(operating_profit:, cost_base:)
      cost_base = BigDecimal(cost_base.to_s)
      return { roi: nil } if cost_base <= 0

      {
        roi: BigDecimal(operating_profit.to_s) / cost_base
      }
    end

    def initialize(cost:, total_qty:, weekly_sales:, unit_profit:, len:, width:, height:, storage_fee:, interest_rate:)
      @cost = decimal(cost)
      @total_qty = decimal(total_qty)
      @weekly_sales = decimal(weekly_sales)
      @unit_profit = decimal(unit_profit)
      @len = decimal(len)
      @width = decimal(width)
      @height = decimal(height)
      @storage_fee = decimal(storage_fee)
      @interest_rate = decimal(interest_rate)
    end

    def call
      return { roi: nil, annualized_return: nil } if invalid_base_inputs?

      {
        roi: roi,
        annualized_return: annualized_return
      }
    end

    private

    attr_reader :cost, :total_qty, :weekly_sales, :unit_profit, :len, :width, :height, :storage_fee, :interest_rate

    def invalid_base_inputs?
      weekly_sales <= 0 || total_qty <= 0 || cost <= 0
    end

    def volume
      @volume ||= (len * width * height) / CUBIC_CM_PER_CUBIC_METER
    end

    def weeks_to_clear
      @weeks_to_clear ||= total_qty / weekly_sales
    end

    def months_to_clear
      @months_to_clear ||= weeks_to_clear / WEEKS_PER_MONTH
    end

    def avg_inventory
      @avg_inventory ||= total_qty / 2
    end

    def orig_total_profit
      @orig_total_profit ||= total_qty * unit_profit
    end

    def total_storage_cost
      @total_storage_cost ||= avg_inventory * months_to_clear * volume * storage_fee
    end

    def total_interest
      @total_interest ||= avg_inventory * months_to_clear * cost * (interest_rate / PERCENT_DIVISOR)
    end

    def actual_net_profit
      @actual_net_profit ||= orig_total_profit - total_storage_cost - total_interest
    end

    def total_initial_investment
      @total_initial_investment ||= total_qty * cost
    end

    def roi
      @roi ||= actual_net_profit / total_initial_investment
    end

    def annualized_return
      @annualized_return ||= roi * (WEEKS_PER_YEAR / weeks_to_clear)
    end

    def decimal(value)
      BigDecimal(value.to_s)
    end
  end
end
