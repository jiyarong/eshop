module Ec
  # The commission base price actually realized in ONE pricing scenario over the last full
  # weeks: SkuActualSellingPriceQuery narrowed to the scenario's tax regime (store company
  # type) and fulfillment (WB FBW counts as FBO). The page-level query averages a whole
  # platform/market; a scenario price must not borrow another scenario's orders.
  class SkuActualScenarioPriceQuery < SkuActualSellingPriceQuery
    FULFILLMENT_TYPES = { "fbo" => %w[fbo fbw], "fbs" => %w[fbs] }.freeze
    COMPANY_TYPES = %w[general small].freeze

    def self.run(sku:, platform:, market:, delivery_mode:, company_type:, today:, time_zone:, weeks: DEFAULT_WEEKS)
      new(sku:, platform:, market:, delivery_mode:, company_type:, today:, time_zone:, weeks:).run
    end

    def initialize(delivery_mode:, company_type:, **arguments)
      super(**arguments)
      @delivery_mode = delivery_mode.to_s.downcase
      @company_type = company_type.to_s.downcase
      raise ArgumentError, "unsupported_delivery_mode" unless FULFILLMENT_TYPES.key?(@delivery_mode)
      raise ArgumentError, "unsupported_company_type" unless COMPANY_TYPES.include?(@company_type)
    end

    private

    attr_reader :delivery_mode, :company_type

    def order_rows(period_from:, period_to:)
      # Ozon has a single tax regime among the scenarios; only WB splits stores by it.
      stores = Ec::Store.active.where(platform: platform)
      stores = stores.where(company_type: company_type) if platform == "wb"
      active_store_ids = stores.ids
      return [] if active_store_ids.empty?

      Ec::OrderItem
        .joins(:order)
        .joins(order_item_sku_product_join_sql)
        .joins("INNER JOIN ec_order_fulfillments ON ec_order_fulfillments.id = ec_order_items.fulfillment_id")
        .where(ec_sku_products: { sku_code: sku.sku_code, is_active: true })
        .where(ec_order_items: { platform: platform, store_id: active_store_ids })
        .where(ec_order_fulfillments: { fulfillment_type: FULFILLMENT_TYPES.fetch(delivery_mode) })
        .where(ec_orders: { ordered_at: user_time_range(period_from, period_to) })
        .where.not(ec_orders: { order_status: "cancelled" })
        .where("ec_order_items.quantity > 0")
        .where("ec_order_items.unit_price > 0 OR ec_order_items.buyer_paid_unit_price > 0")
        .distinct
        .pluck(
          "ec_order_items.id",
          "ec_order_items.unit_price",
          "ec_order_items.currency_code",
          "ec_order_items.buyer_paid_unit_price",
          "ec_order_items.buyer_currency_code",
          "ec_order_items.quantity",
          "ec_orders.ordered_at",
          "ec_orders.external_order_id"
        ).map do |id, commission_base_price, commission_base_currency, buyer_paid_price, buyer_currency, quantity, ordered_at, external_order_id|
          {
            id: id,
            external_order_id: external_order_id,
            commission_base_price: commission_base_price&.to_d,
            commission_base_currency: commission_base_currency.to_s.upcase.presence,
            buyer_paid_price: buyer_paid_price&.to_d,
            buyer_currency: buyer_currency.to_s.upcase.presence,
            quantity: quantity.to_i,
            ordered_at: ordered_at
          }
        end
    end
  end
end
