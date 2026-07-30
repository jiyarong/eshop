module Ec
  class OperationAction < ApplicationRecord
    self.table_name = "ec_operation_actions"

    OPERATION_TYPES = %w[
      listing_content
      listing_pricing
      listing_specification
      sku_adv_on_off
      sku_inbound_change
    ].freeze

    belongs_to :operated_by_user, class_name: "User"
    belongs_to :sku_product, class_name: "Ec::SkuProduct", foreign_key: :ec_sku_product_id
    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :ec_sku_id
    belongs_to :store, class_name: "Ec::Store", foreign_key: :ec_store_id

    validates :operation_type, inclusion: { in: OPERATION_TYPES }
    validates :operated_at, :diff_result, presence: true
    validate :listing_associations_are_consistent

    private

    def listing_associations_are_consistent
      return unless sku_product

      errors.add(:sku, :invalid) if sku && sku != sku_product.sku
      errors.add(:store, :invalid) if store && store != sku_product.store
    end
  end
end
