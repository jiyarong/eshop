module Ec
  class SkuBatchActionRecorder
    class << self
      def record(batch)
        return unless batch.normal? && batch.purchased_quantity.to_i.positive?

        sku = batch.sku
        sku_product = sku.sku_products.includes(:store).order(:id).first
        operator = Current.user || sku.operator || fallback_operator
        return unless sku_product && operator

        Ec::OperationAction.transaction do
          action = Ec::OperationAction.create!(
            operation_type: "supply_order",
            operated_by_user: operator,
            operated_at: batch.created_at || Time.current,
            sku_product: sku_product,
            sku: sku,
            store: sku_product.store,
            diff_result: diff_result(batch, sku_product),
            record_by_system: true
          )
          Ec::OperationActionPlanMatcher.call(action)
          action
        end
      end

      private

      def diff_result(batch, sku_product)
        {
          "platform" => sku_product.platform,
          "fields" => {
            "batch_code" => { "from" => nil, "to" => batch.batch_code },
            "purchased_quantity" => { "from" => "0", "to" => batch.purchased_quantity.to_s }
          },
          "sku_batch" => {
            "id" => batch.id,
            "batch_code" => batch.batch_code,
            "status" => batch.status,
            "purchase_date" => batch.purchase_date&.iso8601,
            "expected_arrival_on" => batch.expected_arrival_on&.iso8601
          }
        }
      end

      def fallback_operator
        User.where(active: true)
          .joins(:roles)
          .where(roles: { code: "super_admin" })
          .order(:id)
          .first
      end
    end
  end
end
