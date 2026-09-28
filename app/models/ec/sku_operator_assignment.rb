module Ec
  class SkuOperatorAssignment < ApplicationRecord
    self.table_name = "ec_sku_operator_assignments"

    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code
    belongs_to :user

    validates :sku, :user, presence: true
    validates :sku_code, uniqueness: true
  end
end
