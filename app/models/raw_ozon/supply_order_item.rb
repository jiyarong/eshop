module RawOzon
  class SupplyOrderItem < ApplicationRecord
    self.table_name = "raw_ozon_supply_order_items"

    belongs_to :supply_order, class_name: "RawOzon::SupplyOrder", inverse_of: :supply_order_items
  end
end
