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

    def self.ransackable_attributes(_auth_object = nil)
      %w[
        buyer_city
        external_order_id
        external_order_number
        in_process_at
        order_status
        ordered_at
        platform
        source_status
        source_substatus
        store_id
        synced_at
      ]
    end

    def self.ransackable_associations(_auth_object = nil)
      %w[fulfillments items store]
    end
  end
end
