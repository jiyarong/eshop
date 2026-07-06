module Ec
  class SkuSalesQuery
    VALID_PERIODS = %w[day week month range].freeze
    VALID_GRAINS = %w[store platform sku].freeze

    def initialize(sku_codes: nil, sku_product_ids: nil, from_date:, to_date:, period:, grain:, time_zone:, platform: nil, store_id: nil)
      @sku_codes = Array(sku_codes).presence
      @sku_product_ids = sku_product_ids
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @period = period.presence_in(VALID_PERIODS) || "day"
      @grain = grain.presence_in(VALID_GRAINS) || "store"
      @time_zone = time_zone
      @platform = platform
      @store_id = store_id
    end

    def call
      relation.map { |row| row_hash(row) }
        .sort_by { |row| [row[:period_start], row[:sku_code].to_s, row[:platform].to_s, row[:store_name].to_s] }
    end

    private

    attr_reader :sku_codes, :sku_product_ids, :from_date, :to_date, :period, :grain, :time_zone, :platform, :store_id

    def relation
      scope = Ec::OrderItem
        .joins(:order, :store)
        .left_joins(:fulfillment)
        .joins(order_item_sku_product_join_sql)
        .joins("LEFT JOIN ec_skus ON ec_skus.sku_code = ec_sku_products.sku_code")
        .where(ec_orders: { ordered_at: user_date_range })
      if !sku_product_ids.nil?
        scope = scope.where(ec_sku_products: { id: sku_product_ids })
      elsif sku_codes.present?
        scope = scope.where(ec_sku_products: { sku_code: sku_codes })
      end
      scope = scope.where(ec_order_items: { platform: platform }) if platform.present?
      scope = scope.where(ec_order_items: { store_id: store_id }) if store_id.present?

      scope
        .select(select_sql)
        .group(*group_columns)
        .order(Arel.sql(order_columns.join(", ")))
    end

    def select_sql
      [
        "#{period_sql} AS period_start",
        "#{sku_sql} AS sku_code",
        "MAX(ec_skus.product_name) AS product_name",
        "#{platform_sql} AS platform",
        "#{store_sql} AS store_name",
        "SUM(#{sales_case}) AS sales_quantity",
        "SUM(#{return_case}) AS return_quantity",
        "SUM(#{sales_case}) - SUM(#{return_case}) AS net_quantity",
        "COUNT(DISTINCT ec_orders.id) AS order_count",
        "SUM(ec_order_items.quantity * COALESCE(ec_order_items.unit_price, 0)) AS gross_revenue",
        "SUM(COALESCE(ec_order_items.payout, 0)) AS payout",
        "SUM(COALESCE(ec_order_items.commission_amount, 0)) AS commission",
        "SUM(COALESCE(ec_order_items.discount_amount, 0)) AS discount",
        "AVG(ec_order_items.unit_price) AS average_unit_price",
        "STRING_AGG(DISTINCT ec_order_fulfillments.fulfillment_type, ' / ') AS fulfillment_types",
        "MAX(ec_orders.ordered_at) AS last_ordered_at"
      ].join(", ")
    end

    def row_hash(row)
      {
        period_start: row.period_start.to_date,
        sku_code: row.sku_code,
        product_name: row.product_name,
        platform: row.platform,
        store_name: row.store_name,
        sales_quantity: row.sales_quantity.to_i,
        return_quantity: row.return_quantity.to_i,
        net_quantity: row.net_quantity.to_i,
        order_count: row.order_count.to_i,
        gross_revenue: row.gross_revenue.to_d,
        payout: row.payout.to_d,
        commission: row.commission.to_d,
        discount: row.discount.to_d,
        average_unit_price: row.average_unit_price.to_d,
        fulfillment_types: row.fulfillment_types.to_s,
        last_ordered_at: row.respond_to?(:last_ordered_at) ? row.last_ordered_at : nil
      }
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

    def period_sql
      period == "range" ? "'#{from_date}'::date" : "DATE_TRUNC('#{period}', #{ordered_at_in_user_zone_sql})"
    end

    def ordered_at_in_user_zone_sql
      "(ec_orders.ordered_at AT TIME ZONE 'UTC') AT TIME ZONE #{user_time_zone_sql}"
    end

    def user_time_zone_sql
      ActiveRecord::Base.connection.quote(time_zone.tzinfo.name)
    end

    def user_date_range
      time_zone.local(from_date.year, from_date.month, from_date.day).beginning_of_day..
        time_zone.local(to_date.year, to_date.month, to_date.day).end_of_day
    end

    def sku_sql
      "ec_sku_products.sku_code"
    end

    def platform_sql
      grain == "sku" ? "NULL" : "ec_order_items.platform"
    end

    def store_sql
      grain == "store" ? "ec_stores.store_name" : "NULL"
    end

    def group_columns
      columns = ["period_start", sku_sql]
      columns << "ec_order_items.platform" unless grain == "sku"
      columns << "ec_stores.store_name" if grain == "store"
      columns
    end

    def order_columns
      columns = ["period_start ASC", "sku_code ASC"]
      columns << "platform ASC" unless grain == "sku"
      columns << "store_name ASC" if grain == "store"
      columns
    end

    def sales_case
      "CASE WHEN ec_orders.order_status = 'returned' THEN 0 ELSE ec_order_items.quantity END"
    end

    def return_case
      "CASE WHEN ec_orders.order_status = 'returned' THEN ec_order_items.quantity ELSE 0 END"
    end
  end
end
