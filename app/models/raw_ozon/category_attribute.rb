module RawOzon
  class CategoryAttribute < ApplicationRecord
    self.table_name = "raw_ozon_category_attributes"

    belongs_to :account, class_name: "RawOzon::SellerAccount"
  end
end
