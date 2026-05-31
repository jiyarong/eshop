module RawWb
  class ProductTagLink < ApplicationRecord
    self.table_name = 'raw_wb_product_tag_links'

    belongs_to :product, class_name: 'RawWb::Product'
    belongs_to :tag,     class_name: 'RawWb::ProductTag'
  end
end
