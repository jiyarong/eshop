module GoogleSheets
  class InventorySnapshotImportService < BaseService
    TAB_NAME = InventorySnapshotWriteService::TAB_NAME

    # 只读取 sku_code（列A）和 total_received（固定列），回写到 ec_inventory_totals
    def call
      rows = fetch_rows
      updated = 0
      skipped = []

      rows.each_with_index do |row, i|
        sku_code       = row[0].to_s.strip
        received_raw   = row[InventorySnapshotWriteService::TOTAL_RECEIVED_COL].to_s.strip

        next if sku_code.blank?

        received = received_raw.gsub(/[^\d\-]/, "").to_i
        record   = Ec::InventoryTotal.find_or_initialize_by(sku_code: sku_code)
        record.update!(total_received: received)
        updated += 1
      rescue => e
        skipped << { row: i + 3, sku_code: sku_code, reason: e.message }
      end

      { updated: updated, skipped: skipped }
    end

    private

    def fetch_rows
      result = @service.get_spreadsheet_values(SPREADSHEET_ID, TAB_NAME)
      rows   = result.values || []
      rows[InventorySnapshotWriteService::HEADER_ROWS..]  # 跳过表头行
    end
  end
end
