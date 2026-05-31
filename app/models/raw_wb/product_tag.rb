module RawWb
  class ProductTag < ApplicationRecord
    self.table_name = 'raw_wb_product_tags'

    belongs_to :account, class_name: 'RawWb::SellerAccount'

    has_many :product_tag_links, class_name: 'RawWb::ProductTagLink', foreign_key: :tag_id, dependent: :destroy
    has_many :products, through: :product_tag_links
  end
end
