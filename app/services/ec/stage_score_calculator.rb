module Ec
  class StageScoreCalculator
    STANDARD_MIN_WEEKS = 6
    NEWLY_SELLING_MIN_WEEKS = 4
    HEALTHY_AD_RATIO_RANGE = 5.0..15.0

    def self.call(observations:, window_type:, clearance: {})
      new(observations:, window_type:, clearance:).call
    end

    def initialize(observations:, window_type:, clearance: {})
      @observations = observations
      @window_type = window_type.to_s
      @clearance = clearance.to_h.stringify_keys
    end

    def call
      validate!
      valid = observations.select { |row| row["status"] == "valid" }
      minimum = newly_selling? ? NEWLY_SELLING_MIN_WEEKS : STANDARD_MIN_WEEKS
      return insufficient_result(valid.size, minimum) if valid.size < minimum

      metrics = calculated_metrics(valid)
      stage, event = classify(valid, metrics)
      metrics.merge(
        "diagnosed_stage" => stage,
        "recommended_event" => event,
        "effective_weeks" => valid.size,
        "minimum_effective_weeks" => minimum,
        "window_type" => window_type
      )
    end

    private

    attr_reader :observations, :window_type, :clearance

    def validate!
      raise ArgumentError, "observations must be a non-empty array" unless observations.is_a?(Array) && observations.any?
      raise ArgumentError, "window_type must be standard or newly_selling" unless window_type.in?(%w[standard newly_selling])

      @observations = observations.map do |row|
        raise ArgumentError, "each observation must be an object" unless row.respond_to?(:stringify_keys)

        normalized = row.stringify_keys
        raise ArgumentError, "observation status is invalid" unless normalized["status"].in?(%w[valid censored_week inventory_unknown])
        normalized
      end
    end

    def newly_selling?
      window_type == "newly_selling"
    end

    def insufficient_result(effective_weeks, minimum)
      {
        "diagnosed_stage" => nil,
        "reason" => "insufficient_effective_weeks",
        "effective_weeks" => effective_weeks,
        "minimum_effective_weeks" => minimum,
        "window_type" => window_type,
        "recommended_event" => nil
      }
    end

    def calculated_metrics(valid)
      sales = numeric_series(valid, "net_sales")
      profit = numeric_series(valid, "after_tax")
      annual_returns = numeric_series(valid, "annualized_return_pct", optional: true)
      sales_slope = normalized_slope(sales)
      profit_slope = normalized_slope(profit)
      return_slope = normalized_slope(annual_returns)
      scale = newly_selling? ? 15.0 : 10.0

      {
        "net_sales_slope_pct_per_week" => rounded(sales_slope),
        "after_tax_slope_pct_per_week" => rounded(profit_slope),
        "annualized_return_slope_pct_per_week" => rounded(return_slope),
        "g" => rounded(0.6 * bounded(sales_slope, scale) + 0.4 * bounded(profit_slope, scale)),
        "q" => rounded(quality_score(valid)),
        "c" => annual_returns.empty? ? nil : rounded(50.0 + 50.0 * Math.tanh(median(annual_returns) / 100.0)),
        "c_trend" => return_slope.nil? ? nil : rounded(100.0 * Math.tanh(return_slope / 10.0)),
        "annualized_return_pct_median" => annual_returns.empty? ? nil : rounded(median(annual_returns))
      }
    end

    def classify(valid, metrics)
      if clearance_met?(valid)
        return [ "CLR", { "event_type" => "clearance_recommendation", "severity" => "red" } ]
      end

      healthy_growth = metrics["g"] >= 35 && metrics["q"] >= 55 && metrics["c"]&.>=(45) && metrics["c_trend"].to_f > -35
      return [ "GRW", { "event_type" => "stage_classification_updated", "severity" => "yellow" } ] if healthy_growth

      severity = metrics["q"] < 55 || metrics["c"].to_f < 35 || valid.count { |row| decimal(row["after_tax"]) <= 0 } >= valid.size / 2.0 ? "red" : "yellow"
      event_type = severity == "red" ? "mat_quality_risk" : "mat_quality_warning"
      [ "MAT", { "event_type" => event_type, "severity" => severity } ]
    end

    def clearance_met?(valid)
      sales = valid.map { |row| decimal(row["net_sales"]) }
      return false if sales.size < 6

      prior = median(sales.first(sales.size - 2))
      recent = median(sales.last(2))
      decline = prior.positive? && recent <= prior * 0.4
      turnover = decimal(clearance["turnover_days"], optional: true)
      turnover_with_incoming = decimal(clearance["turnover_days_with_incoming"], optional: true)
      inventory_pressure = turnover&.>=(180) || turnover_with_incoming&.>=(240)
      deterioration = clearance["profit_or_ad_deterioration"] == true
      no_recovery = clearance["sustained_recovery"] != true
      decline && inventory_pressure && deterioration && no_recovery
    end

    def quality_score(valid)
      total = valid.size.to_f
      profitable = valid.count { |row| decimal(row["after_tax"]) > 0 } / total * 100
      positive_unit = valid.count { |row| decimal(row["average_profit_per_order"], optional: true)&.positive? } / total * 100
      healthy_ads = valid.count do |row|
        ratio = decimal(row["ad_ratio_pct"], optional: true)
        ratio && HEALTHY_AD_RATIO_RANGE.cover?(ratio)
      end / total * 100
      positive_margin = valid.count { |row| decimal(row["margin_pct"], optional: true)&.positive? } / total * 100
      0.40 * profitable + 0.25 * positive_unit + 0.20 * healthy_ads + 0.15 * positive_margin
    end

    def numeric_series(rows, key, optional: false)
      rows.filter_map { |row| decimal(row[key], optional:) }
    end

    def normalized_slope(values)
      return nil if values.size < 2

      center = median(values)
      return nil if center.abs < 0.000001

      theil_sen(values) / center.abs * 100.0
    end

    def theil_sen(values)
      slopes = values.each_index.flat_map do |left|
        ((left + 1)...values.size).map { |right| (values[right] - values[left]) / (right - left).to_f }
      end
      median(slopes)
    end

    def median(values)
      sorted = values.sort
      midpoint = sorted.size / 2
      sorted.size.odd? ? sorted[midpoint] : (sorted[midpoint - 1] + sorted[midpoint]) / 2.0
    end

    def bounded(value, scale)
      value.nil? ? 0.0 : 100.0 * Math.tanh(value / scale)
    end

    def decimal(value, optional: false)
      return nil if optional && value.nil?
      Float(value)
    rescue ArgumentError, TypeError
      raise ArgumentError, "observation contains an invalid numeric value"
    end

    def rounded(value)
      value&.round(1)
    end
  end
end
