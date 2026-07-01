module Ec
  class SkuProductOperator < ApplicationRecord
    self.table_name = "ec_sku_product_operators"

    belongs_to :sku_product, class_name: "Ec::SkuProduct"
    belongs_to :user

    validates :sku_product, :user, presence: true
    validates :user_id, uniqueness: { scope: :sku_product_id }
  end
end
