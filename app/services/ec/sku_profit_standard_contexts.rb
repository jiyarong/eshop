module Ec
  class SkuProfitStandardContexts
    IDENTITY_KEYS = %w[platform market delivery_mode warehouse_region company_type].freeze
    SCENARIOS = [
      { "platform" => "wb", "market" => "ru", "delivery_mode" => "fbo", "warehouse_region" => "main", "company_type" => "general" },
      { "platform" => "wb", "market" => "ru", "delivery_mode" => "fbs", "warehouse_region" => "main", "company_type" => "general" },
      { "platform" => "wb", "market" => "ru", "delivery_mode" => "fbo", "warehouse_region" => "main", "company_type" => "small" },
      { "platform" => "wb", "market" => "ru", "delivery_mode" => "fbs", "warehouse_region" => "main", "company_type" => "small" },
      { "platform" => "ozon", "market" => "ru", "delivery_mode" => "fbo", "warehouse_region" => "main", "company_type" => "general" },
      { "platform" => "ozon", "market" => "by", "delivery_mode" => "fbo", "warehouse_region" => "main", "company_type" => "general" }
    ].map(&:freeze).freeze
    SCENARIO_INDEX = SCENARIOS.each_with_index.to_h.freeze

    def self.build_missing(version, sku: version.sku, effective_on: version.effective_from || Date.current)
      SCENARIOS.filter_map do |attributes|
        next if version.contexts.any? { |context| identity_for(context) == attributes }

        context = version.contexts.build(attributes)
        context.assign_input_values(
          SkuProfitCalculator.initial_inputs(
            sku:,
            platform: attributes.fetch("platform"),
            parameter_context: attributes,
            effective_on:
          )
        )
        context
      end
    end

    def self.sort(contexts)
      contexts.sort_by do |context|
        identity = identity_for(context)
        [
          SCENARIO_INDEX.fetch(identity, SCENARIOS.size),
          *IDENTITY_KEYS.map { |key| identity[key].to_s },
          context.id.to_i
        ]
      end
    end

    def self.identity_for(context)
      context.attributes.slice(*IDENTITY_KEYS).transform_values { |value| value.to_s.downcase.presence }
    end
    private_class_method :identity_for
  end
end
