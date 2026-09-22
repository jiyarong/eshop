module Ec
  class SkuDiagnosisRule < ApplicationRecord
    self.table_name = "ec_sku_diagnosis_rules"

    SCHEDULED_FREQUENCIES = %w[daily weekly].freeze
    FREQUENCIES = (SCHEDULED_FREQUENCIES + %w[manual]).freeze
    LISTING_CONTEXT_KEYS = %w[ozon_listing_content wb_listing_content].freeze
    LEGACY_LISTING_CONTEXT_KEYS = %w[listing_content product_attributes].freeze
    CONTEXT_KEYS = %w[
      base inventory lifecycle profit sales_funnel advertise_per_week
      ec_orders_full_period supply_orders_full_period operation_actions_full_period
      warehouse_recommendation search_terms_per_week ozon_listing_content wb_listing_content
    ].freeze
    SUPPORTED_CONTEXT_KEYS = (CONTEXT_KEYS + LEGACY_LISTING_CONTEXT_KEYS).freeze
    EXECUTION_CONDITION_DEFINITIONS = {
      "grade" => {
        values: Ec::SkuMarketingState::GRADES,
        value_for: ->(sku) { sku.current_marketing_state&.grade }
      },
      "stage" => {
        values: Ec::SkuMarketingState::STAGES,
        value_for: ->(sku) { sku.current_marketing_state&.stage }
      }
    }.freeze
    EXECUTION_CONDITION_VALUES = EXECUTION_CONDITION_DEFINITIONS.transform_values { |definition| definition.fetch(:values) }.freeze
    EXECUTION_CONDITION_KEYS = EXECUTION_CONDITION_VALUES.keys.freeze

    after_initialize :default_context_keys, if: :new_record?

    validates :name, :prompt, presence: true
    validates :frequency, inclusion: { in: FREQUENCIES }
    validate :context_keys_are_supported
    validate :execution_conditions_are_supported

    scope :enabled_for, ->(date) do
      frequencies = date.tuesday? ? SCHEDULED_FREQUENCIES : [ "daily" ]
      where(enabled: true, frequency: frequencies)
    end

    def context_keys
      configured = configuration.is_a?(Hash) ? configuration["context_keys"] || configuration[:context_keys] : nil
      normalize_context_keys(configured)
    end

    def context_keys=(value)
      self.configuration = configuration.to_h.merge("context_keys" => Array(value).map(&:to_s))
    end

    def allowed_event_types
      configured = configuration.is_a?(Hash) ? configuration["allowed_event_types"] || configuration[:allowed_event_types] : nil
      normalize_event_types(configured)
    end

    def allowed_event_types=(value)
      self.configuration = configuration.to_h.merge("allowed_event_types" => normalize_event_types(value))
    end

    def allowed_event_types_text
      allowed_event_types.join("\n")
    end

    def allowed_event_types_text=(value)
      self.allowed_event_types = value
    end

    def execution_conditions
      configured = configuration.is_a?(Hash) ? configuration["execution_conditions"] || configuration[:execution_conditions] : nil
      EXECUTION_CONDITION_KEYS.to_h do |key|
        values = configured.is_a?(Hash) ? configured[key] || configured[key.to_sym] : nil
        [ key, normalize_execution_condition_values(key, values) ]
      end
    end

    def execution_conditions=(value)
      normalized = EXECUTION_CONDITION_KEYS.to_h do |key|
        [ key, normalize_execution_condition_values(key, value.to_h[key] || value.to_h[key.to_sym]) ]
      end
      self.configuration = configuration.to_h.merge("execution_conditions" => normalized)
    end

    def applies_to_sku?(sku)
      execution_conditions.all? do |key, values|
        values.empty? || values.include?(execution_condition_value(key, sku))
      end
    end

    private

    def context_keys_are_supported
      configured = configuration.is_a?(Hash) ? configuration["context_keys"] || configuration[:context_keys] : nil
      invalid = Array(configured).map(&:to_s) - SUPPORTED_CONTEXT_KEYS
      errors.add(:configuration, "contains unsupported context keys: #{invalid.join(', ')}") if invalid.any?
      errors.add(:configuration, :blank) if Array(configured).empty?
    end

    def execution_conditions_are_supported
      configured = configuration.is_a?(Hash) ? configuration["execution_conditions"] || configuration[:execution_conditions] : nil
      return if configured.blank?

      unless configured.is_a?(Hash)
        errors.add(:configuration, "execution conditions must be a hash")
        return
      end

      invalid_keys = configured.keys.map(&:to_s) - EXECUTION_CONDITION_KEYS
      errors.add(:configuration, "contains unsupported execution condition keys: #{invalid_keys.join(', ')}") if invalid_keys.any?

      EXECUTION_CONDITION_KEYS.each do |key|
        values = configured[key] || configured[key.to_sym]
        invalid_values = normalize_execution_condition_values(key, values) - EXECUTION_CONDITION_VALUES.fetch(key)
        errors.add(:configuration, "contains unsupported #{key} values: #{invalid_values.join(', ')}") if invalid_values.any?
      end
    end

    def normalize_event_types(value)
      Array(value).flat_map { |item| item.to_s.lines }.map(&:strip).reject(&:blank?).uniq
    end

    def normalize_context_keys(value)
      keys = Array(value).map(&:to_s)
      if (keys & LEGACY_LISTING_CONTEXT_KEYS).any?
        keys = (keys - LEGACY_LISTING_CONTEXT_KEYS) + LISTING_CONTEXT_KEYS
      end
      keys.uniq & CONTEXT_KEYS
    end

    def normalize_execution_condition_values(key, value)
      Array(value).map { |item| normalize_execution_condition_value(key, item) }.reject(&:blank?).uniq
    end

    def normalize_execution_condition_value(key, value)
      normalized = value.to_s.strip
      key == "grade" ? normalized.upcase : normalized.downcase
    end

    def execution_condition_value(key, sku)
      EXECUTION_CONDITION_DEFINITIONS.fetch(key).fetch(:value_for).call(sku)
    end

    def default_context_keys
      return unless configuration.blank? || (configuration["context_keys"].nil? && configuration[:context_keys].nil?)

      self.configuration = configuration.to_h.merge("context_keys" => CONTEXT_KEYS)
    end
  end
end
