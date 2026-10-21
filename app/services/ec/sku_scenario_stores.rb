module Ec
  # The stores that stand for a pricing scenario of an SKU, so an operator facing twelve scenarios sees which of
  # our stores each one is about. A scenario is a platform, a market, a fulfilment and a tax regime; a store has a
  # platform and a tax regime (WB: TaxiLink is the small taxpayer, WorldChoice the general one; the Ozon stores are
  # all general), so the stores of a scenario are the SKU's stores of that platform and tax regime. At most
  # MAX_STORES are named, the ones that shipped most of the SKU in that fulfilment over the last WEEKS weeks (an
  # order that was not cancelled), then by name. A scenario no store of the SKU fits has none.
  class SkuScenarioStores
    WEEKS = 12
    MAX_STORES = 2
    FULFILLMENT_TYPES = { "fbo" => %w[fbo fbw], "fbs" => %w[fbs] }.freeze

    def self.call(sku:, today:, time_zone: ActiveSupport::TimeZone["Asia/Shanghai"], weeks: WEEKS)
      new(sku:, today:, time_zone:, weeks:).call
    end

    def initialize(sku:, today:, time_zone:, weeks: WEEKS)
      @sku = sku
      @today = today.to_date
      @time_zone = time_zone
      @weeks = Integer(weeks)
    end

    # { "wb|ru|fbo|main|general" => ["WorldChoice"], ... } for every standard scenario that has a store.
    def call
      stores = listed_stores
      units = shipped_units
      Ec::SkuProfitStandardContexts::SCENARIOS.each_with_object({}) do |scenario, result|
        candidates = stores.select { |store| store[:platform] == scenario["platform"] && store[:company_type] == scenario["company_type"] }
        next if candidates.empty?

        types = FULFILLMENT_TYPES.fetch(scenario["delivery_mode"], [])
        ranked = candidates.sort_by do |store|
          [ -types.sum { |type| units.fetch([ store[:id], type ], 0) }, store[:name].to_s.downcase ]
        end
        result[Ec::SkuProfitStandardContexts.key_for(scenario)] = ranked.first(MAX_STORES).map { |store| store[:name] }
      end
    end

    private

    attr_reader :sku, :today, :time_zone, :weeks

    def listed_stores
      sku.sku_products.active.joins(:store).merge(Ec::Store.active)
        .pluck("ec_stores.id", "ec_stores.store_name", "ec_stores.platform", "ec_stores.company_type")
        .uniq
        .map { |id, name, platform, company_type| { id: id, name: name, platform: platform, company_type: company_type } }
    end

    # { [store_id, fulfillment_type] => units }
    def shipped_units
      period_to = today.beginning_of_week(:monday) - 1.day
      period_from = period_to - (weeks * 7 - 1).days
      range = time_zone.local(period_from.year, period_from.month, period_from.day).beginning_of_day..
        time_zone.local(period_to.year, period_to.month, period_to.day).end_of_day

      Ec::OrderItem
        .joins(:order)
        .joins(<<~SQL.squish)
          INNER JOIN ec_sku_products
            ON ec_sku_products.store_id = ec_order_items.store_id
           AND ec_sku_products.platform = ec_order_items.platform
           AND ((ec_order_items.platform = 'ozon' AND ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id)
             OR (ec_order_items.platform = 'wb' AND ec_sku_products.product_id = ec_order_items.platform_sku_id))
        SQL
        .joins("INNER JOIN ec_order_fulfillments ON ec_order_fulfillments.id = ec_order_items.fulfillment_id")
        .where(ec_sku_products: { sku_code: sku.sku_code, is_active: true })
        .where(ec_orders: { ordered_at: range })
        .where.not(ec_orders: { order_status: "cancelled" })
        .where("ec_order_items.quantity > 0")
        .group("ec_order_items.store_id", "ec_order_fulfillments.fulfillment_type")
        .sum("ec_order_items.quantity")
        .transform_values(&:to_i)
    end
  end
end
