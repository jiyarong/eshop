module Ec
  # Alternate demand-state forecast. The original service treats inventory as a
  # direct weight; this version uses inventory to estimate demand censoring and
  # keeps a separate branch for intermittent sales.
  class SkuDailySalesForecastV2 < SkuDailySalesForecast
    VERSION = "v2"
    DEFAULT_ACTIVE_DAYS = 14
    DEFAULT_RECENT_WEIGHT = BigDecimal("0.9")
    DEFAULT_STOCKOUT_UPLIFT_CAP = BigDecimal("0")
    DEFAULT_INTERMITTENT_THRESHOLD = BigDecimal("0.5")

    def initialize(active_days: DEFAULT_ACTIVE_DAYS,
      recent_weight: DEFAULT_RECENT_WEIGHT,
      stockout_uplift_cap: DEFAULT_STOCKOUT_UPLIFT_CAP,
      intermittent_threshold: DEFAULT_INTERMITTENT_THRESHOLD,
      **options)
      super(**options.merge(formula: :weighted_mean))
      @active_days = send(:positive_integer, active_days, :active_days)
      @recent_weight = send(
        :decimal_between, recent_weight, :recent_weight, min: 0, max: 1
      )
      @stockout_uplift_cap = send(
        :decimal_between, stockout_uplift_cap, :stockout_uplift_cap, min: 0, max: 1
      )
      @intermittent_threshold = send(
        :decimal_between, intermittent_threshold, :intermittent_threshold, min: 0, max: 1
      )
    end

    private

    def parameters
      super.merge(
        version: VERSION,
        formula: "demand_state_weekly_blend",
        active_days: @active_days,
        recent_weight: @recent_weight,
        stockout_uplift_cap: @stockout_uplift_cap,
        intermittent_threshold: @intermittent_threshold,
        formula_description: "weekly demand state with inventory censoring correction"
      )
    end

    def forecast_from_rows(rows, as_of:)
      observed_rows = rows.select do |row|
        row[:observed] && row[:date] <= as_of && row[:date] > as_of - @active_days
      end
      active_rows = observed_rows.reject { |row| row[:out_of_stock] }
      return empty_forecast_v2 if active_rows.empty?

      recent_rows = active_rows.select { |row| row[:date] > as_of - 7.days }
      prior_rows = active_rows.select { |row| row[:date] <= as_of - 7.days }
      recent_observed_rows = observed_rows.select { |row| row[:date] > as_of - 7.days }
      recent_mean = mean_sales(recent_rows)
      prior_mean = mean_sales(prior_rows)
      base_demand = if prior_rows.empty?
        recent_mean
      elsif recent_rows.empty?
        prior_mean
      else
        recent_coverage = recent_rows.size.to_d / recent_observed_rows.size
        effective_recent_weight = @recent_weight * recent_coverage
        (recent_mean * effective_recent_weight) + (prior_mean * (1 - effective_recent_weight))
      end

      demand_state = demand_state(active_rows)
      daily_sales = demand_state == :intermittent ? intermittent_demand(active_rows, recent_rows, prior_rows) : base_demand
      daily_sales *= (1 + inventory_censoring_uplift(observed_rows, active_rows, base_demand))

      {
        daily_sales: daily_sales,
        training_days: active_rows.size,
        inventory_days: active_rows.count { |row| row[:inventory] },
        formula: "demand_state_weekly_blend",
        demand_state: demand_state,
        daily_sales_velocity: mean_velocity(active_rows)
      }
    end

    def demand_state(active_rows)
      positive_rate = active_rows.count { |row| row[:sales].to_d.positive? }.to_d / active_rows.size
      return :intermittent if positive_rate < @intermittent_threshold

      :continuous
    end

    def intermittent_demand(active_rows, recent_rows, prior_rows)
      positive_sales = active_rows.filter_map do |row|
        sales = row[:sales].to_d
        sales if sales.positive?
      end
      return BigDecimal("0") if positive_sales.empty?

      recent_rate = positive_rate(recent_rows)
      prior_rate = prior_rows.empty? ? recent_rate : positive_rate(prior_rows)
      occurrence_rate = (recent_rate * @recent_weight) + (prior_rate * (1 - @recent_weight))
      mean_values(positive_sales) * occurrence_rate
    end

    def inventory_censoring_uplift(observed_rows, active_rows, base_demand)
      return BigDecimal("0") if observed_rows.empty? || base_demand <= 0

      stockout_days = observed_rows.count { |row| row[:out_of_stock] }
      low_inventory_days = active_rows.count do |row|
        row[:inventory] && row[:inventory] < base_demand * 2
      end
      censoring_rate = (stockout_days + (low_inventory_days * BigDecimal("0.5"))).to_d / observed_rows.size
      [ censoring_rate, BigDecimal("1") ].min * @stockout_uplift_cap
    end

    def positive_rate(rows)
      return BigDecimal("0") if rows.empty?

      rows.count { |row| row[:sales].to_d.positive? }.to_d / rows.size
    end

    def mean_sales(rows)
      values = rows.map { |row| row[:sales].to_d }
      mean_values(values)
    end

    def mean_velocity(rows)
      values = rows.filter_map { |row| row[:daily_sales_velocity] }
      values.empty? ? nil : mean_values(values)
    end

    def mean_values(values)
      return BigDecimal("0") if values.empty?

      values.sum(BigDecimal("0")) / values.size
    end

    def empty_forecast_v2
      {
        daily_sales: BigDecimal("0"),
        training_days: 0,
        inventory_days: 0,
        formula: "demand_state_weekly_blend",
        demand_state: :no_observed_demand
      }
    end
  end
end
