module Ec
  # 每日库存快照同步
  #
  # 从 OzonInventorySummary + WbInventorySummary 拉取最新数据，
  # upsert 到 ec_inventory_snapshots（明细）和 ec_inventory_totals（汇总）。
  # total_received 是运营手填字段，sync 不覆盖。
  #
  # Usage:
  #   Ec::InventorySnapshotSync.run
  class InventorySnapshotSync
    OZON_STORE_NAMES = {
      1 => "Nevastal",
      3 => "Nevastal2",
      4 => "Domos",
      5 => "Nanokit",
    }.freeze

    WB_STORE_NAMES = {
      2 => "TaxiLink",
      3 => "WorldChoice",
    }.freeze

    def self.run
      new.run
    end

    def self.run_and_push_to_sheets
      run
      GoogleSheets::InventorySnapshotWriteService.new.call
    end

    def run
      now = Time.current
      snapshot_rows = []

      snapshot_rows += ozon_rows(now)
      snapshot_rows += wb_rows(now)

      return if snapshot_rows.empty?

      Ec::InventorySnapshot.upsert_all(
        snapshot_rows,
        unique_by: :idx_ec_inventory_snapshots_unique,
        update_only: %i[store_name stock supply sold fbs synced_at updated_at],
        record_timestamps: false,
      )

      upsert_totals(now)

      ts = Time.current.strftime("%m-%d %H:%M:%S")
      Rails.logger.info "[InventorySnapshotSync] #{ts} Done. #{snapshot_rows.size} snapshot rows upserted."
    end

    private

    def ozon_rows(now)
      result = Ec::OzonInventorySummary.new.call
      result.rows.map do |r|
        {
          sku_code:   r.article.upcase,
          platform:   'ozon',
          account_id: r.account_id,
          store_name: r.store_name,
          stock:      r.fbo_stock,
          supply:     r.fbo_supply,
          sold:       r.fbo_sold,
          fbs:        r.fbs_net,
          synced_at:  now,
          created_at: now,
          updated_at: now,
        }
      end
    end

    def wb_rows(now)
      result = Ec::WbInventorySummary.new.call
      result.rows.map do |r|
        {
          sku_code:   r.vendor_code.upcase,
          platform:   'wb',
          account_id: r.account_id,
          store_name: r.store_name,
          stock:      r.fbw_stock,
          supply:     r.fbw_supply,
          sold:       r.fbw_sold,
          fbs:        r.fbs,
          synced_at:  now,
          created_at: now,
          updated_at: now,
        }
      end
    end

    def upsert_totals(now)
      agg = Ec::InventorySnapshot
        .group(:sku_code)
        .pluck(
          :sku_code,
          Arel.sql('SUM(supply)'),
          Arel.sql('SUM(stock)'),
          Arel.sql('SUM(sold)'),
          Arel.sql('SUM(fbs)'),
        )

      rows = agg.map do |sku_code, supply, stock, sold, fbs|
        {
          sku_code:     sku_code,
          total_supply: supply.to_i,
          total_stock:  stock.to_i,
          total_sold:   sold.to_i,
          total_fbs:    fbs.to_i,
          synced_at:    now,
          created_at:   now,
          updated_at:   now,
        }
      end

      return if rows.empty?

      Ec::InventoryTotal.upsert_all(
        rows,
        unique_by: :index_ec_inventory_totals_on_sku_code,
        update_only: %i[total_supply total_stock total_sold total_fbs synced_at updated_at],
        record_timestamps: false,
      )
    end
  end
end
