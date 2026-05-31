module RawWb
  class OrderStatusHistory < ApplicationRecord
    self.table_name = 'raw_wb_order_status_histories'

    belongs_to :order, class_name: 'RawWb::Order'
  end
end
