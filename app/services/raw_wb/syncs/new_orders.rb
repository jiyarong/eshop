module RawWb
  module Syncs
    module NewOrders
      # GET /api/v3/orders/new — marketplace-api (currently pending new orders)
      def sync_new_orders
        synced_at = Time.current
        data      = @client.get(:marketplace, '/api/v3/orders/new')
        orders    = Array(data['orders'] || data)
        return 0 if orders.empty?

        rows = orders.map { |o| build_order(o, synced_at) }
        RawWb::Order.upsert_all(rows, unique_by: :wb_order_id, update_only: order_update_cols, record_timestamps: false)
        rows.size
      end
    end
  end
end
