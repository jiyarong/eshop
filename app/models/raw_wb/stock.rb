module RawWb
  class Stock < ApplicationRecord
    self.table_name = 'raw_wb_stocks'

    belongs_to :account,   class_name: 'RawWb::SellerAccount'
    belongs_to :warehouse, class_name: 'RawWb::Warehouse'
    belongs_to :sku,       class_name: 'RawWb::ProductSku', optional: true
  end
end
