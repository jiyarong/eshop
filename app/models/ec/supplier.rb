module Ec
  class Supplier < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_suppliers"

    has_many :purchase_orders, class_name: "Ec::PurchaseOrder", foreign_key: :supplier_id

    validates :name, presence: true, uniqueness: true

    scope :active, -> { where(is_active: true) }
  end
end
