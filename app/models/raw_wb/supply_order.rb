module RawWb
  class SupplyOrder < ApplicationRecord
    self.table_name = 'raw_wb_supply_orders'

    belongs_to :supply, class_name: 'RawWb::Supply'
    belongs_to :order,  class_name: 'RawWb::Order'
  end
end
