module Ec
  class SkuLifecycleEvent < ApplicationRecord
    self.table_name = "ec_sku_lifecycle_events"

    EVENT_TYPES = %w[
      first_sale
      marketing_state_changed
      purchase_ordered
      purchase_received
      profit_grade_reached
      cumulative_profit_reached
      replenishment
      platform_stockout
      all_platform_stockout
      stock_recovered
    ].freeze

    CONTENT_SCHEMAS = {
      "first_sale" => %w[order_id order_item_id platform store_id sku_product_id quantity platform_sku_id],
      "marketing_state_changed" => %w[to_grade to_stage initial_state],
      "purchase_ordered" => %w[batch_code purchased_quantity status time_precision],
      "purchase_received" => %w[batch_code received_quantity received_on status initialized_batch time_precision],
      "profit_grade_reached" => %w[grade week_from week_to annualized_net_profit_cny annualized_return_pct after_tax time_precision],
      "cumulative_profit_reached" => %w[threshold_cny cumulative_profit_cny week_from week_to time_precision],
      "replenishment" => %w[platform quantity],
      "platform_stockout" => %w[platform quantity first_zero_date confirmed_on consecutive_zero_days time_precision],
      "all_platform_stockout" => %w[started_on confirmed_on platform_stock threshold_quantity confirmation_days time_precision],
      "stock_recovered" => %w[scope stockout_source_key recovered_on confirmed_on platform_stock confirmation_days time_precision]
    }.freeze

    belongs_to :sku, class_name: "Ec::Sku"
    belongs_to :sku_product, class_name: "Ec::SkuProduct", optional: true

    validates :event_type, inclusion: { in: EVENT_TYPES }
    validates :occurred_at, :source_key, presence: true
    validates :source_key, uniqueness: true
    validate :sku_product_belongs_to_sku
    validate :required_content_fields

    scope :chronological, -> { order(occurred_at: :asc, id: :asc) }

    private

    def sku_product_belongs_to_sku
      return if sku_product.blank? || sku.blank?
      return if sku_product.sku_code == sku.sku_code

      errors.add(:sku_product, :invalid)
    end

    def required_content_fields
      return unless EVENT_TYPES.include?(event_type)

      missing_fields = CONTENT_SCHEMAS.fetch(event_type).reject { |key| content.to_h.key?(key) || content.to_h.key?(key.to_sym) }
      errors.add(:content, :invalid, missing: missing_fields.join(", ")) if missing_fields.any?
    end
  end
end
