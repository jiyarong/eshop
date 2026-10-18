module Ec
  class PalletPlanItem < ApplicationRecord
    self.table_name = "ec_pallet_plan_items"
    belongs_to :pallet_plan, class_name: "Ec::PalletPlan", inverse_of: :items
    belongs_to :sku_product, class_name: "Ec::SkuProduct"
    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code
    has_many :pallet_items, class_name: "Ec::PalletItem", dependent: :destroy

    validates :sku_code, :platform_sku_id, presence: true
    validates :sku_code, uniqueness: { scope: :pallet_plan_id }
    validates :boxes, :pcs, :units, numericality: { only_integer: true, greater_than: 0 }
    validates :platform_covered_units, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: :units }
    validate { errors.add(:units, :invalid) unless units == boxes.to_i * pcs.to_i }
    validate do
      unless sku_product && sku_product.sku_code == sku_code && sku_product.store_id == pallet_plan&.store_id
        errors.add(:sku_product, :invalid)
      end
    end
  end
end
