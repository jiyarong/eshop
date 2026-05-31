module RawWb
  class Order < ApplicationRecord
    self.table_name = 'raw_wb_orders'

    belongs_to :account,   class_name: 'RawWb::SellerAccount'
    belongs_to :warehouse, class_name: 'RawWb::Warehouse', optional: true

    has_many :order_metas,          class_name: 'RawWb::OrderMeta',         foreign_key: :order_id, dependent: :destroy
    has_many :order_status_histories, class_name: 'RawWb::OrderStatusHistory', foreign_key: :order_id, dependent: :destroy
    has_many :supply_orders,        class_name: 'RawWb::SupplyOrder',       foreign_key: :order_id, dependent: :destroy
    has_many :supplies,             through: :supply_orders
    has_many :return_claims,        class_name: 'RawWb::ReturnClaim',       foreign_key: :order_id
    has_one  :chat,                 class_name: 'RawWb::Chat',              foreign_key: :order_id
  end
end
