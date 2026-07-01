module Ec
  module Auditable
    extend ActiveSupport::Concern

    included do
      after_create_commit { record_operation_log("create", previous_changes) }
      after_update_commit { record_operation_log("update", previous_changes) }
      after_destroy_commit { record_operation_log("destroy", attributes.transform_values { |value| [value, nil] }) }
    end

    private

    def record_operation_log(action, raw_changes)
      changeset = audit_changeset(raw_changes)
      return if changeset.empty?

      Ec::OperationLog.create!(
        user: Current.user,
        record_type: self.class.name,
        record_id: id,
        action: action,
        changeset: changeset
      )
    end

    def audit_changeset(raw_changes)
      audit_attribute_names.filter_map do |attribute_name|
        next unless raw_changes.key?(attribute_name)

        from, to = raw_changes.fetch(attribute_name)
        next if audit_json_value(attribute_name, from) == audit_json_value(attribute_name, to)

        {
          field: attribute_name,
          from: audit_json_value(attribute_name, from),
          to: audit_json_value(attribute_name, to)
        }
      end
    end

    def audit_attribute_names
      Ec::AuditConfig.attributes_for(self.class)
    end

    def audit_json_value(attribute_name, value)
      type = self.class.type_for_attribute(attribute_name)
      serialized = type.serialize(value)

      case serialized
      when BigDecimal
        serialized.to_s("F")
      when Date, Time, ActiveSupport::TimeWithZone
        serialized.iso8601
      else
        serialized
      end
    end
  end
end
