module RawWb
  class Warehouse < ApplicationRecord
    self.table_name = 'raw_wb_warehouses'

    belongs_to :account, class_name: 'RawWb::SellerAccount'

    has_many :stocks,         class_name: 'RawWb::Stock',        foreign_key: :warehouse_id, dependent: :destroy
    has_many :stock_histories, class_name: 'RawWb::StockHistory', foreign_key: :warehouse_id, dependent: :destroy
    has_many :orders,         class_name: 'RawWb::Order',        foreign_key: :warehouse_id
  end
end
