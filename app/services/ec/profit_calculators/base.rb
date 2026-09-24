module Ec
  module ProfitCalculators
    class Base
      RATE_KEYS = %w[
        commission_rate acquiring_rate advertising_rate tax_rate sales_vat_rate
        return_rate logistics_tax_rate damage_rate
        ozon_warehouse_rate ozon_import_vat_cost_rate
      ].freeze

      def self.call(parameter_context:, inputs:) = new(parameter_context: parameter_context, inputs: inputs).call
      def initialize(parameter_context:, inputs:) = (@context, @inputs = parameter_context.stringify_keys, inputs.stringify_keys)
      private
      def decimal(key) = BigDecimal(@inputs[key].to_s)
      def present?(key) = @inputs[key].present?
      def numeric?(key) = @inputs[key].is_a?(Numeric) || BigDecimal(@inputs[key].to_s, exception: false).present?
      def missing(*keys) = keys.reject { |key| present?(key) }
      def optional_warnings(*keys) = keys.reject { |key| present?(key) }.map { |key| "#{key}_not_included" }
      def validation_errors(required:, dimensions: [])
        errors = missing(*required).map { |key| "missing_#{key}" }
        @inputs.each_key { |key| errors << "invalid_#{key}" if present?(key) && !numeric?(key) }
        errors << "exchange_rate_must_be_positive" if numeric?("exchange_rate_rub_cny") && decimal("exchange_rate_rub_cny") <= 0
        dimensions.each { |key| errors << "#{key}_must_be_non_negative" if numeric?(key) && decimal(key).negative? }
        RATE_KEYS.each do |key|
          errors << "#{key}_must_be_between_zero_and_one" if numeric?(key) && !decimal(key).between?(0, 1)
        end
        errors << "return_rate_must_be_less_than_one" if numeric?("return_rate") && decimal("return_rate") == 1
        errors.uniq
      end
      def result(revenue:, breakdown:, warnings:, intermediate: {})
        total = breakdown.values.sum
        profit = revenue - total
        { revenue_cny: revenue, cost_breakdown: breakdown, total_cost_cny: total, profit_cny: profit,
          margin: revenue.zero? ? 0.to_d : profit / revenue, intermediate: intermediate,
          warnings: warnings, formula_version: ProfitCalculator::FORMULA_VERSION }
      end
    end
  end
end
