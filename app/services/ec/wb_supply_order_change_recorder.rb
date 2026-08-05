module Ec
  class WbSupplyOrderChangeRecorder
    STATUS_NAMES = {
      1 => "not_planned",
      2 => "planned",
      3 => "unloading_allowed",
      4 => "accepting",
      5 => "accepted",
      6 => "unloaded_at_gate"
    }.freeze

    class << self
      def record(account:, changes:, operated_at: Time.current)
        return if changes.empty?

        sku_products = sku_products_by_nm_id(account, changes)
        changes.each do |change|
          supply = change.fetch(:supply)
          items = supply_items(account, supply)
          items.each do |item|
            sku_product = sku_products[item.nm_id.to_s]
            unless sku_product
              log_unmatched(account, supply, item.nm_id)
              next
            end

            record_change(
              sku_product: sku_product,
              supply: supply,
              items: items,
              item: item,
              previous_status_id: change[:previous_status_id],
              operated_at: updated_at(supply) || operated_at
            )
          end
        end
      end

      private

      def sku_products_by_nm_id(account, changes)
        nm_ids = changes.flat_map do |change|
          supply_items(account, change.fetch(:supply)).map(&:nm_id)
        end.map(&:to_s).uniq
        return {} if nm_ids.empty?

        store_ids = Ec::Store.where(platform: "wb", wb_raw_account_id: account.id).select(:id)
        Ec::SkuProduct
          .includes(:sku, :store, operator_role_assignments: :user)
          .where(store_id: store_ids, platform: "wb", product_id: nm_ids)
          .order(:id)
          .each_with_object({}) do |sku_product, result|
            result[sku_product.product_id.to_s] ||= sku_product
          end
      end

      def supply_items(account, supply)
        ids = [supply['supplyID'], supply['id'], supply['preorderID']].compact.map(&:to_s).uniq
        RawWb::SupplyItem.where(account_id: account.id, wb_supply_id: ids).order(:nm_id)
      end

      def record_change(sku_product:, supply:, items:, item:, previous_status_id:, operated_at:)
        current_status_id = supply['statusID'].to_i
        Ec::ListingChangeRecorder.record(
          sku_product: sku_product,
          operation_type: "supply_order",
          before: { supply_order_status: status_name(previous_status_id) },
          after: { supply_order_status: status_name(current_status_id) },
          operated_at: operated_at,
          metadata: {
            supply_order: {
              account_id: item.account_id,
              id: (supply['supplyID'].presence || supply['id'].presence)&.to_s,
              preorder_id: supply['preorderID']&.to_s,
              status_id_from: previous_status_id,
              status_id_to: current_status_id,
              nm_id: item.nm_id,
              sku_quantity: item.quantity,
              accepted_quantity: item.accepted_qty,
              remaining_quantity: [item.quantity - item.accepted_qty, 0].max,
              sku_count: items.size,
              total_quantity: items.sum(&:quantity),
              total_accepted_quantity: items.sum(&:accepted_qty),
              items: items.map do |supply_item|
                {
                  nm_id: supply_item.nm_id,
                  quantity: supply_item.quantity,
                  accepted_quantity: supply_item.accepted_qty
                }
              end,
              box_type_id: supply['boxTypeID'],
              is_box_on_pallet: supply['isBoxOnPallet'],
              created_at: supply['createDate'],
              supply_date: supply['supplyDate'],
              fact_date: supply['factDate'],
              state_updated_at: supply['updatedDate']
            }
          }
        )
      end

      def status_name(status_id)
        STATUS_NAMES[status_id.to_i] || "unknown"
      end

      def updated_at(supply)
        Time.zone.parse(supply['updatedDate']) if supply['updatedDate'].present?
      rescue ArgumentError
        nil
      end

      def log_unmatched(account, supply, nm_id)
        Rails.logger.warn(
          "[WbSupplyOrderChange] account=#{account.id} supply=#{supply['supplyID'] || supply['preorderID']} " \
          "nm_id=#{nm_id} has no Ec::SkuProduct binding"
        )
      end
    end
  end
end
