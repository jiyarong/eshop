module RawWb
  class Product < ApplicationRecord
    self.table_name = 'raw_wb_products'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
    belongs_to :subject, class_name: 'RawWb::Subject', optional: true

    has_many :product_characteristics, class_name: 'RawWb::ProductCharacteristic', foreign_key: :product_id, dependent: :destroy
    has_many :product_skus,            class_name: 'RawWb::ProductSku',            foreign_key: :product_id, dependent: :destroy
    has_many :product_media,           class_name: 'RawWb::ProductMedium',         foreign_key: :product_id, dependent: :destroy
    has_many :product_tag_links,       class_name: 'RawWb::ProductTagLink',        foreign_key: :product_id, dependent: :destroy
    has_many :product_tags,            through: :product_tag_links
    has_one  :product_price,           class_name: 'RawWb::ProductPrice',          foreign_key: :product_id, dependent: :destroy
    has_many :product_price_histories, class_name: 'RawWb::ProductPriceHistory',   foreign_key: :product_id, dependent: :destroy
  end
end
