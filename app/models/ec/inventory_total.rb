module Ec
  class InventoryTotal < ApplicationRecord
    self.table_name = 'ec_inventory_totals'

    belongs_to :sku, class_name: 'Ec::Sku', foreign_key: :sku_code, primary_key: :sku_code

    # 白俄仓推算 = 总入库 − 总送仓 − FBS总计
    def blr_warehouse
      total_received - total_supply - total_fbs
    end

    # 总可售 = 白俄仓 + 所有平台当前库存
    def total_available
      blr_warehouse + total_stock
    end
  end
end
