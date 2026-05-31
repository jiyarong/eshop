module RawWb
  class PromotionProduct < ApplicationRecord
    self.table_name = 'raw_wb_promotion_products'

    belongs_to :promotion, class_name: 'RawWb::Promotion'
  end
end
