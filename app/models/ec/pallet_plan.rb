module Ec
  class PalletPlan < ApplicationRecord
    include Ec::Auditable
    self.table_name = "ec_pallet_plans"

    STATUSES = %w[draft reserved packing packed dispatched closed cancelled].freeze
    # A closed plan has completed platform handoff and no longer contributes an
    # extra reservation on top of the inventory ledger.
    COMMITTED_STATUSES = %w[reserved packing packed dispatched].freeze
    EDITABLE_STATUSES = %w[draft reserved packing packed].freeze

    belongs_to :store, class_name: "Ec::Store"
    belongs_to :created_by, class_name: "User"
    has_many :items, class_name: "Ec::PalletPlanItem", foreign_key: :pallet_plan_id, dependent: :destroy, inverse_of: :pallet_plan
    has_many :pallets, -> { order(:position) }, class_name: "Ec::Pallet", dependent: :destroy, inverse_of: :pallet_plan

    scope :committed, -> { where(status: COMMITTED_STATUSES) }
    validates :plan_no, :cluster_name, :time_zone, :from_date, :to_date, presence: true
    validates :plan_no, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validates :target_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 180 }
    validates :macrolocal_cluster_id, numericality: { only_integer: true, greater_than: 0 }
    validate { errors.add(:store, :invalid) unless store&.ozon? }

    before_validation { self.plan_no ||= "OP-#{SecureRandom.uuid}" }

    def editable?
      status.in?(EDITABLE_STATUSES) && ozon_order_id.blank?
    end

    def active?
      !status.in?(%w[closed cancelled])
    end
  end
end
