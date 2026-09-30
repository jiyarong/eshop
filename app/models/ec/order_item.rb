module Ec
  class OrderItem < ApplicationRecord
    self.table_name = "ec_order_items"

    WB_PLATFORM_FULFILLMENT_TYPES = %w[fbw fbo].freeze

    enum :platform, Ec::Order::PLATFORMS, prefix: :platform, validate: true

    belongs_to :order, class_name: "Ec::Order"
    belongs_to :fulfillment, class_name: "Ec::OrderFulfillment", optional: true
    belongs_to :store, class_name: "Ec::Store"
    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code, optional: true
    has_many :source_links, class_name: "Ec::OrderSourceLink", foreign_key: :item_id, dependent: :nullify
    has_many :return_items, class_name: "Ec::ReturnItem", foreign_key: :order_item_id, dependent: :nullify
    has_one :ozon_posting_report_item, class_name: "RawOzon::PostingReportItem", foreign_key: :ec_order_item_id, dependent: :nullify

    validates :platform, :store, :order, :quantity, presence: true

    scope :deductible_from_book_inventory, -> {
      joins(:order)
        .left_joins(:fulfillment)
        .where.not(ec_orders: { order_status: "cancelled" })
        .where(
          <<~SQL.squish,
            NOT (
              ec_orders.platform = :platform
              AND ec_orders.order_status = :returned_status
              AND COALESCE(ec_order_fulfillments.fulfillment_type, '') IN (:fulfillment_types)
            )
          SQL
          platform: "wb",
          returned_status: "returned",
          fulfillment_types: WB_PLATFORM_FULFILLMENT_TYPES
        )
    }

    def self.ransackable_attributes(_auth_object = nil)
      %w[offer_id platform platform_sku_id product_name_source sku_code store_id]
    end
  end
end
