module Ec
  class Return < ApplicationRecord
    self.table_name = "ec_returns"

    RETURN_TYPES = %w[customer_return cancellation_return unknown].freeze
    PROCESS_STATUSES = %w[
      requested approved moving_to_platform at_platform moving_to_seller
      ready_for_seller_pickup received_by_seller completed cancelled unknown
    ].freeze
    INVENTORY_LOCATIONS = %w[
      customer return_transit platform_return_warehouse platform_saleable
      platform_unsaleable seller_return_transit seller_warehouse disposed unknown
    ].freeze
    INVENTORY_CONDITIONS = %w[saleable defective unknown].freeze
    REFUND_STATUSES = %w[none partial full unknown].freeze

    belongs_to :store, class_name: "Ec::Store"
    belongs_to :order, class_name: "Ec::Order", optional: true
    has_many :items, class_name: "Ec::ReturnItem", foreign_key: :return_id, dependent: :destroy
    has_many :source_links, class_name: "Ec::ReturnSourceLink", foreign_key: :return_id, dependent: :destroy

    validates :platform, inclusion: { in: Ec::Order::PLATFORMS.values }
    validates :return_type, inclusion: { in: RETURN_TYPES }
    validates :process_status, inclusion: { in: PROCESS_STATUSES }
    validates :inventory_location, inclusion: { in: INVENTORY_LOCATIONS }
    validates :inventory_condition, inclusion: { in: INVENTORY_CONDITIONS }
    validates :refund_status, inclusion: { in: REFUND_STATUSES }
    validates :return_key, uniqueness: { scope: %i[platform store_id] }
  end
end
