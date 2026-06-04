module Ec
  class Order < ApplicationRecord
    self.table_name = "ec_orders"

    PLATFORMS = { wb: "wb", ozon: "ozon", amazon: "amazon" }.freeze
    STATUSES = {
      pending: "pending",
      processing: "processing",
      shipped: "shipped",
      delivered: "delivered",
      cancelled: "cancelled",
      returned: "returned",
      unknown: "unknown"
    }.freeze

    enum :platform, PLATFORMS, prefix: :platform, validate: true
    enum :order_status, STATUSES, prefix: :order, validate: true

    belongs_to :store, class_name: "Ec::Store"
    has_many :fulfillments, class_name: "Ec::OrderFulfillment", foreign_key: :order_id, dependent: :destroy
    has_many :items, class_name: "Ec::OrderItem", foreign_key: :order_id, dependent: :destroy
    has_many :source_links, class_name: "Ec::OrderSourceLink", foreign_key: :order_id, dependent: :destroy

    validates :platform, :store, :order_key, :order_status, presence: true
    validates :order_key, uniqueness: { scope: [:platform, :store_id] }
  end
end
