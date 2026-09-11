module RawOzon
  class AttributeValue < ApplicationRecord
    self.table_name = "raw_ozon_attribute_values"

    belongs_to :account, class_name: "RawOzon::SellerAccount"
  end
end
