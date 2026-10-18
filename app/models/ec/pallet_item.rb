module Ec
  class PalletItem < ApplicationRecord
    self.table_name = "ec_pallet_items"
    belongs_to :pallet, class_name: "Ec::Pallet", inverse_of: :items
    belongs_to :pallet_plan_item, class_name: "Ec::PalletPlanItem"

    validates :boxes, :units, numericality: { only_integer: true, greater_than: 0 }
    validate do
      errors.add(:pallet_plan_item, :invalid) unless pallet_plan_item&.pallet_plan_id == pallet&.pallet_plan_id
      errors.add(:units, :invalid) unless units == boxes.to_i * pallet_plan_item&.pcs.to_i
    end
  end
end
