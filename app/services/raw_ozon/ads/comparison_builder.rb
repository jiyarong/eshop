module RawOzon
  module Ads
    class ComparisonBuilder
      NEGATIVE_METRICS = %i[spend drr avg_cpc cost_per_order].freeze

      def summary(current, previous, metrics:)
        metrics.index_with { |metric| metric_comparison(current[metric], previous[metric], metric) }
      end

      def rows(current_rows, previous_rows, key_builder:, metrics:)
        previous_by_key = previous_rows.index_by { |row| key_builder.call(row) }
        current_rows.each_with_object({}) do |row, result|
          key = key_builder.call(row)
          previous = previous_by_key[key]
          result[key] = metrics.index_with do |metric|
            metric_comparison(row[metric], previous&.dig(metric), metric)
          end
        end
      end

      private

      def metric_comparison(current, previous, metric)
        return none(current) if current.nil? || previous.nil?

        current_value = current.to_d
        previous_value = previous.to_d
        return flat(current, previous) if current_value.zero? && previous_value.zero?

        delta = current_value - previous_value
        trend = delta.positive? ? "up" : delta.negative? ? "down" : "flat"
        delta_pct = previous_value.zero? ? nil : (delta / previous_value * 100).round(2)
        semantic = if trend == "flat"
          "neutral"
        elsif NEGATIVE_METRICS.include?(metric.to_sym)
          trend == "up" ? "negative" : "positive"
        else
          trend == "up" ? "positive" : "negative"
        end
        { current: current, previous: previous, delta_value: delta.round(2), delta_pct: delta_pct,
          trend: trend, semantic: semantic }
      end

      def none(current)
        { current: current, previous: nil, delta_value: nil, delta_pct: nil, trend: "none", semantic: "none" }
      end

      def flat(current, previous)
        { current: current, previous: previous, delta_value: 0, delta_pct: 0, trend: "flat", semantic: "neutral" }
      end
    end
  end
end
