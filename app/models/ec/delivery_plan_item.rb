module Ec
  class DeliveryPlanItem < ApplicationRecord
    include Ec::Auditable
    self.table_name = "ec_delivery_plan_items"

    belongs_to :delivery_plan, class_name: "Ec::DeliveryPlan", inverse_of: :items
    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code
    validates :sku_code, presence: true, uniqueness: { scope: :delivery_plan_id }
    validates :units, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  end
end
