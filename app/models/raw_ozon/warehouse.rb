module RawOzon
  class Warehouse < ApplicationRecord
    self.table_name = 'raw_ozon_warehouses'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
