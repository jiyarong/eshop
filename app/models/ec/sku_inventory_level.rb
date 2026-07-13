module Ec
  class SkuInventoryLevel < ApplicationRecord
    self.table_name = "ec_sku_inventory_levels"

    FULFILLMENT_TYPES = %w[fbw fbs fbo inbound].freeze

    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code
    belongs_to :store, class_name: "Ec::Store", optional: true

    validates :sku_code, :platform, :account_id, :fulfillment_type, :synced_at, presence: true
    validates :quantity, numericality: { greater_than_or_equal_to: 0 }
    validates :fulfillment_type, inclusion: { in: FULFILLMENT_TYPES }

    scope :latest, -> { where(is_latest: true) }
    scope :ordered_latest, -> { latest.order(:sku_code, :platform, :store_name, :fulfillment_type) }

    before_validation { self.sku_code = sku_code&.upcase }
  end
end
