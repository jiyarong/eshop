module RawWb
  module Syncs
    module Warehouses
      # GET /api/v3/warehouses — marketplace-api (seller warehouses)
      def sync_warehouses
        data = @client.get(:marketplace, '/api/v3/warehouses')
        rows = Array(data).filter_map do |r|
          next if r['id'].blank?
          { account_id: @account.id, wb_warehouse_id: r['id'].to_i, name: r['name'].to_s, is_active: true }
        end
        return 0 if rows.empty?

        rows.each do |row|
          wh = RawWb::Warehouse.find_or_initialize_by(wb_warehouse_id: row[:wb_warehouse_id])
          wh.account_id = @account.id
          wh.name       = row[:name]
          wh.is_active  = row[:is_active]
          wh.save!
        end
        rows.size
      end
    end
  end
end
