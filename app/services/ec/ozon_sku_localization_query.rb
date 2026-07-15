module Ec
  class OzonSkuLocalizationQuery
    DEFAULT_LIMIT = 50
    MAX_LIMIT = 200

    def initialize(from_date:, to_date:, time_zone:, sku_product_ids:, store_id: nil, sku_code: nil, query: nil, fulfillment_type: nil, order_status: nil, sort: nil, limit: nil, offset: nil)
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @time_zone = time_zone
      @sku_product_ids = Array(sku_product_ids)
      @store_id = store_id.presence
      @sku_code = sku_code.to_s.upcase.presence
      @query = query.to_s.strip.presence
      @fulfillment_type = fulfillment_type.presence
      @order_statuses = Array(order_status).filter_map { |status| status.to_s.presence }
      @sort = sort.presence_in(%w[total_quantity localization_rate non_local_quantity local_quantity sku_code]) || "total_quantity"
      @limit = bounded_integer(limit, DEFAULT_LIMIT, MAX_LIMIT)
      @offset = [offset.to_i, 0].max
    end

    def call
      rows = localization_rows
      {
        from_date: from_date,
        to_date: to_date,
        time_zone: time_zone.tzinfo.name,
        filters: filters_payload,
        summary: summary_payload,
        items: rows,
        total_sku_count: base_scope.distinct.count("ec_sku_products.sku_code")
      }
    end

    private

    attr_reader :from_date, :to_date, :time_zone, :sku_product_ids, :store_id, :sku_code, :query, :fulfillment_type, :order_statuses, :sort, :limit, :offset

    def base_scope
      scope = Ec::OrderItem
        .joins(:order, :fulfillment)
        .joins(order_item_sku_product_join_sql)
        .joins("LEFT JOIN ec_skus ON ec_skus.sku_code = ec_sku_products.sku_code")
        .where(ec_order_items: { platform: "ozon" })
        .where(ec_orders: { ordered_at: user_date_range })
        .where(ec_sku_products: { id: sku_product_ids })
        .where.not(ec_order_fulfillments: { cluster_from: nil })
        .where.not(ec_order_fulfillments: { cluster_to: nil })

      scope = scope.where(ec_order_items: { store_id: store_id }) if store_id.present?
      scope = scope.where(ec_sku_products: { sku_code: sku_code }) if sku_code.present?
      scope = scope.where(ec_order_fulfillments: { fulfillment_type: fulfillment_type }) if fulfillment_type.present?
      scope = scope.where(ec_orders: { order_status: order_statuses }) if order_statuses.any?
      scope = apply_query(scope)
      scope
    end

    def apply_query(scope)
      return scope if query.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
      scope.where(
        "LOWER(ec_sku_products.sku_code) LIKE :pattern OR LOWER(ec_skus.product_name) LIKE :pattern OR LOWER(ec_sku_products.product_name) LIKE :pattern OR LOWER(ec_order_items.product_name_source) LIKE :pattern",
        pattern: pattern
      )
    end

    def summary_payload
      total = base_scope.sum("ec_order_items.quantity").to_i
      local = base_scope.where("ec_order_fulfillments.cluster_from = ec_order_fulfillments.cluster_to").sum("ec_order_items.quantity").to_i
      {
        total_quantity: total,
        local_quantity: local,
        non_local_quantity: total - local,
        localization_rate: ratio(local, total),
        order_count: base_scope.distinct.count("ec_orders.id")
      }
    end

    def localization_rows
      relation = base_scope
        .select(select_sql)
        .group("ec_sku_products.sku_code")
        .order(Arel.sql(order_sql))
        .limit(limit)
        .offset(offset)

      relation.map do |row|
        total = row.total_quantity.to_i
        local = row.local_quantity.to_i
        {
          sku_code: row.sku_code,
          product_name: row.product_name,
          total_quantity: total,
          local_quantity: local,
          non_local_quantity: total - local,
          localization_rate: ratio(local, total),
          order_count: row.order_count.to_i,
          fulfillment_types: row.fulfillment_types.to_s,
          local_cluster_count: row.local_cluster_count.to_i,
          non_local_cluster_count: row.non_local_cluster_count.to_i
        }
      end
    end

    def select_sql
      [
        "ec_sku_products.sku_code AS sku_code",
        "MAX(COALESCE(ec_skus.product_name, ec_sku_products.product_name, ec_order_items.product_name_source)) AS product_name",
        "SUM(ec_order_items.quantity) AS total_quantity",
        "SUM(CASE WHEN ec_order_fulfillments.cluster_from = ec_order_fulfillments.cluster_to THEN ec_order_items.quantity ELSE 0 END) AS local_quantity",
        "COUNT(DISTINCT ec_orders.id) AS order_count",
        "STRING_AGG(DISTINCT ec_order_fulfillments.fulfillment_type, ' / ') AS fulfillment_types",
        "COUNT(DISTINCT CASE WHEN ec_order_fulfillments.cluster_from = ec_order_fulfillments.cluster_to THEN ec_order_fulfillments.cluster_from END) AS local_cluster_count",
        "COUNT(DISTINCT CASE WHEN ec_order_fulfillments.cluster_from <> ec_order_fulfillments.cluster_to THEN ec_order_fulfillments.cluster_to END) AS non_local_cluster_count"
      ].join(", ")
    end

    def order_sql
      case sort
      when "localization_rate"
        "CASE WHEN SUM(ec_order_items.quantity) = 0 THEN 0 ELSE SUM(CASE WHEN ec_order_fulfillments.cluster_from = ec_order_fulfillments.cluster_to THEN ec_order_items.quantity ELSE 0 END)::decimal / SUM(ec_order_items.quantity) END DESC, total_quantity DESC"
      when "non_local_quantity"
        "(SUM(ec_order_items.quantity) - SUM(CASE WHEN ec_order_fulfillments.cluster_from = ec_order_fulfillments.cluster_to THEN ec_order_items.quantity ELSE 0 END)) DESC"
      when "local_quantity"
        "local_quantity DESC"
      when "sku_code"
        "sku_code ASC"
      else
        "total_quantity DESC"
      end
    end

    def filters_payload
      {
        store_id: store_id,
        sku_code: sku_code,
        query: query,
        fulfillment_type: fulfillment_type,
        order_status: order_statuses,
        sort: sort
      }
    end

    def order_item_sku_product_join_sql
      <<~SQL.squish
        INNER JOIN ec_sku_products
          ON ec_sku_products.store_id = ec_order_items.store_id
         AND ec_sku_products.platform = ec_order_items.platform
         AND ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id
      SQL
    end

    def user_date_range
      time_zone.local(from_date.year, from_date.month, from_date.day).beginning_of_day..
        time_zone.local(to_date.year, to_date.month, to_date.day).end_of_day
    end

    def ratio(numerator, denominator)
      return nil if denominator.to_i.zero?

      (numerator.to_d / denominator.to_d).round(4)
    end

    def bounded_integer(value, default, max)
      integer = value.to_i
      integer = default unless integer.positive?
      [integer, max].min
    end
  end
end
