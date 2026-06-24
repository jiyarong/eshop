module Ec
  class OrderFulfillment < ApplicationRecord
    self.table_name = "ec_order_fulfillments"

    FULFILLMENT_TYPES = {
      fbo: "fbo",
      fbw: "fbw",
      fbs: "fbs",
      fba: "fba",
      fbm: "fbm",
      unknown: "unknown"
    }.freeze

    enum :platform, Ec::Order::PLATFORMS, prefix: :platform, validate: true
    enum :fulfillment_type, FULFILLMENT_TYPES, prefix: :fulfillment, validate: true
    enum :status, Ec::Order::STATUSES, prefix: :status, validate: true

    belongs_to :order, class_name: "Ec::Order"
    belongs_to :store, class_name: "Ec::Store"
    has_many :items, class_name: "Ec::OrderItem", foreign_key: :fulfillment_id, dependent: :nullify
    has_many :source_links, class_name: "Ec::OrderSourceLink", foreign_key: :fulfillment_id, dependent: :nullify

    validates :platform, :store, :order, :external_fulfillment_id, :fulfillment_key, :fulfillment_type, :status, presence: true
    validates :fulfillment_key, uniqueness: { scope: [:platform, :store_id] }

    def raw_source
      return if raw_source_type.blank? || raw_source_id.blank?

      raw_source_type.constantize.find_by(id: raw_source_id)
    rescue NameError
      nil
    end

    def self.ransackable_attributes(_auth_object = nil)
      %w[external_fulfillment_id fulfillment_type platform source_status source_substatus status store_id]
    end
  end
end
