module Ec
  class SkuOperationActionMetricsQuery
    WB_METRICS = {
      views: :open_card,
      add_to_cart: :add_to_cart,
      funnel_orders: :orders,
      revenue: :orders_sum,
      buyouts: :buyouts,
      cancellations: :cancel_count,
      wishlist: :add_to_wishlist,
      stock_wb: :stock_wb,
      stock_mp: :stock_mp
    }.freeze
    OZON_METRICS = {
      views: :hits_view,
      sessions: :session_view,
      add_to_cart: :hits_tocart,
      funnel_orders: :ordered_units,
      revenue: :revenue,
      returns: :returns_count,
      cancellations: :cancellations
    }.freeze

    def initialize(sku:, from_date:, to_date:, time_zone:)
      @sku = sku
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @time_zone = time_zone
    end

    def call
      {
        sales_by_day_and_platform: sales_by_day_and_platform,
        funnel_by_day_and_platform: funnel_by_day_and_platform
      }
    end

    private

    attr_reader :sku, :from_date, :to_date, :time_zone

    def sales_by_day_and_platform
      sales_relation.each_with_object({}) do |((sale_date, platform), quantity), result|
        result[[ sale_date.to_date, platform.to_s ]] = quantity.to_i
      end
    end

    def sales_relation
      Ec::OrderItem
        .joins(:order)
        .joins(order_item_sku_product_join_sql)
        .where(ec_sku_products: { sku_code: sku.sku_code })
        .where.not(ec_orders: { order_status: %w[cancelled returned] })
        .where(ec_orders: { ordered_at: date_range })
        .group(Arel.sql("DATE(#{ordered_at_in_time_zone_sql})"), "ec_order_items.platform")
        .sum(:quantity)
    end

    def funnel_by_day_and_platform
      result = Hash.new { |hash, key| hash[key] = Hash.new(0.to_d) }
      seen_products = {}

      sku.sku_products.includes(:store).find_each do |product|
        source = funnel_source(product)
        next unless source
        next if seen_products[source.fetch(:key)]

        seen_products[source.fetch(:key)] = true
        source.fetch(:scope).find_each do |row|
          metrics = result[[ row.stat_date, product.platform ]]
          source.fetch(:metrics).each do |metric, field|
            metrics[metric] += row.public_send(field).to_d
          end
          metrics[:source_rows] += 1
        end
      end

      result
    end

    def funnel_source(product)
      case product.platform
      when "wb"
        account_id = product.store.wb_raw_account_id
        platform_id = Integer(product.product_id, exception: false)
        return unless account_id && platform_id

        {
          key: [ "wb", account_id, platform_id ],
          metrics: WB_METRICS,
          scope: RawWb::SalesFunnelDaily.where(
            account_id: account_id,
            nm_id: platform_id,
            stat_date: from_date..to_date
          )
        }
      when "ozon"
        account_id = product.store.ozon_raw_account_id
        platform_id = Integer(product.platform_sku_id, exception: false)
        return unless account_id && platform_id

        {
          key: [ "ozon", account_id, platform_id ],
          metrics: OZON_METRICS,
          scope: RawOzon::SalesFunnelDaily.where(
            account_id: account_id,
            sku: platform_id,
            stat_date: from_date..to_date
          )
        }
      end
    end

    def order_item_sku_product_join_sql
      <<~SQL.squish
        INNER JOIN ec_sku_products
          ON ec_sku_products.store_id = ec_order_items.store_id
         AND ec_sku_products.platform = ec_order_items.platform
         AND (
           (ec_order_items.platform = 'ozon' AND ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id)
           OR
           (ec_order_items.platform = 'wb' AND ec_sku_products.product_id = ec_order_items.platform_sku_id)
         )
      SQL
    end

    def ordered_at_in_time_zone_sql
      "(ec_orders.ordered_at AT TIME ZONE 'UTC') AT TIME ZONE #{quoted_time_zone}"
    end

    def quoted_time_zone
      ActiveRecord::Base.connection.quote(time_zone.tzinfo.name)
    end

    def date_range
      time_for_date(from_date).beginning_of_day..time_for_date(to_date).end_of_day
    end

    def time_for_date(date)
      time_zone.local(date.year, date.month, date.day)
    end
  end
end
