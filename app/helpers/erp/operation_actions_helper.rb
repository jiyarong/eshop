module Erp
  module OperationActionsHelper
    CHANGE_KEYS = %w[from to added removed primary_from primary_to].freeze

    def operation_action_type_options
      Ec::OperationAction::OPERATION_TYPES.map do |operation_type|
        [t("erp.operation_actions.operation_types.#{operation_type}"), operation_type]
      end
    end

    def operation_action_platform_options
      Erp::OperationActionsController::PLATFORMS.map do |platform|
        [t("erp.operation_actions.platforms.#{platform}"), platform]
      end
    end

    def operation_action_field_label(field)
      key = "erp.operation_actions.diff_fields.#{field}"
      I18n.exists?(key) ? t(key) : field.to_s
    end

    def operation_action_diff_entries(fields, path = [])
      fields.flat_map do |field, value|
        current_path = path + [field.to_s]
        if value.is_a?(Hash) && (value.keys.map(&:to_s) & CHANGE_KEYS).any?
          [[current_path, value]]
        elsif value.is_a?(Hash)
          operation_action_diff_entries(value, current_path)
        else
          [[current_path, { "to" => value }]]
        end
      end
    end

    def operation_action_diff_path(path)
      [operation_action_field_label(path.first), *path.drop(1)].join(" / ")
    end

    def operation_action_diff_value(value)
      return t("erp.operation_actions.values.empty") if value.nil?
      return value.to_s unless value.is_a?(Hash) || value.is_a?(Array)

      JSON.pretty_generate(value)
    end

    def operation_action_advertisement(action)
      advertisement = action.diff_result["advertisement"]
      return unless advertisement.is_a?(Hash)

      name = advertisement["name"].presence
      id = advertisement["id"].presence
      return if name.blank? && id.blank?

      { name:, id: }
    end
  end
end
