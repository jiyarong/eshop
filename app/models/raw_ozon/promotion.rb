module RawOzon
  class Promotion < ApplicationRecord
    self.table_name = 'raw_ozon_promotions'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
