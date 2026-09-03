module SalesFunnelReports
  class SkuFunnelAnalysisQuery
    PERIOD_COUNT = 4
    COMMON_METRICS = %i[
      product_card_views cart_additions cart_rate orders cart_to_order_rate
      conversions visit_to_conversion_rate net_sales store_ending_inventory sku_ending_inventory
    ].freeze
    STORE_METRICS = (COMMON_METRICS + %i[
      order_amount platform_fulfilled cancellations
      ozon_total_views ozon_search_views ozon_click_rate ozon_all_cart_additions
      ozon_search_cart_additions ozon_average_search_position ozon_returns
      wb_buyout_amount wb_buyout_rate wb_cancel_amount wb_wishlist wb_stock wb_seller_stock
    ]).freeze

    ORDER_ITEM_JOIN = <<~SQL.squish.freeze
      INNER JOIN ec_sku_products
        ON ec_sku_products.store_id = ec_order_items.store_id
       AND ec_sku_products.platform = ec_order_items.platform
       AND (
         (ec_order_items.platform = 'ozon' AND ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id)
         OR
         (ec_order_items.platform = 'wb' AND ec_sku_products.product_id = ec_order_items.platform_sku_id)
       )
    SQL

    def self.run(sku:, from_date:, to_date:, time_zone: Time.zone)
      new(sku:, from_date:, to_date:, time_zone:).call
    end

    def initialize(sku:, from_date:, to_date:, time_zone:)
      @sku = sku
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @time_zone = time_zone
      validate_period!
    end

    def call
      products = sku.sku_products.includes(:store).select { |product| product.store&.is_active? && product.platform.in?(%w[wb ozon]) }
      periods = build_periods
      range = periods.first[:from_date]..periods.last[:to_date]
      raw_by_product = load_raw_rows(products, range)
      orders_by_product = load_order_rows(products, range)
      inventory = load_inventory(periods)

      store_groups = products.filter_map do |product|
        rows = periods.to_h do |period|
          [period[:key], build_store_row(product, period, raw_by_product.fetch(product.id, []), orders_by_product.fetch(product.id, []), inventory)]
        end
        next unless operating?(rows.fetch("P0"))

        {
          store_id: product.store_id,
          store_ref: store_ref(product.store),
          sku_product_id: product.id,
          platform: product.platform,
          store_name: product.store.store_name,
          listing_label: product.product_name.presence || product.offer_id.presence || product.product_id,
          rows_by_period: rows
        }
      end
      store_groups.sort_by! do |group|
        [-group.dig(:rows_by_period, "P-1", :net_sales).to_i, group[:platform], group[:store_name].to_s]
      end

      periods.each do |period|
        rows = store_groups.map { |group| group[:rows_by_period].fetch(period[:key]) }
        period[:sku_row] = aggregate_sku_row(rows, inventory.dig(period[:to_date], :total))
      end

      { periods:, store_groups:, common_metrics: COMMON_METRICS, store_metrics: STORE_METRICS }
    end

    private

    attr_reader :sku, :from_date, :to_date, :time_zone

    def build_periods
      days = (to_date - from_date).to_i + 1
      PERIOD_COUNT.times.map do |offset|
        { key: offset.zero? ? "P0" : "P-#{offset}", from_date: from_date - (days * offset).days, to_date: to_date - (days * offset).days }
      end.reverse
    end

    def validate_period!
      days = (to_date - from_date).to_i + 1
      valid = from_date.cwday == 1 && to_date.cwday == 7 && days.positive? && (days % 7).zero?
      raise ArgumentError, "invalid_funnel_period" unless valid
    end

    def load_raw_rows(products, range)
      result = Hash.new { |hash, key| hash[key] = [] }
      wb_products = products.select { |product| product.platform == "wb" }.index_by { |product| [product.store.wb_raw_account_id, product.product_id.to_s] }
      ozon_products = products.select { |product| product.platform == "ozon" }.index_by { |product| [product.store.ozon_raw_account_id, product.platform_sku_id.to_s] }

      RawWb::SalesFunnelDaily.where(account_id: wb_products.keys.map(&:first).compact.uniq, stat_date: range).find_each do |record|
        product = wb_products[[record.account_id, record.nm_id.to_s]]
        result[product.id] << record if product
      end
      RawOzon::SalesFunnelDaily.where(account_id: ozon_products.keys.map(&:first).compact.uniq, stat_date: range).find_each do |record|
        product = ozon_products[[record.account_id, record.sku.to_s]]
        result[product.id] << record if product
      end
      result
    end

    def load_order_rows(products, range)
      product_ids = products.index_by(&:id)
      from_time = local_day(range.begin).beginning_of_day
      to_time = local_day(range.end).end_of_day
      result = Hash.new { |hash, key| hash[key] = [] }
      Ec::OrderItem.joins(:order).joins(ORDER_ITEM_JOIN)
        .where(ec_sku_products: { id: product_ids.keys })
        .where(ec_orders: { ordered_at: from_time..to_time })
        .select("ec_order_items.*, ec_sku_products.id AS matched_sku_product_id, ec_orders.ordered_at AS matched_ordered_at, ec_orders.order_status AS matched_order_status")
        .find_each do |item|
          result[item.matched_sku_product_id.to_i] << item
        end
      result
    end

    def load_inventory(periods)
      snapshots = Ec::Snapshot.of_type(Ec::InventorySnapshot.snapshot_type)
        .where(sku_id: sku.id, snapshot_date: periods.map { |period| period[:to_date] })
        .index_by(&:snapshot_date)
      periods.each_with_object({}) do |period, result|
        snapshot = snapshots[period[:to_date]]
        next result[period[:to_date]] = nil unless snapshot

        levels = Array(snapshot.data.dig(:distribution, :levels)).map(&:with_indifferent_access)
        result[period[:to_date]] = {
          total: snapshot.data.dig(:overview, :book_stock)&.to_i,
          stores: levels.select { |level| level[:fulfillment_type].to_s.in?(EndingInventoryQuery::STORE_STOCK_TYPES) }
            .group_by { |level| level[:store_id].to_i }
            .transform_values { |store_levels| store_levels.sum { |level| level[:quantity].to_i } }
        }
      end
    end

    def build_store_row(product, period, raw_records, order_items, inventory)
      raw = raw_records.select { |record| record.stat_date.in?(period[:from_date]..period[:to_date]) }
      items = order_items.select { |item| item.matched_ordered_at.to_date.in?(period[:from_date]..period[:to_date]) }
      platform_values = product.platform == "wb" ? wb_values(raw) : ozon_values(raw)
      conversions = items.select { |item| item.matched_order_status.in?(%w[delivered returned]) }.sum(&:quantity)
      net_sales = items.select { |item| item.matched_order_status == "delivered" }.sum(&:quantity)
      store_inventory = inventory.dig(period[:to_date], :stores, product.store_id)

      platform_values.merge(
        conversions:, net_sales:,
        visit_to_conversion_rate: percent(conversions, platform_values[:product_card_views]),
        store_ending_inventory: store_inventory,
        sku_ending_inventory: inventory.dig(period[:to_date], :total),
        source_present: raw.any? || items.any? || !store_inventory.nil?,
        available_metrics: available_store_metrics(product.platform, raw.any?, items.any?, !inventory[period[:to_date]].nil?)
      )
    end

    def wb_values(records)
      views = sum(records, :open_card)
      carts = sum(records, :add_to_cart)
      orders = sum(records, :orders)
      buyouts = sum(records, :buyouts)
      {
        product_card_views: views, cart_additions: carts, cart_rate: percent(carts, views),
        orders:, cart_to_order_rate: percent(orders, carts), order_amount: sum(records, :orders_sum), currency: wb_currency(records),
        platform_fulfilled: buyouts, cancellations: sum(records, :cancel_count),
        wb_buyout_amount: sum(records, :buyouts_sum), wb_buyout_rate: percent(buyouts, orders),
        wb_cancel_amount: sum(records, :cancel_sum), wb_wishlist: sum(records, :add_to_wishlist),
        wb_stock: latest_sum(records, :stock_wb), wb_seller_stock: latest_sum(records, :stock_mp)
      }
    end

    def ozon_values(records)
      views = sum(records, :hits_view_pdp)
      carts = sum(records, :hits_tocart_pdp)
      orders = sum(records, :ordered_units)
      search_views = sum(records, :hits_view_search)
      {
        product_card_views: views, cart_additions: carts, cart_rate: percent(carts, views),
        orders:, cart_to_order_rate: percent(orders, carts), order_amount: sum(records, :revenue), currency: "RUB",
        platform_fulfilled: sum(records, :delivered_units), cancellations: sum(records, :cancellations),
        ozon_total_views: sum(records, :hits_view), ozon_search_views: search_views,
        ozon_click_rate: percent(views, search_views), ozon_all_cart_additions: sum(records, :hits_tocart),
        ozon_search_cart_additions: sum(records, :hits_tocart_search),
        ozon_average_search_position: average(records, :position_category), ozon_returns: sum(records, :returns_count)
      }
    end

    def aggregate_sku_row(rows, total_inventory)
      views = rows.sum { |row| row[:product_card_views].to_d }
      carts = rows.sum { |row| row[:cart_additions].to_d }
      orders = rows.sum { |row| row[:orders].to_d }
      conversions = rows.sum { |row| row[:conversions].to_d }
      {
        product_card_views: views, cart_additions: carts, cart_rate: percent(carts, views),
        orders:, cart_to_order_rate: percent(orders, carts), conversions:,
        visit_to_conversion_rate: percent(conversions, views),
        net_sales: rows.sum { |row| row[:net_sales].to_d }, sku_ending_inventory: total_inventory,
        source_present: rows.any? { |row| row[:source_present] },
        available_metrics: COMMON_METRICS.select do |metric|
          metric == :sku_ending_inventory ? !total_inventory.nil? : rows.any? { |row| row.fetch(:available_metrics).include?(metric) }
        end
      }
    end

    def available_store_metrics(platform, funnel_present, orders_present, inventory_present)
      metrics = []
      if funnel_present
        metrics.concat(%i[product_card_views cart_additions cart_rate orders cart_to_order_rate order_amount platform_fulfilled cancellations])
        metrics.concat(platform == "wb" ? %i[wb_buyout_amount wb_buyout_rate wb_cancel_amount wb_wishlist wb_stock wb_seller_stock] : %i[ozon_total_views ozon_search_views ozon_click_rate ozon_all_cart_additions ozon_search_cart_additions ozon_average_search_position ozon_returns])
      end
      metrics.concat(%i[conversions visit_to_conversion_rate net_sales]) if orders_present
      metrics.concat(%i[store_ending_inventory sku_ending_inventory]) if inventory_present
      metrics
    end

    def operating?(row)
      row[:product_card_views].to_d.positive? || row[:conversions].to_d.positive? || row[:store_ending_inventory].to_i.positive?
    end

    def sum(records, field)
      records.sum { |record| record.public_send(field).to_d }
    end

    def average(records, field)
      values = records.filter_map { |record| record.public_send(field)&.to_d }
      values.empty? ? nil : (values.sum / values.length).round(2)
    end

    def wb_currency(records)
      records.filter_map { |record| record.currency.presence }.uniq.first || "RUB"
    end

    def latest_sum(records, field)
      latest_date = records.map(&:stat_date).max
      latest_date ? sum(records.select { |record| record.stat_date == latest_date }, field) : nil
    end

    def percent(numerator, denominator)
      return nil unless denominator.to_d.positive?

      (numerator.to_d / denominator.to_d * 100).round(2)
    end

    def local_day(date)
      time_zone.local(date.year, date.month, date.day)
    end

    def store_ref(store)
      account_id = store.wb? ? store.wb_raw_account_id : store.ozon_raw_account_id
      "#{store.platform}:#{account_id}"
    end
  end
end
