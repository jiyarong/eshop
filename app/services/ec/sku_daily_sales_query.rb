module Ec
  class SkuDailySalesQuery
    def initialize(sku_codes:, from_date:, to_date:, time_zone:)
      @sku_codes = Array(sku_codes).map(&:to_s).map(&:upcase).uniq
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @time_zone = time_zone
    end

    def call
      return {} if @sku_codes.empty?

      relation.each_with_object({}) do |((sale_date, sku_code), quantity), result|
        result[[ sale_date.to_date, sku_code.to_s ]] = quantity.to_i
      end
    end

    private

    def relation
      Ec::OrderItem
        .joins(:order)
        .joins(order_item_sku_product_join_sql)
        .where(ec_sku_products: { sku_code: @sku_codes })
        .where.not(ec_orders: { order_status: %w[cancelled returned] })
        .where(ec_orders: { ordered_at: user_date_range })
        .group(Arel.sql("DATE(#{ordered_at_in_time_zone_sql})"), "ec_sku_products.sku_code")
        .sum(:quantity)
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
      ActiveRecord::Base.connection.quote(@time_zone.tzinfo.name)
    end

    def user_date_range
      time_for_date(@from_date).beginning_of_day..time_for_date(@to_date).end_of_day
    end

    def time_for_date(date)
      @time_zone.local(date.year, date.month, date.day)
    end
  end
end
