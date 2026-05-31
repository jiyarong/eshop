module Ec
  class PaymentRequest < ApplicationRecord
    self.table_name = "ec_payment_requests"

    PAYMENT_TYPES = %w[deposit balance other].freeze
    STATUSES = %w[pending approved paid cancelled].freeze

    belongs_to :purchase_order, class_name: "Ec::PurchaseOrder"

    validates :payment_type, inclusion: { in: PAYMENT_TYPES }
    validates :status, inclusion: { in: STATUSES }
    validates :amount_cny, numericality: { greater_than: 0 }
  end
end
