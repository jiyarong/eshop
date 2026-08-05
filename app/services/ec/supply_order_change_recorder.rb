module Ec
  class SupplyOrderChangeRecorder
    class << self
      def record(account:, changes:, operated_at: Time.current)
        return if changes.empty?

        sku_products = sku_products_by_platform_sku(account, changes)
        changes.each do |change|
          row = change.fetch(:row)
          items = row[:items].presence || change[:previous_items].to_h
          items.each do |platform_sku_id, quantity|
            sku_product = sku_products[platform_sku_id.to_s]
            unless sku_product
              log_unmatched(account, row, platform_sku_id)
              next
            end

            record_change(
              sku_product: sku_product,
              row: row,
              items: items,
              platform_sku_id: platform_sku_id,
              quantity: quantity,
              previous_status: change[:previous_status],
              operated_at: state_updated_at(row) || operated_at
            )
          end
        end
      end

      private

      def sku_products_by_platform_sku(account, changes)
        platform_sku_ids = changes.flat_map do |change|
          (change.dig(:row, :items).presence || change[:previous_items].to_h).keys
        end.map(&:to_s).uniq
        return {} if platform_sku_ids.empty?

        store_ids = Ec::Store.where(platform: "ozon", ozon_raw_account_id: account.id).select(:id)
        Ec::SkuProduct
          .includes(:sku, :store, operator_role_assignments: :user)
          .where(store_id: store_ids, platform: "ozon", platform_sku_id: platform_sku_ids)
          .order(:id)
          .each_with_object({}) do |sku_product, result|
            result[sku_product.platform_sku_id.to_s] ||= sku_product
          end
      end

      def record_change(sku_product:, row:, items:, platform_sku_id:, quantity:, previous_status:, operated_at:)
        raw_json = row[:raw_json].to_h
        Ec::ListingChangeRecorder.record(
          sku_product: sku_product,
          operation_type: "supply_order",
          before: { supply_order_status: previous_status },
          after: { supply_order_status: row[:status] },
          operated_at: operated_at,
          metadata: {
            supply_order: {
              account_id: row[:account_id],
              id: row[:supply_order_id],
              number: raw_json["order_number"],
              platform_sku_id: platform_sku_id.to_s,
              sku_quantity: quantity.to_i,
              sku_count: items.size,
              total_quantity: items.values.sum(&:to_i),
              items: items,
              timeslot: row[:timeslot],
              drop_off_warehouse: raw_json["drop_off_warehouse"],
              created_at: row[:created_at],
              state_updated_at: raw_json["state_updated_date"]
            }
          }
        )
      end

      def state_updated_at(row)
        value = row.dig(:raw_json, "state_updated_date")
        Time.zone.parse(value) if value.present?
      rescue ArgumentError
        nil
      end

      def log_unmatched(account, row, platform_sku_id)
        Rails.logger.warn(
          "[OzonSupplyOrderChange] account=#{account.id} order=#{row[:supply_order_id]} " \
          "platform_sku_id=#{platform_sku_id} has no Ec::SkuProduct binding"
        )
      end
    end
  end
end
