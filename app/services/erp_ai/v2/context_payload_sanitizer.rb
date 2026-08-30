module ErpAI
  module V2
    class ContextPayloadSanitizer
      OMITTED_KEYS = %w[source_payload item_payload].freeze

      def self.call(value, normalize_numbers: false)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), result|
            next if omitted_key?(key)

            result[key] = call(item, normalize_numbers: normalize_numbers)
          end
        when Array
          value.map { |item| call(item, normalize_numbers: normalize_numbers) }
        when BigDecimal
          normalize_numbers ? normalized_decimal(value) : value
        else
          value
        end
      end

      def self.normalized_decimal(value)
        decimal = value.to_d
        decimal.frac.zero? ? decimal.to_i : decimal.to_f
      end

      private_class_method :normalized_decimal

      def self.omitted_key?(key)
        normalized = key.to_s
        OMITTED_KEYS.include?(normalized) || normalized.end_with?("raw_json", "raw_payload")
      end

      private_class_method :omitted_key?
    end
  end
end
