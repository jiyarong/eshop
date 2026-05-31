module RawWb
  class Supply < ApplicationRecord
    self.table_name = 'raw_wb_supplies'

    belongs_to :account, class_name: 'RawWb::SellerAccount'

    has_many :supply_orders, class_name: 'RawWb::SupplyOrder', foreign_key: :supply_id, dependent: :destroy
    has_many :orders,        through: :supply_orders
    has_many :supply_boxes,  class_name: 'RawWb::SupplyBox',   foreign_key: :supply_id, dependent: :destroy
  end
end
