module Ec
  class ReturnItem < ApplicationRecord
    self.table_name = "ec_return_items"

    belongs_to :return, class_name: "Ec::Return"
    belongs_to :store, class_name: "Ec::Store"
    belongs_to :sku_product, class_name: "Ec::SkuProduct", optional: true
    belongs_to :order_item, class_name: "Ec::OrderItem", optional: true

    validates :platform, inclusion: { in: Ec::Order::PLATFORMS.values }
    validates :item_key, uniqueness: { scope: :return_id }
    validates :quantity, numericality: { only_integer: true, greater_than: 0 }

    scope :restockable, -> { where(restockable: true) }
  end
end
