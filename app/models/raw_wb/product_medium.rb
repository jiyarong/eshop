module RawWb
  class ProductMedium < ApplicationRecord
    self.table_name = 'raw_wb_product_media'

    belongs_to :product, class_name: 'RawWb::Product'
  end
end
