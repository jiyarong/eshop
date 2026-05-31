module GoogleSheets
  class SkuImportService < BaseService
    TAB_NAME = 'SKU'.freeze

    # 列顺序：A=sku_code, B=product_name, C=product_name_ru, D=is_active
    def call
      rows = fetch_rows
      upserted = 0
      skipped  = []

      rows.each_with_index do |row, i|
        sku_code = row[0].to_s.strip.upcase
        if sku_code.blank?
          skipped << { row: i + 2, reason: 'SKU编码为空' }
          next
        end

        sku = Ec::Sku.find_or_initialize_by(sku_code: sku_code)
        sku.product_name    = row[1].to_s.strip.presence
        sku.product_name_ru = row[2].to_s.strip.presence
        sku.is_active       = row[3].to_s.strip == '是'
        sku.save!
        upserted += 1
      rescue => e
        skipped << { row: i + 2, sku_code: sku_code, reason: e.message }
      end

      { upserted: upserted, skipped: skipped }
    end

    private

    def fetch_rows
      result = @service.get_spreadsheet_values(SPREADSHEET_ID, TAB_NAME)
      rows   = result.values || []
      rows[1..]  # 跳过第0行表头
    end
  end
end
