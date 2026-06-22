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
      purchased = @sku.batches.where(status: %w[received closed]).sum(:received_quantity).to_i
      sold = store_rows.sum { |row| row[:sales_quantity] }
      returned = store_rows.sum { |row| row[:return_quantity] }
      supply = store_rows.sum { |row| row[:supply_quantity] }
      platform_stock = latest_levels.sum(&:quantity)

      {
        received_quantity: purchased,
        sales_quantity: sold,
        return_quantity: returned,
        supply_quantity: supply,
        platform_stock: platform_stock,
        book_stock: purchased - sold + returned - supply,
        available_stock: purchased - sold + returned - platform_stock
      }
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
        orders = order_rows[key] || { sales_quantity: 0 }
        levels = latest_levels.select { |level| key_for(level.platform, level.store_id, level.store_name, level.account_id) == key }

        {
          platform: platform,
          store_id: store_id,
          store_name: store_name,
          account_id: account_id,
          sales_quantity: orders[:sales_quantity].to_i,
          return_quantity: return_rows[key].to_i,
          supply_quantity: supply_quantity_for(platform, key),
          platform_stock: levels.sum(&:quantity),
          latest_synced_at: levels.map(&:synced_at).compact.max
        }
      end.sort_by { |row| [row[:platform].to_s, row[:store_name].to_s] }
    end

    def order_rows
      @order_rows ||= begin
        rows = Hash.new { |hash, key| hash[key] = { sales_quantity: 0 } }
        condition_sql = order_item_match_sql
        return rows if condition_sql.blank?

        Ec::OrderItem
          .joins(:order, :store)
          .where(condition_sql)
          .where.not(ec_orders: { order_status: "cancelled" })
          .select(
            "ec_order_items.platform",
            "ec_order_items.store_id",
            "ec_stores.store_name",
            "CASE WHEN ec_order_items.platform = 'wb' THEN ec_stores.wb_raw_account_id ELSE ec_stores.ozon_raw_account_id END AS account_id",
            "SUM(CASE WHEN ec_orders.order_status = 'returned' THEN 0 ELSE ec_order_items.quantity END) AS sales_quantity"
          )
          .group("ec_order_items.platform", "ec_order_items.store_id", "ec_stores.store_name", "ec_stores.wb_raw_account_id", "ec_stores.ozon_raw_account_id")
          .each do |row|
            rows[key_for(row.platform, row.store_id, row.store_name, row.account_id)] = {
              sales_quantity: row.sales_quantity.to_i
            }
          end

        rows
      end
    end

    def order_item_match_sql
      predicates = ["ec_order_items.sku_code = #{ActiveRecord::Base.connection.quote(@sku.sku_code)}"]
      @sku.sku_products.each do |product|
        ids = [product.product_id, product.platform_sku_id, product.offer_id].compact_blank.uniq
        next if ids.empty?

        quoted_ids = ids.map { |value| ActiveRecord::Base.connection.quote(value.to_s) }.join(", ")
        predicates << ActiveRecord::Base.sanitize_sql_array(
          [
            "(ec_order_items.platform = ? AND ec_order_items.store_id = ? AND (ec_order_items.platform_sku_id IN (#{quoted_ids}) OR ec_order_items.offer_id IN (#{quoted_ids})))",
            product.platform,
            product.store_id
          ]
        )
      end

      predicates.join(" OR ")
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

    def key_for(platform, store_id, store_name, account_id)
      [platform.to_s, store_id&.to_i, store_name.to_s, account_id&.to_i]
    end
  end
end
