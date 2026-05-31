module Ec
  class InventorySnapshot < ApplicationRecord
    self.table_name = 'ec_inventory_snapshots'

    belongs_to :sku, class_name: 'Ec::Sku', foreign_key: :sku_code, primary_key: :sku_code
  end
end
