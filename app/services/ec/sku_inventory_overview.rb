module Ec
  class SkuInventoryOverview
    def initialize(sku)
      @sku = sku
    end

    def call
      latest_levels = @sku.inventory_levels.latest.includes(:store).order(:platform, :store_name, :fulfillment_type).to_a
      store_rows = build_store_rows(latest_levels)

      {
        summary: summary(store_rows, latest_levels),
        store_rows: store_rows,
        latest_levels: latest_levels
      }
    end

    private

    def summary(store_rows, latest_levels)
      sold = store_rows.sum { |row| row[:sales_quantity] }
      returned = store_rows.sum { |row| row[:return_quantity] }
      supply = store_rows.sum { |row| row[:supply_quantity] }
      platform_stock = latest_levels.sum(&:quantity)
      platform_inbound_stock = latest_levels
        .select { |level| level.fulfillment_type.to_s == "inbound" }
        .sum(&:quantity)
      fbo_fbw_stock = latest_levels
        .select { |level| level.fulfillment_type.to_s.in?(%w[fbo fbw]) }
        .sum(&:quantity)
      platform_reserved_stock = fbo_fbw_stock + platform_inbound_stock
      batches = batch_summary
      received = batches[:received_quantity]

      {
        purchase_quantity: batches[:purchase_quantity],
        adjustment_quantity: batches[:adjustment_quantity],
        received_quantity: received,
        sales_quantity: sold,
        return_quantity: returned,
        supply_quantity: supply,
        platform_stock: platform_stock,
        platform_inbound_stock: platform_inbound_stock,
        fbo_fbw_stock: fbo_fbw_stock,
        book_stock: received - sold + returned,
        available_stock: received - sold + returned - platform_reserved_stock
      }
    end

    def batch_summary
      @batch_summary ||= begin
        rows = @sku.batches
          .where(status: %w[received closed])
          .group(:batch_type)
          .sum(:received_quantity)

        purchase_quantity = rows.fetch("normal", 0).to_i
        adjustment_quantity = rows.except("normal").values.sum(&:to_i)

        {
          purchase_quantity: purchase_quantity,
          adjustment_quantity: adjustment_quantity,
          received_quantity: purchase_quantity + adjustment_quantity
        }
      end
    end

    def build_store_rows(latest_levels)
      store_keys = (
        order_rows.keys +
        return_rows.keys +
        wb_supply_rows.keys +
        ozon_supply_rows.keys +
        latest_levels.map { |level| key_for(level.platform, level.store_id, level.store_name, level.account_id) }
      ).uniq

      store_keys.map do |key|
        platform, store_id, store_name, account_id = key
        orders = order_rows[key] || { sales_quantity: 0, order_status_counts: empty_order_status_counts }
        levels = latest_levels.select { |level| key_for(level.platform, level.store_id, level.store_name, level.account_id) == key }

        {
          platform: platform,
          store_id: store_id,
          store_name: store_name,
          account_id: account_id,
          sales_quantity: orders[:sales_quantity].to_i,
          order_status_counts: empty_order_status_counts.merge(orders[:order_status_counts] || {}),
          return_quantity: return_rows[key].to_i,
          supply_quantity: supply_quantity_for(platform, key),
          platform_stock: levels.sum(&:quantity),
          latest_synced_at: levels.map(&:synced_at).compact.max
        }
      end.sort_by { |row| [row[:platform].to_s, row[:store_name].to_s] }
    end

    def order_rows
      @order_rows ||= begin
        rows = Hash.new { |hash, key| hash[key] = { sales_quantity: 0, order_status_counts: empty_order_status_counts } }

        Ec::OrderItem
          .joins(:order, :store)
          .joins(order_item_sku_product_join_sql)
          .where(ec_sku_products: { sku_code: @sku.sku_code })
          .where.not(ec_orders: { order_status: "cancelled" })
          .select(
            "ec_order_items.platform",
            "ec_order_items.store_id",
            "ec_stores.store_name",
            "ec_orders.order_status",
            "CASE WHEN ec_order_items.platform = 'wb' THEN ec_stores.wb_raw_account_id ELSE ec_stores.ozon_raw_account_id END AS account_id",
            "SUM(CASE WHEN ec_orders.order_status = 'returned' THEN 0 ELSE ec_order_items.quantity END) AS sales_quantity",
            "SUM(ec_order_items.quantity) AS status_quantity"
          )
          .group("ec_order_items.platform", "ec_order_items.store_id", "ec_stores.store_name", "ec_orders.order_status", "ec_stores.wb_raw_account_id", "ec_stores.ozon_raw_account_id")
          .each do |row|
            key = key_for(row.platform, row.store_id, row.store_name, row.account_id)
            status_key = bucket_for_order_status(row.order_status)
            current = rows[key]
            current[:sales_quantity] += row.sales_quantity.to_i
            current[:order_status_counts][status_key] += row.status_quantity.to_i if status_key.present?
          end

        rows
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

    def return_rows
      @return_rows ||= begin
        rows = Hash.new(0)
        merge_return_rows(rows, ozon_return_rows)
        merge_return_rows(rows, wb_return_rows)
        rows
      end
    end

    def ozon_return_rows
      rows = {}

      RawOzon::Return
        .joins("LEFT JOIN ec_stores ON ec_stores.ozon_raw_account_id = raw_ozon_returns.account_id AND ec_stores.platform = 'ozon'")
        .where(
          <<~SQL.squish,
            EXISTS (
              SELECT 1
              FROM ec_sku_products
              WHERE ec_sku_products.store_id = ec_stores.id
                AND ec_sku_products.platform = 'ozon'
                AND ec_sku_products.sku_code = ?
                AND (
                  raw_ozon_returns.offer_id = ec_sku_products.offer_id
                  OR raw_ozon_returns.ozon_sku::text = ec_sku_products.platform_sku_id
                )
            )
            AND NOT EXISTS (
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
          @sku.sku_code
        )
        .select(
          "raw_ozon_returns.account_id",
          "ec_stores.id AS store_id",
          "ec_stores.store_name",
          "SUM(COALESCE(raw_ozon_returns.quantity, 1)) AS return_quantity"
        )
        .group("raw_ozon_returns.account_id", "ec_stores.id", "ec_stores.store_name")
        .each do |row|
          rows[key_for("ozon", row.store_id, row.store_name || "Account##{row.account_id}", row.account_id)] = row.return_quantity.to_i
        end

      rows
    end

    def wb_return_rows
      rows = {}

      RawWb::GoodsReturn
        .joins("LEFT JOIN ec_stores ON ec_stores.wb_raw_account_id = raw_wb_goods_returns.account_id AND ec_stores.platform = 'wb'")
        .where(
          <<~SQL.squish,
            EXISTS (
              SELECT 1
              FROM ec_sku_products
              WHERE ec_sku_products.store_id = ec_stores.id
                AND ec_sku_products.platform = 'wb'
                AND ec_sku_products.sku_code = ?
                AND raw_wb_goods_returns.nm_id::text = ec_sku_products.product_id
            )
          SQL
          @sku.sku_code
        )
        .select(
          "raw_wb_goods_returns.account_id",
          "ec_stores.id AS store_id",
          "ec_stores.store_name",
          "COUNT(*) AS return_quantity"
        )
        .group("raw_wb_goods_returns.account_id", "ec_stores.id", "ec_stores.store_name")
        .each do |row|
          rows[key_for("wb", row.store_id, row.store_name || "Account##{row.account_id}", row.account_id)] = row.return_quantity.to_i
        end

      rows
    end

    def merge_return_rows(target, source)
      source.each do |key, quantity|
        target[key] += quantity.to_i
      end
    end

    def wb_supply_rows
      @wb_supply_rows ||= begin
        rows = Hash.new(0)
        nm_ids = @sku.sku_products.where(platform: "wb").pluck(:product_id)

        if nm_ids.any?
          RawWb::SupplyItem
            .joins("LEFT JOIN ec_stores ON ec_stores.wb_raw_account_id = raw_wb_supply_items.account_id AND ec_stores.platform = 'wb'")
            .where(nm_id: nm_ids)
            .select(
              "raw_wb_supply_items.account_id",
              "ec_stores.id AS store_id",
              "ec_stores.store_name",
              "SUM(raw_wb_supply_items.accepted_qty) AS supply_quantity"
            )
            .group("raw_wb_supply_items.account_id", "ec_stores.id", "ec_stores.store_name")
            .each do |row|
              rows[key_for("wb", row.store_id, row.store_name || "Account##{row.account_id}", row.account_id)] = row.supply_quantity.to_i
            end
          end

        rows
      end
    end

    def ozon_supply_rows
      @ozon_supply_rows ||= begin
        rows = Hash.new(0)
        sku_products_by_account.each do |account_id, products|
          ozon_skus = products.map(&:platform_sku_id).compact
          next if ozon_skus.empty?

          store = products.first.store
          quantity = RawOzon::SupplyOrder.where(account_id: account_id, status: "COMPLETED").sum do |order|
            ozon_skus.sum { |ozon_sku| order.items.to_h[ozon_sku].to_i }
          end
          rows[key_for("ozon", store.id, store.store_name, account_id)] = quantity
        end

        rows
      end
    end

    def sku_products_by_account
      @sku.sku_products.includes(:store).where(platform: "ozon").group_by { |product| product.store.ozon_raw_account_id }
    end

    def supply_quantity_for(platform, key)
      platform == "wb" ? wb_supply_rows[key].to_i : ozon_supply_rows[key].to_i
    end

    def empty_order_status_counts
      {
        "pending" => 0,
        "processing" => 0,
        "shipping" => 0,
        "signed" => 0
      }
    end

    def bucket_for_order_status(order_status)
      case order_status.to_s
      when "pending" then "pending"
      when "processing" then "processing"
      when "shipped" then "shipping"
      when "delivered" then "signed"
      else nil
      end
    end

    def key_for(platform, store_id, store_name, account_id)
      [platform.to_s, store_id&.to_i, store_name.to_s, account_id&.to_i]
    end
  end
end
