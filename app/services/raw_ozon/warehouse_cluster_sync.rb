module RawOzon
  class WarehouseClusterSync
    DEFAULT_LIMIT = 1000

    def self.run(account_scope: RawOzon::SellerAccount.where(is_active: true), client_factory: nil, now: Time.current)
      new(account_scope: account_scope, client_factory: client_factory, now: now).run
    end

    def initialize(account_scope:, client_factory: nil, now: Time.current)
      @account_scope = account_scope
      @client_factory = client_factory || ->(account) { RawOzon::OzonClient.new(account.client_id, account.api_key) }
      @now = now
    end

    def run
      @account_scope.each_with_object({}) do |account, results|
        results[account.id] = sync_account(account)
      end
    end

    private

    def sync_account(account)
      rows = warehouse_cluster_rows(account)
      return { ok: 0, fetched: 0, created: 0, updated: 0 } if rows.empty?

      warehouse_ids = rows.map { |row| row[:warehouse_id] }
      existing_count = RawOzon::WarehouseCluster.where(account_id: account.id, warehouse_id: warehouse_ids).count

      RawOzon::WarehouseCluster.upsert_all(
        rows,
        unique_by: :idx_raw_ozon_warehouse_clusters_unique,
        update_only: %i[warehouse_name normalized_warehouse_name macrolocal_cluster_id cluster_name country_name raw_json synced_at updated_at],
        record_timestamps: false
      )
      RawOzon::WarehouseCluster.where(account_id: account.id).where.not(warehouse_id: warehouse_ids).delete_all

      {
        ok: rows.size,
        fetched: rows.size,
        created: rows.size - existing_count,
        updated: existing_count
      }
    rescue => e
      Rails.logger.warn("[OzonWarehouseClusterSync] account=#{account.id} failed: #{e.class} #{e.message}")
      { error: e.message }
    end

    def warehouse_cluster_rows(account)
      client = @client_factory.call(account)
      response = client.post("/v2/cluster/list", { limit: DEFAULT_LIMIT })

      Array(response["result"]).flat_map do |cluster|
        cluster_id = cluster["macrolocal_cluster_id"]
        cluster_name = cluster.dig("data", "macrolocal_cluster", "name")
        country_name = cluster.dig("data", "macrolocal_cluster", "country", "name")

        Array(cluster.dig("data", "fulfillments")).filter_map do |warehouse|
          warehouse_id = warehouse["warehouse_id"]
          warehouse_name = warehouse["name"].to_s
          next if warehouse_id.blank? || warehouse_name.blank?

          {
            account_id: account.id,
            warehouse_id: warehouse_id,
            warehouse_name: warehouse_name,
            normalized_warehouse_name: RawOzon::WarehouseCluster.normalize_warehouse_name(warehouse_name),
            macrolocal_cluster_id: cluster_id,
            cluster_name: cluster_name,
            country_name: country_name,
            raw_json: { cluster: cluster, warehouse: warehouse },
            synced_at: @now,
            created_at: @now,
            updated_at: @now
          }
        end
      end
    end
  end
end
