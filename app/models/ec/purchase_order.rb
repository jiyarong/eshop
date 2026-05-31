module Ec
  class PurchaseOrder < ApplicationRecord
    self.table_name = "ec_purchase_orders"

    STATUSES = %w[draft ordered partially_received received cancelled].freeze

    belongs_to :supplier, class_name: "Ec::Supplier"
    has_many :items, class_name: "Ec::PurchaseOrderItem", foreign_key: :purchase_order_id, dependent: :destroy

    validates :order_no, presence: true, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validates :currency, presence: true

    before_validation { self.order_no = order_no&.strip&.upcase }

    def goods_amount_cny
      items.sum { |item| item.amount_cny }.to_d
    end
  end
end
