module RawWb
  class OrderMeta < ApplicationRecord
    self.table_name = 'raw_wb_order_metas'

    belongs_to :order, class_name: 'RawWb::Order'
  end
end
