module RawOzon
  class Product < ApplicationRecord
    self.table_name = 'raw_ozon_products'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
    has_one  :product_attribute, class_name: 'RawOzon::ProductAttribute', foreign_key: :ozon_product_id, primary_key: :ozon_product_id
    has_one  :product_price,     class_name: 'RawOzon::ProductPrice',     foreign_key: :ozon_product_id, primary_key: :ozon_product_id
    has_one  :product_stock,     class_name: 'RawOzon::ProductStock',     foreign_key: :ozon_product_id, primary_key: :ozon_product_id
  end
end
