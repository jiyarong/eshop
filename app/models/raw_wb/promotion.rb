module RawWb
  class Promotion < ApplicationRecord
    self.table_name = 'raw_wb_promotions'

    belongs_to :account, class_name: 'RawWb::SellerAccount'

    has_many :promotion_products, class_name: 'RawWb::PromotionProduct', foreign_key: :promotion_id, dependent: :destroy
  end
end
