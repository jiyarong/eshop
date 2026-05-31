module RawWb
  class ProductCharacteristic < ApplicationRecord
    self.table_name = 'raw_wb_product_characteristics'

    belongs_to :product, class_name: 'RawWb::Product'
  end
end
