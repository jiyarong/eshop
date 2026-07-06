module Ec
  class InventoryTurnoverMetricsQuery
    def initialize(sku_codes:, date_to:, time_zone:)
      @sku_codes = Array(sku_codes).map(&:to_s).map(&:upcase).uniq
      @date_to = date_to
      @time_zone = time_zone
    end

    def call
      return {} if @sku_codes.empty?

      velocity_metrics = Ec::InventoryVelocityMetricsQuery.new(
        sku_codes: @sku_codes,
        date_to: @date_to,
        time_zone: @time_zone
      ).call

      received_quantities = received_quantities_by_sku
      procurement_quantities = procurement_quantities_by_sku
      sales_quantities = sales_quantities_by_sku
      returned_quantities = returned_quantities_by_sku

      @sku_codes.index_with do |sku_code|
        daily_sales_velocity = velocity_metrics.dig(sku_code, :daily_sales_velocity)
        book_stock = received_quantities.fetch(sku_code, 0) - sales_quantities.fetch(sku_code, 0) + returned_quantities.fetch(sku_code, 0)
        procurement_stock = procurement_quantities.fetch(sku_code, 0)

        {
          book_stock: book_stock,
          procurement_stock: procurement_stock,
          daily_sales_velocity: daily_sales_velocity,
          turnover_days: daily_sales_velocity.to_d.positive? ? (book_stock.to_d / daily_sales_velocity.to_d) : nil,
          turnover_days_with_procurement: daily_sales_velocity.to_d.positive? ? ((book_stock + procurement_stock).to_d / daily_sales_velocity.to_d) : nil
        }
      end
    end

    private

    def received_quantities_by_sku
      Ec::SkuBatch
        .where(sku_code: @sku_codes, status: %w[received closed])
        .group(:sku_code)
        .sum(:received_quantity)
        .transform_keys(&:to_s)
        .transform_values(&:to_i)
    end

    def procurement_quantities_by_sku
      Ec::SkuBatch
        .where(sku_code: @sku_codes, status: %w[draft ordered in_transit], batch_type: :normal)
        .group(:sku_code)
        .sum(:purchased_quantity)
        .transform_keys(&:to_s)
        .transform_values(&:to_i)
    end

    def sales_quantities_by_sku
      Ec::OrderItem
        .joins(:order)
        .joins(order_item_sku_product_join_sql)
        .where(ec_sku_products: { sku_code: @sku_codes })
        .where.not(ec_orders: { order_status: "cancelled" })
        .group("ec_sku_products.sku_code")
        .sum(Arel.sql("CASE WHEN ec_orders.order_status = 'returned' THEN 0 ELSE ec_order_items.quantity END"))
        .transform_keys(&:to_s)
        .transform_values(&:to_i)
    end

    def returned_quantities_by_sku
      merge_quantities_by_sku(ozon_return_quantities_by_sku, wb_return_quantities_by_sku)
    end

    def ozon_return_quantities_by_sku
      RawOzon::Return
        .joins("INNER JOIN ec_stores ON ec_stores.ozon_raw_account_id = raw_ozon_returns.account_id AND ec_stores.platform = 'ozon'")
        .joins(ozon_return_sku_product_join_sql)
        .where(ec_sku_products: { sku_code: @sku_codes })
        .where(
          <<~SQL.squish
            NOT EXISTS (
              SELECT 1
              FROM ec_orders
              WHERE ec_orders.platform = 'ozon'
                AND ec_orders.store_id = ec_stores.id
                AND ec_orders.order_status = 'cancelled'
                AND (
                  ec_orders.external_order_number = raw_ozon_returns.posting_number
                  OR ec_orders.external_order_number = raw_ozon_returns.order_number
                  OR ec_orders.external_order_id = raw_ozon_returns.order_id::text
                )
            )
          SQL
        )
        .group("ec_sku_products.sku_code")
        .sum(Arel.sql("COALESCE(raw_ozon_returns.quantity, 1)"))
        .transform_keys(&:to_s)
        .transform_values(&:to_i)
    end

    def wb_return_quantities_by_sku
      RawWb::GoodsReturn
        .joins("INNER JOIN ec_stores ON ec_stores.wb_raw_account_id = raw_wb_goods_returns.account_id AND ec_stores.platform = 'wb'")
        .joins(wb_return_sku_product_join_sql)
        .where(ec_sku_products: { sku_code: @sku_codes })
        .group("ec_sku_products.sku_code")
        .count
        .transform_keys(&:to_s)
        .transform_values(&:to_i)
    end

    def merge_quantities_by_sku(*sources)
      sources.each_with_object(Hash.new(0)) do |source, merged|
        source.each do |sku_code, quantity|
          merged[sku_code.to_s] += quantity.to_i
        end
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

    def ozon_return_sku_product_join_sql
      <<~SQL.squish
        INNER JOIN ec_sku_products
          ON ec_sku_products.store_id = ec_stores.id
         AND ec_sku_products.platform = 'ozon'
         AND (
           raw_ozon_returns.offer_id = ec_sku_products.offer_id
           OR raw_ozon_returns.ozon_sku::text = ec_sku_products.platform_sku_id
         )
      SQL
    end

    def wb_return_sku_product_join_sql
      <<~SQL.squish
        INNER JOIN ec_sku_products
          ON ec_sku_products.store_id = ec_stores.id
         AND ec_sku_products.platform = 'wb'
         AND raw_wb_goods_returns.nm_id::text = ec_sku_products.product_id
      SQL
    end
  end
end
