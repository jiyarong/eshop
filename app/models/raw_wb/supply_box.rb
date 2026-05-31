module RawWb
  class SupplyBox < ApplicationRecord
    self.table_name = 'raw_wb_supply_boxes'

    belongs_to :supply, class_name: 'RawWb::Supply'
  end
end
