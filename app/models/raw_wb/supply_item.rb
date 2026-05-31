module RawWb
  class SupplyItem < ApplicationRecord
    self.table_name = 'raw_wb_supply_items'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
  end
end
