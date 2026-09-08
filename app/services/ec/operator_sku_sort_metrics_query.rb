module Ec
  class OperatorSkuSortMetricsQuery
    def initialize(skus:, sort_key:, date_to:, time_zone:)
      @skus = skus.to_a
      @sku_codes = @skus.map(&:sku_code)
      @sort_key = sort_key.to_s
      @date_to = date_to.to_date
      @time_zone = time_zone
    end

    def call
      return {} if @sku_codes.empty?

      case @sort_key
      when "weekly_profit" then weekly_profit
      when "weekly_orders" then weekly_orders
      when "book_stock" then book_stock
      else {}
      end
    end

    private

    def weekly_profit
      from_date = @date_to.beginning_of_week(:monday) - 1.week
      report = Ec::WeeklySummaryDeepQuery.run(from_date:, to_date: from_date.end_of_week(:monday), sku_codes: @sku_codes)
      report.fetch(:rows, []).to_h { |row| [row.fetch(:sku).to_s, row[:after_tax]] }
    rescue RuntimeError => error
      raise unless error.message.start_with?("找不到 ")
      {}
    end

    def weekly_orders
      from_date = @date_to.beginning_of_week(:monday) - 1.week
      range = @time_zone.local(from_date.year, from_date.month, from_date.day).beginning_of_day..
        @time_zone.local(from_date.end_of_week.year, from_date.end_of_week.month, from_date.end_of_week.day).end_of_day
      Ec::OrderItem.joins(:order).joins(order_item_join_sql)
        .where(ec_sku_products: { sku_code: @sku_codes }, ec_orders: { ordered_at: range })
        .group("ec_sku_products.sku_code").sum(:quantity).transform_keys(&:to_s)
        .then { |values| @sku_codes.index_with { |code| values.fetch(code, 0) } }
    end

    def book_stock
      Ec::SkuInventoryOverviewBatchQuery.new(skus: @skus).call
        .transform_values { |metrics| metrics[:book_stock] }
    end

    def order_item_join_sql
      <<~SQL.squish
        INNER JOIN ec_sku_products
          ON ec_sku_products.store_id = ec_order_items.store_id
         AND ec_sku_products.platform = ec_order_items.platform
         AND ((ec_order_items.platform = 'ozon' AND ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id)
           OR (ec_order_items.platform = 'wb' AND ec_sku_products.product_id = ec_order_items.platform_sku_id))
      SQL
    end
  end
end
