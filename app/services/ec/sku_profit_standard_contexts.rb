module Ec
  class SkuProfitStandardContexts
    IDENTITY_KEYS = %w[platform market delivery_mode warehouse_region company_type].freeze
    CONFIG_PATH = Rails.root.join("config/sku_profit_scenarios.yml")
    SCENARIOS = YAML.load_file(CONFIG_PATH).fetch("scenarios").map do |row|
      row.stringify_keys.merge("warehouse_region" => row["warehouse_region"] || "main").slice(*IDENTITY_KEYS).transform_values(&:to_s).freeze
    end.freeze
    ACTUALS_PENDING = YAML.load_file(CONFIG_PATH).fetch("scenarios").each_with_object({}) do |row, pending|
      kinds = Array(row["actuals_pending"]).map(&:to_s)
      next if kinds.empty?

      identity = row.stringify_keys.merge("warehouse_region" => row["warehouse_region"] || "main")
      pending[IDENTITY_KEYS.map { |key| identity[key].to_s }.join("|")] = kinds.freeze
    end.freeze
    SCENARIO_INDEX = SCENARIOS.each_with_index.to_h.freeze
    DEFAULT_WAREHOUSE_REGION = "main".freeze

    # "wb|ru|fbo|main|general": one string per scenario, for hashes, DOM ids and URLs.
    def self.key_for(attributes)
      IDENTITY_KEYS.map do |key|
        value = attributes[key] || attributes[key.to_sym]
        value = DEFAULT_WAREHOUSE_REGION if key == "warehouse_region" && value.blank?
        value.to_s.downcase
      end.join("|")
    end

    # The actual-data kinds ("storage", "advertising") that are still platform-wide for a scenario.
    def self.actuals_pending(attributes)
      ACTUALS_PENDING.fetch(key_for(attributes), [])
    end

    def self.actuals_split?(attributes)
      actuals_pending(attributes).empty?
    end

    def self.scenario_keys
      SCENARIOS.map { |attributes| key_for(attributes) }
    end

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
