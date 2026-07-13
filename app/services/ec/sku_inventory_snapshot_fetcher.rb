module Ec
  class SkuInventorySnapshotFetcher
    TOTAL_WAREHOUSE_NAME = "Всего находится на складах".freeze

    def call(now: Time.current)
      wb_fbw_rows(now) + wb_fbs_rows(now) + ozon_rows(now)
    end

    private

    def wb_fbw_rows(now)
      reports = prefetch_wb_fbw_reports

      RawWb::SellerAccount.where(is_active: true).flat_map do |account|
        store = Ec::Store.find_by(platform: "wb", wb_raw_account_id: account.id)
        report = Array(reports[account.id])

        Ec::SkuProduct
          .joins(:store)
          .where(platform: "wb", ec_stores: { wb_raw_account_id: account.id })
          .group_by(&:sku_code)
          .map do |sku_code, products|
            nm_ids = products.map(&:product_id)
            matching_rows = report.select { |row| nm_ids.include?(row["nmId"].to_s) }
            quantity = matching_rows.sum do |row|
              Array(row["warehouses"]).find { |warehouse| warehouse["warehouseName"] == TOTAL_WAREHOUSE_NAME }&.dig("quantity").to_i
            end

            row_for(
              sku_code: sku_code,
              platform: "wb",
              account_id: account.id,
              store: store || products.first.store,
              store_name: account.name,
              fulfillment_type: "fbw",
              quantity: quantity,
              synced_at: now,
              metadata: { nm_ids: nm_ids },
              warehouse_breakdown: wb_fbw_warehouse_breakdown(matching_rows)
            )
          end
      end
    end

    def wb_fbw_warehouse_breakdown(rows)
      grouped = Hash.new(0)
      rows.each do |row|
        Array(row["warehouses"]).each do |warehouse|
          warehouse_name = warehouse["warehouseName"].to_s
          next if warehouse_name.blank? || warehouse_name == TOTAL_WAREHOUSE_NAME

          grouped[warehouse_name] += warehouse["quantity"].to_i
        end
      end

      grouped.map do |warehouse_name, quantity|
        { warehouse_name: warehouse_name, quantity: quantity }
      end.sort_by { |row| row[:warehouse_name].to_s }
    end

    def prefetch_wb_fbw_reports
      RawWb::SellerAccount.where(is_active: true).each_with_object({}) do |account, cache|
        client = RawWb::WbClient.new(account.api_token)
        task_id = client.get(:seller_analytics, "/api/v1/warehouse_remains", groupByNm: true).dig("data", "taskId")
        loop do
          break if client.get(:seller_analytics, "/api/v1/warehouse_remains/tasks/#{task_id}/status").dig("data", "status") == "done"

          sleep 3
        end
        cache[account.id] = Array(client.get(:seller_analytics, "/api/v1/warehouse_remains/tasks/#{task_id}/download"))
      rescue => e
        Rails.logger.warn("[SkuInventorySnapshotFetcher] WB FBW account=#{account.id} failed: #{e.message}")
        cache[account.id] = []
      end
    end

    def wb_fbs_rows(now)
      RawWb::SellerAccount.where(is_active: true).flat_map do |account|
        store = Ec::Store.find_by(platform: "wb", wb_raw_account_id: account.id)
        fbs_warehouses = wb_fbs_warehouses(account)
        inbound_by_sku_code = Ec::PlatformInboundInventoryQuery.new(platform: "wb", account: account).by_sku_code

        Ec::SkuProduct
          .joins(:store)
          .where(platform: "wb", ec_stores: { wb_raw_account_id: account.id })
          .group_by(&:sku_code)
          .flat_map do |sku_code, products|
            chrt_ids = products.map(&:platform_sku_id).compact
            stocks_by_warehouse = chrt_ids.empty? ? [] : wb_fbs_stocks_by_warehouse(account, fbs_warehouses, chrt_ids)
            fbs_quantity = stocks_by_warehouse.sum { |row| row[:quantity].to_i }
            inbound_quantity = inbound_by_sku_code[sku_code].to_i
            available_fbs_quantity = [fbs_quantity - inbound_quantity, 0].max

            [
              row_for(
                sku_code: sku_code,
                platform: "wb",
                account_id: account.id,
                store: store || products.first.store,
                store_name: account.name,
                fulfillment_type: "fbs",
                quantity: available_fbs_quantity,
                synced_at: now,
                metadata: {
                  chrt_ids: chrt_ids,
                  warehouse_count: fbs_warehouses.size,
                  raw_fbs_quantity: fbs_quantity,
                  inbound_deducted_quantity: [inbound_quantity, fbs_quantity].min
                },
                warehouse_breakdown: stocks_by_warehouse
              ),
              row_for(
                sku_code: sku_code,
                platform: "wb",
                account_id: account.id,
                store: store || products.first.store,
                store_name: account.name,
                fulfillment_type: "inbound",
                quantity: inbound_quantity,
                synced_at: now,
                metadata: { source: "raw_wb_supply_items", chrt_ids: chrt_ids },
                warehouse_breakdown: []
              )
            ]
          end
      end
    end

    def wb_fbs_warehouses(account)
      client = RawWb::WbClient.new(account.api_token)
      Array(client.get(:marketplace, "/api/v3/warehouses")).select { |warehouse| warehouse["deliveryType"] == 1 }
    rescue => e
      Rails.logger.warn("[SkuInventorySnapshotFetcher] WB FBS warehouses account=#{account.id} failed: #{e.message}")
      []
    end

    def wb_fbs_stocks_by_warehouse(account, warehouses, chrt_ids)
      client = RawWb::WbClient.new(account.api_token)
      warehouses.map do |warehouse|
        response = client.post(:marketplace, "/api/v3/stocks/#{warehouse["id"]}", { chrtIds: chrt_ids.map(&:to_i) })
        quantity = Array(response["stocks"]).sum { |stock| stock["amount"].to_i }
        { warehouse_id: warehouse["id"], warehouse_name: warehouse["name"], quantity: quantity }
      end.select { |row| row[:quantity].positive? }
    rescue => e
      Rails.logger.warn("[SkuInventorySnapshotFetcher] WB FBS stocks account=#{account.id} failed: #{e.message}")
      []
    end

    def ozon_rows(now)
      RawOzon::SellerAccount.where(is_active: true).flat_map do |account|
        store = Ec::Store.find_by(platform: "ozon", ozon_raw_account_id: account.id)
        stocks_by_product_id = ozon_stocks_by_product_id(account)
        warehouse_breakdowns_by_sku = ozon_warehouse_breakdowns_by_sku(account)
        inbound_by_sku_code = Ec::PlatformInboundInventoryQuery.new(platform: "ozon", account: account).by_sku_code

        Ec::SkuProduct
          .joins(:store)
          .where(platform: "ozon", ec_stores: { ozon_raw_account_id: account.id })
          .group_by(&:sku_code)
          .flat_map do |sku_code, products|
            product_ids = products.map(&:product_id)
            ozon_skus = products.map { |product| product.platform_sku_id.to_s }.reject(&:blank?)
            fbo = product_ids.sum { |product_id| stocks_by_product_id.dig(product_id, "fbo").to_i }
            fbs = product_ids.sum { |product_id| stocks_by_product_id.dig(product_id, "fbs").to_i }
            inbound = inbound_by_sku_code[sku_code].to_i
            available_fbs = [fbs - inbound, 0].max

            %w[fbo fbs inbound].map do |fulfillment_type|
              quantity = case fulfillment_type
              when "fbo" then fbo
              when "fbs" then available_fbs
              else inbound
              end

              row_for(
                sku_code: sku_code,
                platform: "ozon",
                account_id: account.id,
                store: store || products.first.store,
                store_name: account.company_name,
                fulfillment_type: fulfillment_type,
                quantity: quantity,
                synced_at: now,
                metadata: {
                  product_ids: product_ids,
                  ozon_skus: ozon_skus,
                  raw_fbs_quantity: fbs,
                  inbound_deducted_quantity: fulfillment_type == "fbs" ? [inbound, fbs].min : 0
                },
                warehouse_breakdown: fulfillment_type == "fbo" ? ozon_warehouse_breakdown(warehouse_breakdowns_by_sku, ozon_skus) : []
              )
            end
          end
      end
    end

    def ozon_stocks_by_product_id(account)
      client = RawOzon::OzonClient.new(account.client_id, account.api_key)
      cursor = nil
      result = {}

      loop do
        body = { filter: {}, limit: 100 }
        body[:cursor] = cursor if cursor
        response = client.post("/v4/product/info/stocks", body)
        items = Array(response["items"])

        items.each do |item|
          product_id = item["product_id"].to_s
          result[product_id] = Array(item["stocks"]).each_with_object({}) do |stock, hash|
            hash[stock["type"].to_s] = stock["present"].to_i
          end
        end

        cursor = response["cursor"]
        break if cursor.blank? || items.size < 100
      end

      result
    rescue => e
      Rails.logger.warn("[SkuInventorySnapshotFetcher] Ozon stocks account=#{account.id} failed: #{e.message}")
      {}
    end

    def ozon_warehouse_breakdowns_by_sku(account)
      client = RawOzon::OzonClient.new(account.client_id, account.api_key)
      offset = 0
      limit = 1000
      result = Hash.new { |hash, key| hash[key] = [] }

      loop do
        response = client.post("/v2/analytics/stock_on_warehouses", {
          limit: limit,
          offset: offset,
          warehouse_type: "ALL"
        })
        rows = Array(response.dig("result", "rows"))
        break if rows.empty?

        rows.each do |row|
          result[row["sku"].to_s] << {
            warehouse_name: row["warehouse_name"],
            item_code: row["item_code"],
            quantity: row["free_to_sell_amount"].to_i,
            promised: row["promised_amount"].to_i,
            reserved: row["reserved_amount"].to_i
          }
        end

        break if rows.size < limit

        offset += limit
        sleep 0.5
      end

      result
    rescue => e
      Rails.logger.warn("[SkuInventorySnapshotFetcher] Ozon warehouse stocks account=#{account.id} failed: #{e.message}")
      {}
    end

    def ozon_warehouse_breakdown(breakdowns_by_sku, ozon_skus)
      grouped = Hash.new { |hash, key| hash[key] = { quantity: 0, promised: 0, reserved: 0, item_codes: [] } }
      ozon_skus.each do |ozon_sku|
        Array(breakdowns_by_sku[ozon_sku]).each do |row|
          warehouse_name = row[:warehouse_name].to_s
          next if warehouse_name.blank?

          grouped_row = grouped[warehouse_name]
          grouped_row[:quantity] += row[:quantity].to_i
          grouped_row[:promised] += row[:promised].to_i
          grouped_row[:reserved] += row[:reserved].to_i
          grouped_row[:item_codes] << row[:item_code].to_s if row[:item_code].present?
        end
      end

      grouped.map do |warehouse_name, row|
        {
          warehouse_name: warehouse_name,
          quantity: row[:quantity],
          promised: row[:promised],
          reserved: row[:reserved],
          item_codes: row[:item_codes].uniq
        }
      end.sort_by { |row| row[:warehouse_name].to_s }
    end

    def row_for(sku_code:, platform:, account_id:, store:, store_name:, fulfillment_type:, quantity:, synced_at:, metadata:, warehouse_breakdown: [])
      {
        sku_code: sku_code.to_s.upcase,
        platform: platform,
        account_id: account_id,
        store_id: store&.id,
        store_name: store&.store_name || store_name,
        fulfillment_type: fulfillment_type,
        quantity: quantity.to_i,
        synced_at: synced_at,
        metadata: metadata,
        warehouse_breakdown: warehouse_breakdown
      }
    end
  end
end
