module Ec
  class SkuProduct < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_sku_products"

    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code
    belongs_to :store, class_name: "Ec::Store"
    has_many :operator_assignments,
      class_name: "Ec::SkuProductOperator",
      foreign_key: :sku_product_id,
      dependent: :destroy
    has_many :operators, through: :operator_assignments, source: :user

    validates :sku_code, :store, :platform, :product_id, presence: true
    validates :product_id, uniqueness: { scope: :store_id }

    before_validation :assign_platform
    before_validation { self.sku_code = sku_code&.upcase }

    scope :ordered, -> { joins(:store).order("ec_stores.platform", "ec_stores.store_name", :product_id) }

    private

    def assign_platform
      self.platform = store&.platform if store
    end
  end
end
