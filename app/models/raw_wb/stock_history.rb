module RawWb
  class StockHistory < ApplicationRecord
    self.table_name = 'raw_wb_stock_histories'

    belongs_to :warehouse, class_name: 'RawWb::Warehouse'
  end
end
