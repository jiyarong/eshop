module RawWb
  class WarehouseRegionSync
    DEFAULT_LIMIT = 1000
    OFFICES_STOCK_TYPE = "wb".freeze

    def self.run(account_scope: RawWb::SellerAccount.where(is_active: true), client_factory: nil, now: Time.current)
      new(account_scope: account_scope, client_factory: client_factory, now: now).run
    end

    def initialize(account_scope:, client_factory: nil, now: Time.current)
      @account_scope = account_scope
      @client_factory = client_factory || ->(account) { RawWb::WbClient.new(account.api_token) }
      @now = now
    end

    def run
      @account_scope.each_with_object({}) do |account, results|
        results[account.id] = sync_account(account)
      end
    end

    private

    def sync_account(account)
      rows = warehouse_region_rows(account)
      return { ok: 0, fetched: 0, created: 0, updated: 0 } if rows.empty?

      warehouse_ids = rows.map { |row| row[:warehouse_id] }
      existing_count = RawWb::WarehouseRegion.where(account_id: account.id, warehouse_id: warehouse_ids).count

      RawWb::WarehouseRegion.upsert_all(
        rows,
        unique_by: :idx_raw_wb_warehouse_regions_unique,
        update_only: %i[warehouse_name normalized_warehouse_name region_name source raw_json synced_at updated_at],
        record_timestamps: false
      )
      RawWb::WarehouseRegion.where(account_id: account.id).where.not(warehouse_id: warehouse_ids).delete_all

      {
        ok: rows.size,
        fetched: rows.size,
        created: rows.size - existing_count,
        updated: existing_count
      }
    rescue => e
      Rails.logger.warn("[WbWarehouseRegionSync] account=#{account.id} failed: #{e.class} #{e.message}")
      { error: e.message }
    end

    def warehouse_region_rows(account)
      client = @client_factory.call(account)
      rows_by_warehouse_id = {}

      wb_warehouse_rows(client).each do |warehouse|
        row = row_from_wb_warehouse(account, warehouse)
        rows_by_warehouse_id[row[:warehouse_id]] ||= row if row
      end

      office_rows(client).each do |region, office|
        row = row_from_office(account, region, office)
        rows_by_warehouse_id[row[:warehouse_id]] ||= row if row
      end

      rows_by_warehouse_id.values
    end

    def wb_warehouse_rows(client)
      offset = 0
      rows = []

      loop do
        response = client.post(:seller_analytics, "/api/analytics/v1/stocks-report/wb-warehouses", {
          limit: DEFAULT_LIMIT,
          offset: offset
        })
        items = Array(response.dig("data", "items") || response["data"] || response)
        rows.concat(items)
        break if items.size < DEFAULT_LIMIT

        offset += DEFAULT_LIMIT
        sleep 0.5
      end

      rows
    end

    def office_rows(client)
      response = client.post(:seller_analytics, "/api/v2/stocks-report/offices", {
        nmIDs: [],
        subjectIDs: [],
        brandNames: [],
        tagIDs: [],
        currentPeriod: { start: Date.current.to_s, end: Date.current.to_s },
        stockType: OFFICES_STOCK_TYPE,
        skipDeletedNm: false
      })

      Array(response.dig("data", "regions")).flat_map do |region|
        Array(region["offices"]).map { |office| [region, office] }
      end
    end

    def row_from_wb_warehouse(account, warehouse)
      warehouse_id = warehouse["warehouseId"]
      warehouse_name = warehouse["warehouseName"].to_s.strip
      region_name = warehouse["regionName"].to_s.strip
      return if warehouse_id.blank? || warehouse_name.blank? || region_name.blank?

      row_for(
        account: account,
        warehouse_id: warehouse_id,
        warehouse_name: warehouse_name,
        region_name: region_name,
        source: "stocks_report_wb_warehouses",
        raw_json: warehouse
      )
    end

    def row_from_office(account, region, office)
      warehouse_id = office["officeID"]
      warehouse_name = office["officeName"].to_s.strip
      region_name = region["regionName"].to_s.strip
      return if warehouse_id.blank? || warehouse_name.blank? || region_name.blank?

      row_for(
        account: account,
        warehouse_id: warehouse_id,
        warehouse_name: warehouse_name,
        region_name: region_name,
        source: "stocks_report_offices",
        raw_json: { region: region.except("offices"), office: office }
      )
    end

    def row_for(account:, warehouse_id:, warehouse_name:, region_name:, source:, raw_json:)
      {
        account_id: account.id,
        warehouse_id: warehouse_id,
        warehouse_name: warehouse_name,
        normalized_warehouse_name: RawWb::WarehouseRegion.normalize_warehouse_name(warehouse_name),
        region_name: region_name,
        source: source,
        raw_json: raw_json,
        synced_at: @now,
        created_at: @now,
        updated_at: @now
      }
    end
  end
end
