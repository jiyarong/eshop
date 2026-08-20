module SalesFunnelReports
  class EndingInventoryQuery
    STORE_STOCK_TYPES = %w[fbo fbw fbs].freeze

    def self.by_sku(sku_ids:, store_id:, on_date:)
      Ec::Snapshot
        .of_type(Ec::InventorySnapshot.snapshot_type)
        .where(snapshot_date: on_date, sku_id: sku_ids)
        .each_with_object({}) do |snapshot, result|
          overview = snapshot.data.fetch(:overview, {})
          levels = Array(snapshot.data.dig(:distribution, :levels)).select do |level|
            level = level.with_indifferent_access
            level[:store_id].to_i == store_id && level[:fulfillment_type].to_s.in?(STORE_STOCK_TYPES)
          end
          result[snapshot.sku_id] = {
            total_ending_inventory: overview[:book_stock]&.to_i,
            store_ending_inventory: levels.sum { |level| level[:quantity].to_i }
          }
        end
    end
  end
end
