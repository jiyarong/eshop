module Ec
  class OperationActionDiffFormatter
    CHANGE_KEYS = %w[from to added removed primary_from primary_to].freeze

    def self.summary(diff_result, operation_type:)
      new(diff_result, operation_type:).summary
    end

    def initialize(diff_result, operation_type:)
      @diff_result = diff_result.to_h.deep_stringify_keys
      @operation_type = operation_type.to_s
    end

    def summary
      fields = @diff_result.fetch("fields", {})
      fields = { "note" => { "to" => @diff_result["note"] } } if fields.blank? && @operation_type == "manual_note"

      entries(fields).map do |path, change|
        label = path.map { |part| field_label(part) }.join(" / ")
        values = %w[from to added removed primary_from primary_to].filter_map do |key|
          next unless change.key?(key)

          "#{change_label(key)}: #{format_value(change[key])}"
        end
        values = [format_value(change["to"])] if values.blank? && change.key?("to")
        [label, values.join("; ")].reject(&:blank?).join(": ")
      end
    end

    private

    def entries(fields, path = [])
      fields.flat_map do |field, value|
        current_path = path + [field.to_s]
        if value.is_a?(Hash) && (value.keys.map(&:to_s) & CHANGE_KEYS).any?
          [[current_path, value.deep_stringify_keys]]
        elsif value.is_a?(Hash)
          entries(value, current_path)
        else
          [[current_path, { "to" => value }]]
        end
      end
    end

    def field_label(field)
      key = "erp.operation_actions.diff_fields.#{field}"
      I18n.exists?(key) ? I18n.t(key) : field.to_s
    end

    def change_label(change)
      I18n.t("erp.operation_actions.change_types.#{change}", default: change.to_s.humanize)
    end

    def format_value(value)
      return I18n.t("erp.operation_actions.values.empty") if value.nil?
      return value.to_s unless value.is_a?(Hash) || value.is_a?(Array)

      JSON.generate(value)
    end
  end
end
