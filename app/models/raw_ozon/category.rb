module RawOzon
  class Category < ApplicationRecord
    self.table_name = 'raw_ozon_categories'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
