module Ec
  class ListingChangeRecorder
    IMAGE_FIELD = "images"

    class << self
      def record(sku_product:, operation_type:, before:, after:, operated_at: Time.current)
        fields = build_diff(normalize_hash(before), normalize_hash(after))
        return if fields.empty?

        operator, attribution = attributed_user(sku_product)
        return log_missing_operator(sku_product) unless operator

        Ec::OperationAction.create!(
          operation_type: operation_type,
          operated_by_user: operator,
          operated_at: operated_at,
          sku_product: sku_product,
          sku: sku_product.sku,
          store: sku_product.store,
          diff_result: {
            "platform" => sku_product.platform,
            "attribution" => attribution,
            "fields" => fields
          },
          record_by_system: true
        )
      end

      private

      def build_diff(before, after)
        (before.keys | after.keys).sort.each_with_object({}) do |field, result|
          old_value = before[field]
          new_value = after[field]
          next if old_value == new_value

          change = value_diff(field, old_value, new_value)
          result[field] = change if change.present?
        end
      end

      def value_diff(field, old_value, new_value)
        return image_diff(old_value, new_value) if field == IMAGE_FIELD
        return build_diff(old_value, new_value) if old_value.is_a?(Hash) && new_value.is_a?(Hash)
        return array_diff(old_value, new_value) if old_value.is_a?(Array) && new_value.is_a?(Array)

        { "from" => old_value, "to" => new_value }
      end

      def array_diff(old_value, new_value)
        added = new_value - old_value
        removed = old_value - new_value
        return if added.empty? && removed.empty?

        { "added" => added, "removed" => removed }
      end

      def image_diff(old_value, new_value)
        old_images = Array(old_value)
        new_images = Array(new_value)
        {
          "primary_from" => old_images.first,
          "primary_to" => new_images.first,
          "added" => new_images - old_images,
          "removed" => old_images - new_images
        }
      end

      def normalize_hash(value)
        value.to_h.each_with_object({}) do |(key, item), result|
          result[key.to_s] = normalize_value(item)
        end
      end

      def normalize_value(value)
        case value
        when Hash
          value.to_h.transform_keys(&:to_s).sort.to_h.transform_values { |item| normalize_value(item) }
        when Array
          value.map { |item| normalize_value(item) }
        when Numeric
          BigDecimal(value.to_s).to_s("F")
        else
          value
        end
      end

      def attributed_user(sku_product)
        operator = sku_product.operator_role_assignments.order(:id).first&.user
        return [operator, "assigned_operator"] if operator

        admin = User.where(active: true)
          .joins(:roles)
          .where(roles: { code: "super_admin" })
          .order(:id)
          .first
        [admin, "admin_fallback"]
      end

      def log_missing_operator(sku_product)
        Rails.logger.warn(
          "[ListingChangeRecorder] skipped action for Ec::SkuProduct##{sku_product.id}: no operator or active super_admin"
        )
        nil
      end
    end
  end
end
