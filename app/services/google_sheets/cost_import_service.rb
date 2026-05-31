module GoogleSheets
  class CostImportService < BaseService
    # 四个 Tab 的固定配置（运费率常数从公式常数中读取，不在单元格里）
    TAB_CONFIGS = {
      '成本模板确认1' => {
        platform: 'wb', company_type: 'general',
        wb_logistics_base_rub: 60,
      },
      '成本模板确认2' => {
        platform: 'wb', company_type: 'small',
        wb_logistics_base_rub: 46,
      },
      '成本模板确认3' => {
        platform: 'ozon', delivery_mode: 'fbo', company_type: 'general',
        ozon_fwd_base_rub: 87.44,  ozon_fwd_per_liter_rub: 15.25,
        ozon_ret_base_rub: 87.44,  ozon_ret_per_liter_rub: 15.25,
      },
      '成本模板确认4' => {
        platform: 'ozon', delivery_mode: 'fbs', company_type: 'general',
        ozon_fwd_base_rub: 117.94, ozon_fwd_per_liter_rub: 23.39,
        ozon_ret_base_rub: 87.44,  ozon_ret_per_liter_rub: 15.25,
      },
    }.freeze

    def call(dry_run: false)
      summary = {}
      TAB_CONFIGS.each do |tab_name, config|
        summary[tab_name] = import_tab(tab_name, config, dry_run:)
      end
      print_summary(summary)
      summary
    end

    private

    # ── 逐 Tab 导入 ────────────────────────────────────────────────────────────

    def import_tab(tab_name, config, dry_run:)
      rows = fetch_rows(tab_name)
      imported = []
      skipped  = []

      rows.each_with_index do |row, idx|
        sku_codes, delivery_mode = resolve_sku(row, config)

        unless sku_codes
          skipped << { row: idx + 2, hint: row_hint(row, config), reason: 'SKU无法确定' }
          next
        end

        Array(sku_codes).each do |sku_code|
          effective_config = config.merge(delivery_mode: delivery_mode || config[:delivery_mode])

          unless dry_run
            ActiveRecord::Base.transaction do
              ensure_sku(sku_code, row, config)
              upsert_sku_cost(sku_code, row, config)
              upsert_platform_cost(sku_code, row, effective_config)
            end
          end

          imported << { sku_code:, delivery_mode: effective_config[:delivery_mode] }
        end
      rescue => e
        skipped << { row: idx + 2, hint: Array(sku_codes).first || row_hint(row, config), reason: e.message }
      end

      { imported:, skipped: }
    end

    # ── SKU 解析 ───────────────────────────────────────────────────────────────

    # 返回 [sku_code, delivery_mode]，无法确定时返回 [nil, nil]
    def resolve_sku(row, config)
      if config[:platform] == 'wb'
        resolve_wb_sku(row)
      else
        resolve_ozon_sku(row)
      end
    end

    # 有效 SKU：以拉丁字母开头，仅含拉丁字母/数字/连字符，无空格，至少4字符
    WB_SKU_RE       = /\A[A-Za-z][A-Za-z0-9\-]{3,}\z/
    # 纯模式标记词，不是 SKU
    WB_SKU_RESERVED = %w[FBS FBO].freeze

    # col[1] 产品名 → SKU（适用于 col[0] 是西里尔文/模式词的行）
    WB_NAME_TO_SKU = [
      [/ldd001|торшер.*\b001\b|\b001\b.*торшер/i, 'LDD001'],
      [/ldd002|торшер.*\b002\b|\b002\b.*торшер/i, 'LDD002'],
      [/ldd003|торшер.*\b003\b|\b003\b.*торшер/i, 'LDD003'],
      [/ldd004/i, 'LDD004'],
      [/ldd005/i, 'LDD005'],
      [/алкотестер|алко/i,                         'CZY001'],
    ].freeze

    def resolve_wb_sku(row)
      cell = row[0].to_s.strip
      return [nil, nil] if cell.blank?

      lines = cell.split("\n").map(&:strip)
      raw_sku = lines[0]

      # 标准 SKU 格式
      if WB_SKU_RE.match?(raw_sku) && !WB_SKU_RESERVED.include?(raw_sku.upcase)
        sku_code = raw_sku.upcase
        context = (lines[1..].join(' ') + ' ' + row[1].to_s).upcase
        delivery_mode = context.include?('FBS') ? 'fbs' : 'fbo'
        return [sku_code, delivery_mode]
      end

      # fallback：col[0] 是俄文品名或 FBO/FBS，尝试从 col[1] 提取 SKU
      name_cell = row[1].to_s.strip
      # 先看 col[1] 里有无拉丁 SKU token（如 "Торшер LDD001"）
      if (m = name_cell.match(/\b([A-Za-z]{2,}[A-Za-z0-9\-]{2,})\b/))
        candidate = m[1].upcase
        if WB_SKU_RE.match?(candidate) && !WB_SKU_RESERVED.include?(candidate)
          delivery_mode = cell.upcase.include?('FBS') ? 'fbs' : 'fbo'
          return [candidate, delivery_mode]
        end
      end
      # 再用名称映射表（"Торшер 001" / "Алкотестер" 等）
      combined = "#{cell}\n#{name_cell}"
      WB_NAME_TO_SKU.each do |pattern, sku|
        if pattern.match?(combined)
          delivery_mode = cell.upcase.include?('FBS') ? 'fbs' : 'fbo'
          return [sku, delivery_mode]
        end
      end

      [nil, nil]
    end

    # Ozon 产品名 → SKU 映射（适用于 col[51]/col[52] 为空的行）
    OZON_NAME_TO_SKU = [
      [/швабра.*206|206.*швабра/i,                    'HD-QJ206'],
      [/швабра.*310|310.*швабра/i,                    'HD-QJ310'],
      [/ирригатор.*(бел|white)|белый.*ирригатор/i,    'CYQ97-WT'],
      [/ирригатор.*(черн|black)|черный.*ирригатор/i,  'CYQ97-BK'],
      [/подушк.*(светл|белая|light)|светл.*подушк/i,  'JXZ-WHITE-02'],
      [/подушк.*(темн|dark|тём)|темн.*подушк/i,       'JXZ-GREY-01'],
      [/吸尘器|пылесос.*верт|беспровод.*пылесос/i,     'XCQ707'],
      [/полотенцесушитель.*(золот|gd)|золот.*полотен/i, 'KJ-217-GD'],
    ].freeze

    def resolve_ozon_sku(row)
      # col[51]/col[52] 可能含换行分隔的多个 Ozon SKU（白/黑两色合一行）
      ozon_sku_nums = [row[51], row[52]]
        .compact
        .flat_map { |v| v.to_s.strip.split(/[\n\r,\s]+/) }
        .map(&:strip)
        .reject(&:empty?)

      if ozon_sku_nums.any?
        found = ozon_sku_nums.filter_map do |sku_num|
          product = RawOzon::Product.find_by("raw_json->>'sku' = ?", sku_num)
          product&.offer_id.to_s.strip.upcase.presence
        end.uniq
        return [found.size == 1 ? found.first : found, nil] if found.any?
      end

      # fallback：按产品名映射
      name = row[0].to_s.strip
      OZON_NAME_TO_SKU.each do |pattern, sku|
        return [sku, nil] if pattern.match?(name)
      end

      [nil, nil]
    end

    # ── ec_skus 保证存在 ───────────────────────────────────────────────────────

    def ensure_sku(sku_code, row, config)
      Ec::Sku.find_or_create_by!(sku_code:) do |s|
        s.is_active = true
        if config[:platform] == 'wb'
          parts = row[1].to_s.split("\n")
          s.product_name    = parts[0].to_s.strip.presence
          s.product_name_ru = parts[1].to_s.strip.presence
        else
          s.product_name_ru = row[0].to_s.split("\n").first.to_s.strip.presence
        end
      end
    end

    # ── ec_sku_costs upsert（合并：不用空值覆盖已有值） ────────────────────────

    def upsert_sku_cost(sku_code, row, config)
      cost = Ec::SkuCost.find_or_initialize_by(sku_code:)
      attrs = config[:platform] == 'wb' ? parse_wb_cost(row) : parse_ozon_cost(row)

      attrs.each { |k, v| cost[k] = v if cost[k].blank? && v.present? }
      cost.save!
    end

    def parse_wb_cost(row)
      purchase = to_d(row[4])
      duty_val = to_d(row[7])
      {
        purchase_price_cny: purchase.nonzero?,
        freight_to_by_cny:  to_d(row[5]).nonzero?,
        customs_misc_cny:   to_d(row[6]).nonzero?,
        customs_duty_rate:  duty_and_purchase_to_rate(duty_val, purchase),
        import_vat_rate:    0.20,
        pkg_length_cm:      to_d(row[10]).nonzero?,
        pkg_width_cm:       to_d(row[11]).nonzero?,
        pkg_height_cm:      to_d(row[12]).nonzero?,
        misc_cost_cny:      to_d(row[25]).nonzero?,
      }.compact
    end

    def parse_ozon_cost(row)
      purchase = to_d(row[1])
      duty_val = to_d(row[4])
      {
        purchase_price_cny:    purchase.nonzero?,
        freight_to_by_cny:     to_d(row[2]).nonzero?,
        customs_misc_cny:      to_d(row[3]).nonzero?,
        customs_duty_rate:     duty_and_purchase_to_rate(duty_val, purchase),
        import_vat_rate:       0.20,
        pkg_volume_override_l: to_d(row[7]).nonzero?,
      }.compact
    end

    # ── ec_sku_platform_costs upsert（全量覆盖平台参数） ─────────────────────

    def upsert_platform_cost(sku_code, row, config)
      pc = Ec::SkuPlatformCost.find_or_initialize_by(
        sku_code:,
        platform:      config[:platform],
        delivery_mode: config[:delivery_mode],
        company_type:  config[:company_type],
      )

      attrs = config[:platform] == 'wb' \
        ? parse_wb_platform(row, config) \
        : parse_ozon_platform(row, config)

      pc.assign_attributes(attrs)
      pc.save!
    end

    def parse_wb_platform(row, config)
      exchange        = to_d(row[28])
      revenue_cny     = to_d(row[29])  # 售价CNY = 售价RUB / 汇率
      platform_frt    = to_d(row[18])  # 平台运费CNY（Sheet 计算列，用于反推退货率）
      return_cny_val  = to_d(row[19])  # 返程费CNY（Sheet 计算列）
      fixed_ret_cny   = to_d(row[20])  # 固定退货费CNY

      # 退货率 = 返程费 ÷ 平台运费（Sheet 各行分别硬编码，有 10/90、18/82、20/80 等）
      wb_return       = platform_frt.nonzero? ? (return_cny_val / platform_frt).round(6) : nil
      # 固定退货率 = 固定退货费 × 汇率 ÷ 50RUB
      wb_fixed_return = exchange.nonzero? ? (fixed_ret_cny * exchange / 50).round(6) : nil

      {
        wb_logistics_base_rub: config[:wb_logistics_base_rub],
        logistics_coeff:       to_d(row[16]),
        fbo_delivery_cny:      to_d(row[17]),
        wb_return_rate:        wb_return,
        wb_fixed_return_rate:  wb_fixed_return,
        acquiring_rate:        derive_rate(row[22], revenue_cny),
        ad_spend_rate:         derive_rate(row[23], revenue_cny),
        commission_rate:       to_rate(row[30]),
        sales_tax_rate:        config[:company_type] == 'small' ? 0.06 : nil,
        exchange_rate_rub_cny: exchange,
        target_price_rub:      to_d(row[26]),
        storage_30d_cny:       to_d(row[21]).nonzero?,
      }.compact
    end

    def parse_ozon_platform(row, config)
      exchange     = to_d(row[30])
      rf_price_cny = to_d(row[31])  # 俄罗斯售价CNY = AC/AE（已计算列）

      # FBO/FBS 仓库费用列位置不同
      if config[:delivery_mode] == 'fbs'
        warehouse_op_rub  = to_d(row[17])   # 官方仓操作费
        fbs_delivery_rub  = to_d(row[18])   # 官方仓配送费（FBS专有）
      else
        warehouse_op_rub  = to_d(row[18])   # 官方仓操作费
        fbs_delivery_rub  = nil
      end

      {
        ozon_fwd_base_rub:      config[:ozon_fwd_base_rub],
        ozon_fwd_per_liter_rub: config[:ozon_fwd_per_liter_rub],
        ozon_ret_base_rub:      config[:ozon_ret_base_rub],
        ozon_ret_per_liter_rub: config[:ozon_ret_per_liter_rub],
        ozon_warehouse_op_rub:  warehouse_op_rub,
        ozon_fbs_delivery_rub:  fbs_delivery_rub,
        commission_rate:        to_rate(row[23]),
        acquiring_rate:         derive_rate(row[25], rf_price_cny),
        ad_spend_rate:          derive_rate(row[26], rf_price_cny),
        exchange_rate_rub_cny:  exchange,
        target_price_rf_rub:    to_d(row[28]),
        target_price_by_rub:    to_d(row[29]),
      }.compact
    end

    # ── 工具方法 ───────────────────────────────────────────────────────────────

    def fetch_rows(tab_name)
      result = @service.get_spreadsheet_values(SPREADSHEET_ID, tab_name)
      rows   = result.values || []
      rows[1..]  # 跳过表头行
    end

    def to_d(val)
      BigDecimal(val.to_s.gsub(',', '').strip)
    rescue ArgumentError, TypeError
      BigDecimal('0')
    end

    # 解析百分比字符串："21.8%" → 0.218，普通小数原样处理
    def to_rate(val)
      s = val.to_s.strip
      return (BigDecimal(s.chomp('%')) / 100).round(6) if s.end_with?('%')
      to_d(val)
    rescue ArgumentError, TypeError
      BigDecimal('0')
    end

    # 从关税绝对值和采购价推算税率（最多4位小数）
    # purchase 为 nil/0 时返回 nil（无法计算）
    # duty 为 0 时返回 0（明确标记 0 税率，避免 DB 默认值污染）
    def duty_and_purchase_to_rate(duty_val, purchase)
      return nil unless purchase&.nonzero?
      (duty_val.to_d / purchase).round(4)
    end

    # 用费用 CNY 金额 / 收入 CNY 推算费率
    def derive_rate(fee_val, revenue_cny)
      fee = to_d(fee_val)
      return nil if fee.zero? || revenue_cny.to_d.zero?
      (fee / revenue_cny.to_d).round(4)
    end

    def row_hint(row, config)
      config[:platform] == 'wb' ? row[0].to_s.split("\n").first : row[0].to_s
    end

    def print_summary(summary)
      summary.each do |tab, result|
        puts "\n[#{tab}]"
        puts "  导入: #{result[:imported].length} 条"
        result[:imported].each { |r| puts "    ✓ #{r[:sku_code]} (#{r[:delivery_mode]})" }
        unless result[:skipped].empty?
          puts "  跳过: #{result[:skipped].length} 条"
          result[:skipped].each { |s| puts "    ✗ 行#{s[:row]} #{s[:hint]} — #{s[:reason]}" }
        end
      end
    end
  end
end
