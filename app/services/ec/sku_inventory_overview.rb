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
      seller_received_removals = store_rows.sum { |row| row[:ozon_seller_received_removal_quantity] }
      supply = store_rows.sum { |row| row[:supply_quantity] }
      platform_stock = latest_levels.sum(&:quantity)
      platform_inbound_stock = latest_levels
        .select { |level| level.fulfillment_type.to_s == "inbound" }
        .sum(&:quantity)
      fbo_fbw_stock = latest_levels
        .select { |level| level.fulfillment_type.to_s.in?(%w[fbo fbw]) }
        .sum(&:quantity)
      composed = Ec::Inventory::BookLedger.compose(
        ledger, platform_sellable: fbo_fbw_stock, platform_inbound: platform_inbound_stock
      )

      {
        purchase_quantity: ledger[:purchase_quantity],
        adjustment_quantity: ledger[:adjustment_quantity],
        received_quantity: ledger[:received_quantity],
        sales_quantity: ledger[:gross_sales_quantity],
        return_quantity: ledger[:reversed_quantity],
        ozon_seller_received_removal_quantity: seller_received_removals,
        supply_quantity: supply,
        platform_stock: platform_stock,
        platform_inbound_stock: platform_inbound_stock,
        fbo_fbw_stock: fbo_fbw_stock,
        book_stock: composed[:ledger_total],
        available_stock: composed[:own_side],
        ledger_total: composed[:ledger_total],
        platform_sellable: composed[:platform_sellable],
        platform_inbound: composed[:platform_inbound],
        platform_side: composed[:platform_side],
        own_side: composed[:own_side],
        return_in_transit: composed[:return_in_transit_quantity],
        return_at_platform: composed[:return_at_platform_quantity],
        unsellable: composed[:unsellable_quantity],
        sellable: composed[:sellable],
        stale_open_order_quantity: composed[:stale_open_order_quantity]
      }
    end

    def ledger
      @ledger ||= Ec::Inventory::BookLedger.call(sku_codes: [ @sku.sku_code ]).fetch(@sku.sku_code.upcase)
    end

    def ledger_stores
      @ledger_stores ||= Ec::Store.where(id: ledger[:by_store].keys.map(&:last)).index_by(&:id)
    end

    def ledger_store_key(platform, store)
      account_id = platform == "wb" ? store.wb_raw_account_id : store.ozon_raw_account_id
      key_for(platform, store.id, store.store_name, account_id)
    end

    def build_store_rows(latest_levels)
      store_keys = (
        order_rows.keys +
        return_rows.keys +
        ozon_seller_received_removal_rows.keys +
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
          ozon_seller_received_removal_quantity: ozon_seller_received_removal_rows[key].to_i,
          supply_quantity: supply_quantity_for(platform, key),
          platform_stock: levels.sum(&:quantity),
          latest_synced_at: levels.map(&:synced_at).compact.max
        }
      end.sort_by { |row| [row[:platform].to_s, row[:store_name].to_s] }
    end

    def order_rows
      @order_rows ||= begin
        rows = Hash.new { |hash, key| hash[key] = { sales_quantity: 0, order_status_counts: empty_order_status_counts } }
        ledger[:by_store].each do |(platform, store_id), data|
          store = ledger_stores[store_id]
          next unless store

          current = rows[ledger_store_key(platform, store)]
          current[:sales_quantity] += data[:gross_sales_quantity]
          data[:status_counts].each { |bucket, quantity| current[:order_status_counts][bucket] += quantity }
        end
        rows
      end
    end

    def return_rows
      @return_rows ||= begin
        rows = Hash.new(0)
        ledger[:by_store].each do |(platform, store_id), data|
          store = ledger_stores[store_id]
          next unless store && data[:reversed_quantity].positive?

          rows[ledger_store_key(platform, store)] += data[:reversed_quantity]
        end
        rows
      end
    end

    def ozon_seller_received_removal_rows
      @ozon_seller_received_removal_rows ||= begin
        sku_products_by_account.each_with_object({}) do |(account_id, products), rows|
          next if account_id.blank?

          store = products.first.store
          key = key_for("ozon", store.id, store.store_name, account_id)
          rows[key] = RawOzon::RemovalItem
            .seller_received
            .where(account_id: account_id, sku: products.map(&:platform_sku_id).compact)
            .sum(:quantity)
        end
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
          quantity_sql = ozon_skus.map do |ozon_sku|
            "COALESCE((items ->> #{RawOzon::SupplyOrder.connection.quote(ozon_sku)})::integer, 0)"
          end.join(" + ")
          quantity = RawOzon::SupplyOrder.where(account_id: account_id, status: "COMPLETED")
            .sum(Arel.sql(quantity_sql))
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

    def key_for(platform, store_id, store_name, account_id)
      [platform.to_s, store_id&.to_i, store_name.to_s, account_id&.to_i]
    end
  end
end
