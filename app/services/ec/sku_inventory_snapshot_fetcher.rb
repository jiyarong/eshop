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
            quantity = report
              .select { |row| nm_ids.include?(row["nmId"].to_s) }
              .sum { |row| Array(row["warehouses"]).find { |warehouse| warehouse["warehouseName"] == TOTAL_WAREHOUSE_NAME }&.dig("quantity").to_i }

            row_for(
              sku_code: sku_code,
              platform: "wb",
              account_id: account.id,
              store: store || products.first.store,
              store_name: account.name,
              fulfillment_type: "fbw",
              quantity: quantity,
              synced_at: now,
              metadata: { nm_ids: nm_ids }
            )
          end
      end
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

        Ec::SkuProduct
          .joins(:store)
          .where(platform: "wb", ec_stores: { wb_raw_account_id: account.id })
          .group_by(&:sku_code)
          .map do |sku_code, products|
            chrt_ids = products.map(&:platform_sku_id).compact
            quantity = chrt_ids.empty? ? 0 : wb_fbs_quantity(account, fbs_warehouses, chrt_ids)

            row_for(
              sku_code: sku_code,
              platform: "wb",
              account_id: account.id,
              store: store || products.first.store,
              store_name: account.name,
              fulfillment_type: "fbs",
              quantity: quantity,
              synced_at: now,
              metadata: { chrt_ids: chrt_ids, warehouse_count: fbs_warehouses.size }
            )
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

    def wb_fbs_quantity(account, warehouses, chrt_ids)
      client = RawWb::WbClient.new(account.api_token)
      warehouses.sum do |warehouse|
        response = client.post(:marketplace, "/api/v3/stocks/#{warehouse["id"]}", { chrtIds: chrt_ids.map(&:to_i) })
        Array(response["stocks"]).sum { |stock| stock["amount"].to_i }
      end
    rescue => e
      Rails.logger.warn("[SkuInventorySnapshotFetcher] WB FBS stocks account=#{account.id} failed: #{e.message}")
      0
    end

    def ozon_rows(now)
      RawOzon::SellerAccount.where(is_active: true).flat_map do |account|
        store = Ec::Store.find_by(platform: "ozon", ozon_raw_account_id: account.id)
        stocks_by_product_id = ozon_stocks_by_product_id(account)

        Ec::SkuProduct
          .joins(:store)
          .where(platform: "ozon", ec_stores: { ozon_raw_account_id: account.id })
          .group_by(&:sku_code)
          .flat_map do |sku_code, products|
            product_ids = products.map(&:product_id)
            fbo = product_ids.sum { |product_id| stocks_by_product_id.dig(product_id, "fbo").to_i }
            fbs = product_ids.sum { |product_id| stocks_by_product_id.dig(product_id, "fbs").to_i }

            %w[fbo fbs].map do |fulfillment_type|
              row_for(
                sku_code: sku_code,
                platform: "ozon",
                account_id: account.id,
                store: store || products.first.store,
                store_name: account.company_name,
                fulfillment_type: fulfillment_type,
                quantity: fulfillment_type == "fbo" ? fbo : fbs,
                synced_at: now,
                metadata: { product_ids: product_ids }
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

    def row_for(sku_code:, platform:, account_id:, store:, store_name:, fulfillment_type:, quantity:, synced_at:, metadata:)
      {
        sku_code: sku_code.to_s.upcase,
        platform: platform,
        account_id: account_id,
        store_id: store&.id,
        store_name: store&.store_name || store_name,
        fulfillment_type: fulfillment_type,
        quantity: quantity.to_i,
        synced_at: synced_at,
        metadata: metadata
      }
    end
  end
end
