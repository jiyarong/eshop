module Ec
  class PurchaseOrder < ApplicationRecord
    self.table_name = "ec_purchase_orders"

    STATUSES = %w[draft ordered partially_received received cancelled].freeze

    belongs_to :supplier, class_name: "Ec::Supplier"
    has_many :items, class_name: "Ec::PurchaseOrderItem", foreign_key: :purchase_order_id, dependent: :destroy, inverse_of: :purchase_order
    has_many :payment_requests, class_name: "Ec::PaymentRequest", foreign_key: :purchase_order_id, dependent: :destroy

    accepts_nested_attributes_for :items, reject_if: :reject_blank_item

    validates :order_no, presence: true, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validates :currency, presence: true

    before_validation { self.order_no = order_no&.strip&.upcase }

    def goods_amount_cny
      items.sum { |item| item.amount_cny }.to_d
    end

    def paid_amount_cny
      payment_requests.select { |payment| payment.status == "paid" }.sum { |payment| payment.amount_cny.to_d }
    end

    private

    def reject_blank_item(attributes)
      attributes[:sku_batch_id].blank? && attributes[:quantity].blank? && attributes[:unit_price_cny].blank?
    end
  end
end
