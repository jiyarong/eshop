module RawOzon
  class SupplyOrder < ApplicationRecord
    self.table_name = 'raw_ozon_supply_orders'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
    has_many :supply_order_items,
      class_name: "RawOzon::SupplyOrderItem",
      inverse_of: :supply_order,
      dependent: :delete_all
  end
end
