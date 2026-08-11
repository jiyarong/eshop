module Ec
  class OzonWarehouseRecommendationQuery
    DEFAULT_TARGET_DAYS = 28
    MAX_TARGET_DAYS = 180

    def initialize(store:, from_date:, to_date:, time_zone:, target_days: nil, query: nil, operator_id: nil, sku_codes: nil)
      @store = store
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @time_zone = time_zone
      @target_days = bounded_target_days(target_days)
      @query = query.to_s.strip.presence
      @operator_id = operator_id
      @sku_codes = sku_codes&.map(&:to_s)&.uniq
    end

    def call
      products = scoped_products.to_a
      sku_codes = products.map(&:sku_code).uniq
      sales = sales_by_sku_and_cluster(products.map(&:id))
      inventory = inventory_by_sku(sku_codes)
      receiving_warehouses = receiving_warehouses_by_cluster
      fbs_available = fbs_available_by_sku(products)
      rows = build_rows(products, sales, inventory, receiving_warehouses, fbs_available)

      {
        store: store,
        from_date: from_date,
        to_date: to_date,
        target_days: target_days,
        query: query,
        rows: rows,
        cluster_rows: build_cluster_rows(rows),
        summary: summary(rows),
        inventory_synced_at: latest_inventory_synced_at(sku_codes)
      }
    end

    private

    attr_reader :store, :from_date, :to_date, :time_zone, :target_days, :query, :operator_id, :sku_codes

    def scoped_products
      scope = Ec::SkuProduct
        .includes(:sku)
        .where(store_id: store.id, platform: "ozon")
        .order(:sku_code, :id)
      scope = scope.where(id: operator_sku_product_ids) if operator_id.present?
      scope = scope.where(sku_code: sku_codes) unless sku_codes.nil?
      return scope if query.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
      scope.where(
        "LOWER(ec_sku_products.sku_code) LIKE :pattern OR LOWER(ec_sku_products.product_name) LIKE :pattern OR LOWER(ec_sku_products.offer_id) LIKE :pattern",
        pattern: pattern
      )
    end

    def operator_sku_product_ids
      Ec::SkuProductOperator
        .where(user_id: operator_id, role: Ec::SkuProductOperator.roles.fetch("operator"))
        .select(:sku_product_id)
    end

    def sales_by_sku_and_cluster(sku_product_ids)
      return {} if sku_product_ids.empty?

      Ec::OrderItem
        .joins(:order, :fulfillment)
        .joins(order_item_sku_product_join_sql)
        .where(ec_order_items: { platform: "ozon", store_id: store.id })
        .where(ec_orders: { ordered_at: user_date_range })
        .where(ec_sku_products: { id: sku_product_ids })
        .where.not(ec_orders: { order_status: %w[cancelled returned] })
        .where.not(ec_order_fulfillments: { cluster_to: nil })
        .group("ec_sku_products.sku_code", "ec_order_fulfillments.cluster_to")
        .sum("ec_order_items.quantity")
    end

    def inventory_by_sku(sku_codes)
      return {} if sku_codes.empty?

      Ec::SkuInventoryLevel
        .where(store_id: store.id, platform: "ozon", fulfillment_type: "fbo", is_latest: true, sku_code: sku_codes)
        .group_by(&:sku_code)
    end

    def receiving_warehouses_by_cluster
      RawOzon::WarehouseCluster
        .where(account_id: store.ozon_raw_account_id)
        .where.not(cluster_name: [nil, ""])
        .group_by(&:cluster_name)
    end

    def fbs_available_by_sku(products)
      products.group_by(&:sku_code).transform_values do |sku_products|
        sku_products.first.sku.inventory_overview.dig(:summary, :available_stock).to_i
      end
    end

    def build_rows(products, sales, inventory, receiving_warehouses, fbs_available)
      products.group_by(&:sku_code).map do |sku_code, sku_products|
        cluster_sales = sales.each_with_object({}) do |((row_sku_code, cluster), quantity), result|
          result[cluster] = quantity.to_i if row_sku_code == sku_code
        end
        warehouse_rows = Array(inventory[sku_code]).flat_map { |level| warehouse_rows(level) }
        clusters = build_clusters(cluster_sales, warehouse_rows, receiving_warehouses)
        total_sales = clusters.sum { |cluster| cluster[:sales_quantity] }
        total_available = clusters.sum { |cluster| cluster[:available] }
        total_inbound = clusters.sum { |cluster| cluster[:inbound] }
        daily_sales = daily_average(total_sales)

        {
          sku_code: sku_code,
          product_name: product_name(sku_products),
          offer_ids: sku_products.filter_map { |product| product.offer_id.presence }.uniq,
          platform_sku_ids: sku_products.filter_map { |product| product.platform_sku_id.presence }.uniq,
          fbs_available: fbs_available.fetch(sku_code, 0).to_i,
          status: stock_status(daily_sales, total_available),
          sales_quantity: total_sales,
          daily_sales: daily_sales,
          days_of_stock: days_of_stock(total_available, daily_sales),
          available: total_available,
          reserved: clusters.sum { |cluster| cluster[:reserved] },
          inbound: total_inbound,
          distribution_gap: clusters.sum { |cluster| cluster[:distribution_gap] },
          recommended: recommended_quantity(daily_sales, total_available, total_inbound),
          clusters: clusters
        }
      end.sort_by { |row| [-row[:recommended], -row[:sales_quantity], row[:sku_code]] }
    end

    def build_clusters(cluster_sales, warehouses, receiving_warehouses)
      warehouses_by_cluster = warehouses.group_by { |row| row[:cluster_name].presence }
      (cluster_sales.keys | warehouses_by_cluster.keys).map do |cluster_name|
        cluster_warehouses = Array(warehouses_by_cluster[cluster_name])
        sales_quantity = cluster_sales.fetch(cluster_name, 0).to_i
        daily_sales = daily_average(sales_quantity)
        available = cluster_warehouses.sum { |row| row[:available] }
        inbound = cluster_warehouses.sum { |row| row[:inbound] }

        {
          cluster_name: cluster_name,
          status: stock_status(daily_sales, available),
          sales_quantity: sales_quantity,
          daily_sales: daily_sales,
          days_of_stock: days_of_stock(available, daily_sales),
          available: available,
          reserved: cluster_warehouses.sum { |row| row[:reserved] },
          inbound: inbound,
          distribution_gap: recommended_quantity(daily_sales, available, inbound),
          receiving_warehouse_count: Array(receiving_warehouses[cluster_name]).size,
          warehouses: cluster_warehouses.sort_by { |row| [-row[:available], row[:warehouse_name]] }
        }
      end.sort_by { |row| [-row[:distribution_gap], -row[:sales_quantity], row[:cluster_name].to_s] }
    end

    def build_cluster_rows(rows)
      products_by_cluster = rows.flat_map do |row|
        row[:clusters].map do |cluster|
          cluster.merge(
            sku_code: row[:sku_code],
            product_name: row[:product_name],
            offer_ids: row[:offer_ids],
            fbs_available: row[:fbs_available]
          )
        end
      end.group_by { |row| row[:cluster_name] }

      products_by_cluster.map do |cluster_name, products|
        sales_quantity = products.sum { |product| product[:sales_quantity] }
        daily_sales = daily_average(sales_quantity)
        available = products.sum { |product| product[:available] }

        {
          cluster_name: cluster_name,
          product_count: products.size,
          receiving_warehouse_count: products.map { |product| product[:receiving_warehouse_count] }.max.to_i,
          status: stock_status(daily_sales, available),
          sales_quantity: sales_quantity,
          daily_sales: daily_sales,
          days_of_stock: days_of_stock(available, daily_sales),
          available: available,
          reserved: products.sum { |product| product[:reserved] },
          inbound: products.sum { |product| product[:inbound] },
          distribution_gap: products.sum { |product| product[:distribution_gap] },
          products: products.sort_by { |product| [-product[:distribution_gap], -product[:sales_quantity], product[:sku_code]] }
        }
      end.sort_by { |row| [-row[:distribution_gap], -row[:sales_quantity], row[:cluster_name].to_s] }
    end

    def warehouse_rows(level)
      Array(level.warehouse_breakdown).filter_map do |warehouse|
        name = warehouse_value(warehouse, :warehouse_name).to_s
        next if name.blank?

        {
          warehouse_name: name,
          cluster_name: warehouse_value(warehouse, :cluster_name).to_s.presence,
          available: warehouse_value(warehouse, :quantity).to_i,
          reserved: warehouse_value(warehouse, :reserved).to_i,
          inbound: warehouse_value(warehouse, :promised).to_i
        }
      end
    end

    def summary(rows)
      {
        sku_count: rows.size,
        shortage_count: rows.count { |row| row[:status] == :shortage },
        available: rows.sum { |row| row[:available] },
        inbound: rows.sum { |row| row[:inbound] },
        recommended: rows.sum { |row| row[:recommended] }
      }
    end

    def product_name(products)
      products.first.sku&.product_name.presence || products.filter_map { |product| product.product_name.presence }.first || products.first.sku_code
    end

    def daily_average(quantity)
      (quantity.to_d / period_days).round(2)
    end

    def days_of_stock(available, daily_sales)
      return nil unless daily_sales.positive?

      (available.to_d / daily_sales).round(0).to_i
    end

    def recommended_quantity(daily_sales, available, inbound)
      return 0 unless daily_sales.positive?

      [(daily_sales * target_days).ceil - available - inbound, 0].max
    end

    def stock_status(daily_sales, available)
      return :no_sales unless daily_sales.positive?

      coverage = available.to_d / daily_sales
      return :shortage if coverage < target_days * 0.5
      return :excess if coverage > target_days * 1.5

      :healthy
    end

    def latest_inventory_synced_at(sku_codes)
      return nil if sku_codes.empty?

      Ec::SkuInventoryLevel
        .where(store_id: store.id, platform: "ozon", fulfillment_type: "fbo", is_latest: true, sku_code: sku_codes)
        .maximum(:synced_at)
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

    def period_days
      @period_days ||= (to_date - from_date).to_i + 1
    end

    def bounded_target_days(value)
      days = value.to_i
      days = DEFAULT_TARGET_DAYS unless days.positive?
      [days, MAX_TARGET_DAYS].min
    end

    def warehouse_value(row, key)
      row[key] || row[key.to_s]
    end
  end
end
