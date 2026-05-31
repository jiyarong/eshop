module Ec
  class PurchaseOrderItem < ApplicationRecord
    self.table_name = "ec_purchase_order_items"

    belongs_to :purchase_order, class_name: "Ec::PurchaseOrder"
    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code
    belongs_to :sku_batch, class_name: "Ec::SkuBatch"

    validates :sku_code, presence: true
    validates :quantity, numericality: { greater_than: 0 }
    validates :unit_price_cny, numericality: { greater_than_or_equal_to: 0 }
    validates :sku_batch_id, uniqueness: { scope: :purchase_order_id }

    before_validation { self.sku_code = sku_code&.upcase }

    def amount_cny
      quantity.to_d * unit_price_cny.to_d
    end
  end
end
