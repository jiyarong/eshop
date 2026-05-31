module GoogleSheets
  class PlatformCostImportService < BaseService
    WB_COST_TAB   = 'WB_COST'
    OZON_COST_TAB = 'OZON_COST'
    HEADER_ROWS   = 2  # row1=中文, row2=俄文

    def call(dry_run: false)
      results = {
        wb:   import_tab(WB_COST_TAB,   platform: 'wb',   dry_run:),
        ozon: import_tab(OZON_COST_TAB, platform: 'ozon', dry_run:),
      }
      print_summary(results, dry_run:)
      results
    end

    private

    def import_tab(tab_name, platform:, dry_run:)
      rows = fetch_data_rows(tab_name)
      updated = []
      skipped = []

      rows.each_with_index do |row, idx|
        sheet_row = HEADER_ROWS + 1 + idx

        sku_code      = row[0].to_s.strip
        delivery_mode = row[1].to_s.strip.downcase
        company_type  = row[2].to_s.strip.downcase

        if sku_code.blank?
          next  # 空行静默跳过
        end

        unless %w[fbs fbo].include?(delivery_mode)
          skipped << { row: sheet_row, key: sku_code, reason: "delivery_mode 无效: #{delivery_mode.inspect}" }
          next
        end

        unless %w[general small].include?(company_type)
          skipped << { row: sheet_row, key: sku_code, reason: "company_type 无效: #{company_type.inspect}" }
          next
        end

        pc = Ec::SkuPlatformCost.find_by(
          sku_code:,
          platform:,
          delivery_mode:,
          company_type:,
        )

        unless pc
          skipped << { row: sheet_row, key: "#{sku_code}/#{delivery_mode}/#{company_type}", reason: 'DB 中不存在，跳过（不新建）' }
          next
        end

        attrs = platform == 'wb' ? parse_wb(row) : parse_ozon(row)

        unless dry_run
          pc.update!(attrs)
        end

        updated << { row: sheet_row, key: "#{sku_code} #{delivery_mode} #{company_type}", attrs: }
      rescue => e
        skipped << { row: sheet_row, key: sku_code, reason: e.message }
      end

      { updated:, skipped: }
    end

    # ── 字段解析：只读 A–O（列0–14），P 列起全是公式，不碰 ──────────────────

    def parse_wb(row)
      {
        exchange_rate_rub_cny:  d(row[3]),
        acquiring_rate:         d(row[4]),
        ad_spend_rate:          d(row[5]),
        commission_rate:        d(row[6]),
        wb_logistics_base_rub:  d(row[7]),
        logistics_coeff:        d(row[8]),
        fbo_delivery_cny:       d(row[9]),
        wb_return_rate:         d(row[10]),
        wb_fixed_return_rate:   d(row[11]),
        storage_30d_cny:        d(row[12]),
        sales_tax_rate:         d(row[13]),
        target_price_rub:       d(row[14]),
      }
    end

    def parse_ozon(row)
      {
        exchange_rate_rub_cny:   d(row[3]),
        acquiring_rate:          d(row[4]),
        ad_spend_rate:           d(row[5]),
        commission_rate:         d(row[6]),
        ozon_fwd_base_rub:       d(row[7]),
        ozon_fwd_per_liter_rub:  d(row[8]),
        ozon_ret_base_rub:       d(row[9]),
        ozon_ret_per_liter_rub:  d(row[10]),
        ozon_warehouse_op_rub:   d(row[11]),
        ozon_fbs_delivery_rub:   d(row[12]),
        target_price_rf_rub:     d(row[13]),
        target_price_by_rub:     d(row[14]),
      }
    end

    # ── 工具 ─────────────────────────────────────────────────────────────────

    def fetch_data_rows(tab_name)
      result = @service.get_spreadsheet_values(SPREADSHEET_ID, "#{tab_name}!A:O")
      rows   = result.values || []
      rows[HEADER_ROWS..]  # 跳过两行表头
    end

    def d(val)
      BigDecimal(val.to_s.gsub(',', '').strip)
    rescue ArgumentError, TypeError
      BigDecimal('0')
    end

    def print_summary(results, dry_run:)
      prefix = dry_run ? '[DRY RUN] ' : ''
      results.each do |platform, result|
        tab = platform == :wb ? WB_COST_TAB : OZON_COST_TAB
        puts "\n#{prefix}[#{tab}]"
        puts "  更新: #{result[:updated].size} 条"
        result[:updated].each { |r| puts "    ✓ 行#{r[:row]} #{r[:key]}" }
        unless result[:skipped].empty?
          puts "  跳过: #{result[:skipped].size} 条"
          result[:skipped].each { |s| puts "    ✗ 行#{s[:row]} #{s[:key]} — #{s[:reason]}" }
        end
      end
    end
  end
end
