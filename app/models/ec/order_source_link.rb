module Ec
  class OrderSourceLink < ApplicationRecord
    self.table_name = "ec_order_source_links"

    SOURCE_ROLES = {
      primary: "primary",
      item: "item",
      finance: "finance",
      status: "status",
      supplement: "supplement"
    }.freeze

    enum :platform, Ec::Order::PLATFORMS, prefix: :platform, validate: true
    enum :source_role, SOURCE_ROLES, prefix: :source, validate: true

    belongs_to :order, class_name: "Ec::Order"
    belongs_to :fulfillment, class_name: "Ec::OrderFulfillment", optional: true
    belongs_to :item, class_name: "Ec::OrderItem", optional: true

    validates :platform, :source_type, :source_id, :source_role, presence: true
    validates :source_id, uniqueness: { scope: [:source_type, :source_role] }

    def source
      source_type.constantize.find_by(id: source_id)
    rescue NameError
      nil
    end
  end
end
