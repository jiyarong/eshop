module Ec
  class Pallet < ApplicationRecord
    self.table_name = "ec_pallets"
    belongs_to :pallet_plan, class_name: "Ec::PalletPlan", inverse_of: :pallets
    has_many :items, class_name: "Ec::PalletItem", dependent: :destroy, inverse_of: :pallet

    validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :pallet_plan_id }
    validates :cargo_type, inclusion: { in: %w[pallet box] }
  end
end
