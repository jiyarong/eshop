module ErpAI
  module V2
    class ContextPayloadSanitizer
      OMITTED_KEYS = %w[source_payload item_payload].freeze

      def self.call(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), result|
            next if omitted_key?(key)

            result[key] = call(item)
          end
        when Array
          value.map { |item| call(item) }
        else
          value
        end
      end

      def self.omitted_key?(key)
        normalized = key.to_s
        OMITTED_KEYS.include?(normalized) || normalized.end_with?("raw_json", "raw_payload")
      end

      private_class_method :omitted_key?
    end
  end
end
