module RawWb
  class ProductSku < ApplicationRecord
    self.table_name = 'raw_wb_product_skus'

    belongs_to :product, class_name: 'RawWb::Product'

    has_many :stocks, class_name: 'RawWb::Stock', foreign_key: :sku_id, dependent: :destroy
  end
end
