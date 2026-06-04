module Ec
  class OrderItem < ApplicationRecord
    self.table_name = "ec_order_items"

    enum :platform, Ec::Order::PLATFORMS, prefix: :platform, validate: true

    belongs_to :order, class_name: "Ec::Order"
    belongs_to :fulfillment, class_name: "Ec::OrderFulfillment", optional: true
    belongs_to :store, class_name: "Ec::Store"
    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code, optional: true
    has_many :source_links, class_name: "Ec::OrderSourceLink", foreign_key: :item_id, dependent: :nullify

    validates :platform, :store, :order, :quantity, presence: true

    def self.ransackable_attributes(_auth_object = nil)
      %w[offer_id platform platform_sku_id product_name_source sku_code store_id]
    end
  end
end
