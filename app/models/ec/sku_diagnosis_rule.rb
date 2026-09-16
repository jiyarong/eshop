module Ec
  class SkuDiagnosisRule < ApplicationRecord
    self.table_name = "ec_sku_diagnosis_rules"

    SCHEDULED_FREQUENCIES = %w[daily weekly].freeze
    FREQUENCIES = (SCHEDULED_FREQUENCIES + %w[manual]).freeze
    CONTEXT_KEYS = %w[
      base inventory lifecycle profit sales_funnel advertise_per_week
      ec_orders_full_period supply_orders_full_period operation_actions_full_period
      warehouse_recommendation search_terms_per_week listing_content
    ].freeze

    after_initialize :default_context_keys, if: :new_record?

    validates :name, :prompt, presence: true
    validates :frequency, inclusion: { in: FREQUENCIES }
    validate :context_keys_are_supported

    scope :enabled_for, ->(date) do
      frequencies = date.monday? ? SCHEDULED_FREQUENCIES : [ "daily" ]
      where(enabled: true, frequency: frequencies)
    end

    def context_keys
      configured = configuration.is_a?(Hash) ? configuration["context_keys"] || configuration[:context_keys] : nil
      Array(configured).map(&:to_s) & CONTEXT_KEYS
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

    private

    def context_keys_are_supported
      configured = configuration.is_a?(Hash) ? configuration["context_keys"] || configuration[:context_keys] : nil
      invalid = Array(configured).map(&:to_s) - CONTEXT_KEYS
      errors.add(:configuration, "contains unsupported context keys: #{invalid.join(', ')}") if invalid.any?
      errors.add(:configuration, :blank) if Array(configured).empty?
    end

    def normalize_event_types(value)
      Array(value).flat_map { |item| item.to_s.lines }.map(&:strip).reject(&:blank?).uniq
    end

    def default_context_keys
      return unless configuration.blank? || (configuration["context_keys"].nil? && configuration[:context_keys].nil?)

      self.configuration = configuration.to_h.merge("context_keys" => CONTEXT_KEYS)
    end
  end
end
