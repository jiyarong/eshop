module GoogleSheets
  class SkuCostImportService < BaseService
    TAB_NAME    = 'SKU_COST'
    HEADER_ROWS = 2  # row1=中文, row2=俄文
    # 列顺序与 CostSheetWriteService::SKU_COST_COLS 对应（A-N 为可编辑列）
    # A=sku_code B=product_name C=product_name_ru D=purchase_price_cny
    # E=freight_to_by_cny F=customs_misc_cny G=customs_duty_rate H=import_vat_rate
    # I=pkg_length_cm J=pkg_width_cm K=pkg_height_cm L=pkg_volume_override_l
    # M=misc_cost_cny N=damage_rate

    def call(dry_run: false)
      rows    = fetch_data_rows
      updated = []
      skipped = []

      rows.each_with_index do |row, idx|
        sheet_row = HEADER_ROWS + 1 + idx
        sku_code  = row[0].to_s.strip.upcase
        next if sku_code.blank?

        unless dry_run
          ActiveRecord::Base.transaction do
            sync_sku_names(sku_code, row)
            sync_sku_cost(sku_code, row)
          end
        end

        updated << sku_code
      rescue => e
        skipped << { row: sheet_row, sku_code:, reason: e.message }
      end

      puts "\n[#{TAB_NAME}] 更新: #{updated.size} 条, 跳过: #{skipped.size} 条"
      skipped.each { |s| puts "  ✗ 行#{s[:row]} #{s[:sku_code]} — #{s[:reason]}" }
      { updated:, skipped: }
    end

    private

    def fetch_data_rows
      result = @service.get_spreadsheet_values(SPREADSHEET_ID, "#{TAB_NAME}!A:N")
      rows   = result.values || []
      rows[HEADER_ROWS..]
    end

    def sync_sku_names(sku_code, row)
      product_name    = row[1].to_s.strip.presence
      product_name_ru = row[2].to_s.strip.presence
      return unless product_name || product_name_ru

      sku = Ec::Sku.find_by(sku_code:)
      return unless sku

      attrs = {}
      attrs[:product_name]    = product_name    if product_name
      attrs[:product_name_ru] = product_name_ru if product_name_ru
      sku.update!(attrs)
    end

    def sync_sku_cost(sku_code, row)
      cost  = Ec::SkuCost.find_or_initialize_by(sku_code:)
      attrs = {
        purchase_price_cny:    d(row[3]),
        freight_to_by_cny:     d(row[4]),
        customs_misc_cny:      d(row[5]),
        customs_duty_rate:     d(row[6]),
        import_vat_rate:       d(row[7]),
        pkg_length_cm:         d(row[8]),
        pkg_width_cm:          d(row[9]),
        pkg_height_cm:         d(row[10]),
        pkg_volume_override_l: d(row[11]),
        misc_cost_cny:         d(row[12]),
        damage_rate:           d(row[13]),
      }.compact
      cost.assign_attributes(attrs)
      cost.save!
    end

    def d(val)
      s = val.to_s.strip
      return nil if s.blank?
      BigDecimal(s.gsub(',', ''))
    rescue ArgumentError, TypeError
      nil
    end
  end
end
