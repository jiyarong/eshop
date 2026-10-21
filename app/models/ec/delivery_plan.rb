module Ec
  class DeliveryPlan < ApplicationRecord
    include Ec::Auditable
    self.table_name = "ec_delivery_plans"

    belongs_to :store, class_name: "Ec::Store"
    belongs_to :created_by, class_name: "User"
    has_many :items, class_name: "Ec::DeliveryPlanItem", dependent: :destroy, inverse_of: :delivery_plan
    has_many :packing_plans, class_name: "Ec::PalletPlan", dependent: :restrict_with_error

    validates :plan_no, :cluster_name, :week_start, :from_date, :to_date, :time_zone, presence: true
    validates :plan_no, uniqueness: true
    validates :status, inclusion: { in: %w[active cancelled] }
    validates :target_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 180 }
    before_validation { self.plan_no ||= "DP-#{SecureRandom.uuid}" }

    def allocated_units(excluding_plan_id: nil)
      scope = Ec::PalletPlanItem.joins(:pallet_plan)
        .where(ec_pallet_plans: { delivery_plan_id: id }).where.not(ec_pallet_plans: { status: "cancelled" })
      scope = scope.where.not(pallet_plan_id: excluding_plan_id) if excluding_plan_id
      scope.group(:sku_code).sum(:units)
    end
  end
end
