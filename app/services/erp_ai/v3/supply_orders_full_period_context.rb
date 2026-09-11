module ErpAI
  module V3
    class SupplyOrdersFullPeriodContext
      WB_COLUMNS = SupplyOrderReports::ReportQuery::WB_COLUMNS
      OZON_COLUMNS = SupplyOrderReports::ReportQuery::OZON_COLUMNS
      CONTEXT_FIELDS = %i[platform store_id store_name].freeze

      def initialize(sku:, period_from:, period_to:, time_zone:)
        @sku = sku
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @time_zone = time_zone
      end

      def call
        sku.sku_products.includes(:store).group_by { |product| [product.platform, product.store] }.flat_map do |(platform, store), products|
          case platform
          when "wb" then wb_rows(store, products)
          when "ozon" then ozon_rows(store, products)
          else []
          end
        end.sort_by { |row| [-(row[:created_at]&.to_i || 0), row.fetch(:platform), row.fetch(:supply_id).to_s, row.fetch(:platform_item_id).to_s] }
      end

      private

      attr_reader :sku, :period_from, :period_to, :time_zone

      def wb_rows(store, products)
        account_id = store.wb_raw_account_id
        product_ids = products.filter_map { |product| positive_integer(product.product_id) }.uniq
        return [] if account_id.blank? || product_ids.empty?

        supplies = RawWb::Supply.where(account_id: account_id, supply_created_at: user_time_range).to_a
        supplies_by_id = supplies.each_with_object({}) do |supply, index|
          index[supply.wb_supply_id.to_s] = supply if supply.wb_supply_id.present?
          index[supply.preorder_id.to_s] ||= supply if supply.preorder_id.present?
        end
        return [] if supplies_by_id.empty?

        RawWb::SupplyItem.where(account_id: account_id, nm_id: product_ids, wb_supply_id: supplies_by_id.keys).filter_map do |item|
          supply = supplies_by_id[item.wb_supply_id.to_s]
          next unless supply

          row_with_context(store, "wb", {
            supply_id: supply.wb_supply_id,
            preorder_id: supply.preorder_id,
            status: supply.status_id,
            platform_item_id: item.nm_id,
            sku_code: sku.sku_code,
            product_name: product_name,
            quantity: item.quantity,
            accepted_quantity: item.accepted_qty,
            remaining_quantity: [item.quantity.to_i - item.accepted_qty.to_i, 0].max,
            warehouse_name: supply.warehouse_name,
            actual_warehouse_name: supply.actual_warehouse_name,
            transit_warehouse_name: supply.transit_warehouse_name,
            created_at: supply.supply_created_at,
            scheduled_at: supply.supply_date,
            actual_at: supply.fact_date,
            packaging: supply.box_type_id,
            pallet: supply.is_box_on_pallet,
            acceptance_cost: supply.acceptance_cost,
            paid_acceptance_coefficient: supply.paid_acceptance_coefficient,
            storage_coefficient: supply.storage_coefficient,
            delivery_coefficient: supply.delivery_coefficient,
            supplier_assign_name: supply.supplier_assign_name,
            reject_reason: supply.reject_reason,
            supply_quantity: supply.detail_quantity,
            supply_accepted_quantity: supply.accepted_quantity,
            ready_for_sale_quantity: supply.ready_for_sale_quantity,
            unloading_quantity: supply.unloading_quantity,
            depersonalized_quantity: supply.depersonalized_quantity,
            can_show_quantity: supply.can_show_quantity,
            synced_at: item.synced_at
          }, WB_COLUMNS)
        end
      end

      def ozon_rows(store, products)
        account_id = store.ozon_raw_account_id
        platform_sku_ids = products.filter_map { |product| product.platform_sku_id.to_s.presence }.uniq
        return [] if account_id.blank? || platform_sku_ids.empty?

        cluster_names = RawOzon::WarehouseCluster
          .where(account_id: account_id)
          .where.not(macrolocal_cluster_id: nil)
          .where.not(cluster_name: nil)
          .pluck(:macrolocal_cluster_id, :cluster_name)
          .to_h

        RawOzon::SupplyOrder.includes(:supply_order_items).where(account_id: account_id, created_at: user_time_range).flat_map do |order|
          raw = order.raw_json || {}
          order.supply_order_items.filter_map do |item|
            next unless item.platform_sku_id.to_s.in?(platform_sku_ids)

            row_with_context(store, "ozon", {
              order_number: raw["order_number"],
              supply_id: item.ozon_supply_id,
              status: item.state.presence || order.status,
              platform_item_id: item.platform_sku_id.to_s,
              sku_code: sku.sku_code,
              product_name: product_name,
              quantity: item.quantity,
              destination_cluster: cluster_names[item.macrolocal_cluster_id.to_i],
              destination_warehouse: item.storage_warehouse_name,
              created_at: order.created_at,
              timeslot: order.timeslot,
              origin_warehouse: raw.dig("drop_off_warehouse", "name"),
              state_updated_at: raw["state_updated_date"],
              synced_at: item.synced_at
            }, OZON_COLUMNS)
          end
        end
      end

      def row_with_context(store, platform, values, columns)
        CONTEXT_FIELDS.index_with do |field|
          case field
          when :platform then platform
          when :store_id then store.id
          when :store_name then store.store_name
          end
        end.merge(columns.index_with { |field| values[field] })
      end

      def product_name
        sku.product_name
      end

      def user_time_range
        @user_time_range ||= time_zone.local(period_from.year, period_from.month, period_from.day).beginning_of_day..
          time_zone.local(period_to.year, period_to.month, period_to.day).end_of_day
      end

      def positive_integer(value)
        integer = value.to_i
        integer if integer.positive?
      end
    end
  end
end
