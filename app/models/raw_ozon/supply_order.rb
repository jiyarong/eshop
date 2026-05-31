module RawOzon
  class SupplyOrder < ApplicationRecord
    self.table_name = 'raw_ozon_supply_orders'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
