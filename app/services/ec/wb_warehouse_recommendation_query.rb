module Ec
  class WbWarehouseRecommendationQuery
    DEFAULT_TARGET_DAYS = 28
    MAX_TARGET_DAYS = 180
    FBO_WAREHOUSE_TYPE = "Склад WB".freeze
    EXCLUDED_TRANSIT_WAREHOUSE_NAMES = [
      "В пути возвраты на склад WB",
      "В пути до получателей"
    ].freeze

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
      sales = sales_by_sku_and_warehouse(products)
      inventory = inventory_by_sku(products.map(&:sku_code).uniq)
      fbs_available = fbs_available_by_sku(products)
      rows = build_rows(products, sales, inventory, fbs_available)

      {
        store: store,
        from_date: from_date,
        to_date: to_date,
        target_days: target_days,
        query: query,
        rows: rows,
        cluster_rows: build_cluster_rows(rows),
        summary: summary(rows, sales),
        inventory_synced_at: latest_inventory_synced_at(products.map(&:sku_code).uniq)
      }
    end

    private

    attr_reader :store, :from_date, :to_date, :time_zone, :target_days, :query, :operator_id, :sku_codes

    def scoped_products
      scope = Ec::SkuProduct
        .includes(:sku)
        .where(store_id: store.id, platform: "wb")
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

    def sales_by_sku_and_warehouse(products)
      product_ids = products.map(&:id)
      return [] if product_ids.empty?

      Ec::OrderItem
        .joins(:order, :fulfillment)
        .joins(order_item_sku_product_join_sql)
        .where(ec_order_items: { platform: "wb", store_id: store.id })
        .where(ec_orders: { ordered_at: user_date_range })
        .where(ec_order_fulfillments: { fulfillment_type: "fbw" })
        .where(ec_sku_products: { id: product_ids })
        .where.not(ec_orders: { order_status: %w[cancelled returned] })
        .group("ec_sku_products.sku_code", "ec_order_fulfillments.cluster_to")
        .sum("ec_order_items.quantity")
        .map do |(sku_code, cluster_name), quantity|
          {
            sku_code: sku_code,
            warehouse_name: nil,
            warehouse_id: nil,
            cluster_name: cluster_name,
            match_type: :fulfillment_cluster,
            quantity: quantity.to_i
          }
        end
    end

    def inventory_by_sku(sku_codes)
      return {} if sku_codes.empty?

      Ec::SkuInventoryLevel
        .where(
          store_id: store.id,
          platform: "wb",
          fulfillment_type: %w[fbw inbound],
          is_latest: true,
          sku_code: sku_codes
        )
        .group_by(&:sku_code)
    end

    def fbs_available_by_sku(products)
      products.group_by(&:sku_code).transform_values do |sku_products|
        sku_products.first.sku.inventory_overview.dig(:summary, :available_stock).to_i
      end
    end

    def build_rows(products, sales, inventory, fbs_available)
      sales_by_sku = sales.group_by { |row| row[:sku_code] }

      products.group_by(&:sku_code).map do |sku_code, sku_products|
        sku_inventory = Array(inventory[sku_code])
        warehouse_rows = merge_warehouse_rows(
          Array(sales_by_sku[sku_code]),
          inventory_rows(sku_inventory.select { |level| level.fulfillment_type == "fbw" })
        )
        clusters = build_clusters(warehouse_rows)
        total_sales = clusters.sum { |cluster| cluster[:sales_quantity] }
        total_available = clusters.sum { |cluster| cluster[:available] }
        total_inbound = sku_inventory.select { |level| level.fulfillment_type == "inbound" }.sum(&:quantity)
        daily_sales = daily_average(total_sales)

        {
          sku_code: sku_code,
          product_name: product_name(sku_products),
          offer_ids: sku_products.filter_map { |product| product.offer_id.presence }.uniq,
          platform_sku_ids: sku_products.map(&:product_id).filter(&:present?).uniq,
          fbs_available: fbs_available.fetch(sku_code, 0).to_i,
          status: stock_status(daily_sales, total_available),
          sales_quantity: total_sales,
          daily_sales: daily_sales,
          days_of_stock: days_of_stock(total_available, daily_sales),
          available: total_available,
          reserved: nil,
          inbound: total_inbound,
          distribution_gap: clusters.sum { |cluster| cluster[:distribution_gap] },
          recommended: recommended_quantity(daily_sales, total_available, total_inbound),
          clusters: clusters
        }
      end.sort_by { |row| [-row[:recommended], -row[:sales_quantity], row[:sku_code]] }
    end

    def inventory_rows(levels)
      levels.flat_map do |level|
        Array(level.warehouse_breakdown).filter_map do |warehouse|
          original_name = warehouse_value(warehouse, :warehouse_name).to_s
          next if original_name.blank?
          next if EXCLUDED_TRANSIT_WAREHOUSE_NAMES.include?(original_name)

          resolution = warehouse_resolution(original_name)
          {
            warehouse_name: resolution&.warehouse_name || original_name,
            warehouse_id: resolution&.warehouse_id || warehouse_value(warehouse, :warehouse_id),
            cluster_name: resolution&.region_name || warehouse_value(warehouse, :cluster_name).presence,
            match_type: resolution&.match_type,
            quantity: 0,
            available: warehouse_value(warehouse, :quantity).to_i
          }
        end
      end
    end

    def merge_warehouse_rows(sales, inventory)
      merged = {}
      (sales + inventory).each do |row|
        key = [row[:cluster_name], row[:warehouse_id] || normalized_name(row[:warehouse_name])]
        target = merged[key] ||= {
          warehouse_name: row[:warehouse_name],
          warehouse_id: row[:warehouse_id],
          cluster_name: row[:cluster_name],
          sales_quantity: 0,
          available: 0
        }
        target[:sales_quantity] += row[:quantity].to_i
        target[:available] += row[:available].to_i
      end
      merged.values
    end

    def build_clusters(warehouses)
      warehouses.group_by { |row| row[:cluster_name].presence }.map do |cluster_name, cluster_warehouses|
        sales_quantity = cluster_warehouses.sum { |row| row[:sales_quantity] }
        available = cluster_warehouses.sum { |row| row[:available] }
        daily_sales = daily_average(sales_quantity)

        {
          cluster_name: cluster_name,
          status: stock_status(daily_sales, available),
          sales_quantity: sales_quantity,
          daily_sales: daily_sales,
          days_of_stock: days_of_stock(available, daily_sales),
          available: available,
          reserved: nil,
          inbound: nil,
          distribution_gap: recommended_quantity(daily_sales, available),
          receiving_warehouse_count: warehouse_count_for_cluster(cluster_name),
          warehouses: cluster_warehouses
            .select { |row| row[:warehouse_name].present? }
            .sort_by { |row| [-row[:available], row[:warehouse_name].to_s] }
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
        available = products.sum { |product| product[:available] }
        daily_sales = daily_average(sales_quantity)

        {
          cluster_name: cluster_name,
          product_count: products.size,
          receiving_warehouse_count: warehouse_count_for_cluster(cluster_name),
          status: stock_status(daily_sales, available),
          sales_quantity: sales_quantity,
          daily_sales: daily_sales,
          days_of_stock: days_of_stock(available, daily_sales),
          available: available,
          reserved: nil,
          inbound: nil,
          distribution_gap: products.sum { |product| product[:distribution_gap] },
          products: products.sort_by { |product| [-product[:distribution_gap], -product[:sales_quantity], product[:sku_code]] }
        }
      end.sort_by { |row| [-row[:distribution_gap], -row[:sales_quantity], row[:cluster_name].to_s] }
    end

    def summary(rows, sales)
      total_sales = sales.sum { |row| row[:quantity] }
      mapped_sales = sales.sum { |row| row[:cluster_name].present? ? row[:quantity] : 0 }
      {
        sku_count: rows.size,
        shortage_count: rows.count { |row| row[:status] == :shortage },
        available: rows.sum { |row| row[:available] },
        inbound: rows.sum { |row| row[:inbound] },
        recommended: rows.sum { |row| row[:recommended] },
        mapped_orders: mapped_sales,
        total_orders: total_sales,
        mapping_coverage: total_sales.positive? ? (mapped_sales.to_d / total_sales * 100).round(1) : 100.to_d
      }
    end

    def warehouse_resolution(name)
      @warehouse_resolutions ||= {}
      @warehouse_resolutions[name.to_s] ||= RawWb::WarehouseNameResolver.resolve(
        account_id: store.wb_raw_account_id,
        warehouse_name: name,
        on: to_date
      )
    end

    def warehouse_count_for_cluster(cluster_name)
      return 0 if cluster_name.blank?

      @warehouse_counts ||= RawWb::WarehouseRegion
        .where(account_id: store.wb_raw_account_id)
        .group(:region_name)
        .count
      @warehouse_counts.fetch(cluster_name, 0)
    end

    def product_name(products)
      products.first.sku&.product_name.presence ||
        products.filter_map { |product| product.product_name.presence }.first ||
        products.first.sku_code
    end

    def normalized_name(name)
      RawWb::WarehouseRegion.normalize_warehouse_name(name)
    end

    def order_item_sku_product_join_sql
      <<~SQL.squish
        INNER JOIN ec_sku_products
          ON ec_sku_products.store_id = ec_order_items.store_id
         AND ec_sku_products.platform = ec_order_items.platform
         AND ec_sku_products.product_id = ec_order_items.platform_sku_id
      SQL
    end

    def daily_average(quantity)
      (quantity.to_d / period_days).round(2)
    end

    def days_of_stock(available, daily_sales)
      return nil unless daily_sales.positive?

      (available.to_d / daily_sales).round(0).to_i
    end

    def recommended_quantity(daily_sales, available, inbound = 0)
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
      Ec::SkuInventoryLevel.where(
        store_id: store.id,
        platform: "wb",
        fulfillment_type: %w[fbw inbound],
        is_latest: true,
        sku_code: sku_codes
      ).maximum(:synced_at)
    end

    def warehouse_value(row, key)
      row[key] || row[key.to_s]
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
  end
end
