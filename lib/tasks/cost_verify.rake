namespace :cost do
  desc "对比 Google Sheet 四个成本 Tab 与 Ruby 计算方法，公差 ±1 CNY（逐行重建对象，不依赖 DB 存储参数）"
  task verify: :environment do
    require_relative '../../app/services/google_sheets/cost_import_service'

    TOLERANCE = 1.0

    WB_COL_TOTAL    = 33   # AH — 最终成本
    WB_COL_PROFIT   = 34   # AI — 利润
    OZ_COL_RF_TOTAL = 34   # AI — RF最终成本
    OZ_COL_BY_TOTAL = 35   # AJ — BY最终成本
    OZ_COL_RF_PROF  = 36   # AK — RF毛利
    OZ_COL_BY_PROF  = 37   # AL — BY毛利

    svc      = GoogleSheets::CostImportService.new
    failures = []
    summary  = {}

    # ── 辅助方法 ─────────────────────────────────────────────────────────────

    def approx_ok?(expected, actual)
      (expected.to_f - actual.to_f).abs <= TOLERANCE
    end

    def to_d_val(svc, val) = svc.send(:to_d, val)

    # 从行数据构建内存 SkuCost，并注入到 SkuPlatformCost
    def build_pair(svc, cost_attrs, platform_attrs)
      c  = Ec::SkuCost.new(cost_attrs)
      pc = Ec::SkuPlatformCost.new(platform_attrs)
      pc.define_singleton_method(:cost) { c }
      pc
    end

    # ── WB Tab 通用验证 ───────────────────────────────────────────────────────

    def check_wb_tab(svc, tab_name, failures, summary)
      config       = GoogleSheets::CostImportService::TAB_CONFIGS[tab_name]
      company_type = config[:company_type]
      rows         = svc.send(:fetch_rows, tab_name)
      checked      = 0
      tab_failures = []

      rows.each_with_index do |row, idx|
        sku_code, delivery_mode = svc.send(:resolve_sku, row, config)
        next unless sku_code

        dm            = delivery_mode || 'fbo'
        cost_attrs    = svc.send(:parse_wb_cost, row)
        platform_attrs = svc.send(:parse_wb_platform, row, config).merge(
          platform: 'wb', delivery_mode: dm, company_type: company_type
        )

        pc = build_pair(svc, cost_attrs, platform_attrs)

        sheet_total  = to_d_val(svc, row[WB_COL_TOTAL])
        sheet_profit = to_d_val(svc, row[WB_COL_PROFIT])
        next if sheet_total.zero? && sheet_profit.zero?

        label = "#{tab_name} 行#{idx + 2} #{sku_code}(#{dm})"
        checked += 1

        unless approx_ok?(sheet_total, pc.wb_total_cost_cny)
          tab_failures << "#{label} 最终成本: Sheet=#{sheet_total.round(2)}, 计算=#{pc.wb_total_cost_cny.round(2)}, 差=#{(sheet_total.to_f - pc.wb_total_cost_cny.to_f).abs.round(2)}"
        end
        unless approx_ok?(sheet_profit, pc.profit_cny)
          tab_failures << "#{label} 利润:     Sheet=#{sheet_profit.round(2)}, 计算=#{pc.profit_cny.round(2)}, 差=#{(sheet_profit.to_f - pc.profit_cny.to_f).abs.round(2)}"
        end
      end

      failures.concat(tab_failures)
      summary[tab_name] = { checked: checked, failures: tab_failures.length }
    end

    # ── Ozon Tab 通用验证 ─────────────────────────────────────────────────────

    def check_ozon_tab(svc, tab_name, failures, summary)
      config = GoogleSheets::CostImportService::TAB_CONFIGS[tab_name]
      rows   = svc.send(:fetch_rows, tab_name)
      checked      = 0
      tab_failures = []

      rows.each_with_index do |row, idx|
        sku_code, = svc.send(:resolve_sku, row, config)
        next unless sku_code

        cost_attrs     = svc.send(:parse_ozon_cost, row)
        platform_attrs = svc.send(:parse_ozon_platform, row, config).merge(
          platform: 'ozon', delivery_mode: config[:delivery_mode], company_type: 'general'
        )

        pc = build_pair(svc, cost_attrs, platform_attrs)

        sheet_rf_total  = to_d_val(svc, row[OZ_COL_RF_TOTAL])
        sheet_by_total  = to_d_val(svc, row[OZ_COL_BY_TOTAL])
        sheet_rf_profit = to_d_val(svc, row[OZ_COL_RF_PROF])
        sheet_by_profit = to_d_val(svc, row[OZ_COL_BY_PROF])
        next if sheet_rf_total.zero? && sheet_rf_profit.zero?

        label = "#{tab_name} 行#{idx + 2} #{sku_code}"
        checked += 1

        { "RF最终成本" => [sheet_rf_total, pc.ozon_total_cost_rf_cny],
          "BY最终成本" => [sheet_by_total, pc.ozon_total_cost_by_cny],
          "RF毛利"     => [sheet_rf_profit, pc.ozon_profit_rf_cny],
          "BY毛利"     => [sheet_by_profit, pc.ozon_profit_by_cny] }.each do |name, (exp, act)|
          unless approx_ok?(exp, act)
            tab_failures << "#{label} #{name}: Sheet=#{exp.to_f.round(2)}, 计算=#{act.to_f.round(2)}, 差=#{(exp.to_f - act.to_f).abs.round(2)}"
          end
        end
      end

      failures.concat(tab_failures)
      summary[tab_name] = { checked: checked, failures: tab_failures.length }
    end

    # ── 运行四个 Tab ──────────────────────────────────────────────────────────

    check_wb_tab(svc, '成本模板确认1', failures, summary)
    check_wb_tab(svc, '成本模板确认2', failures, summary)
    check_ozon_tab(svc, '成本模板确认3', failures, summary)
    check_ozon_tab(svc, '成本模板确认4', failures, summary)

    # ── 输出 ─────────────────────────────────────────────────────────────────

    puts "\n#{'=' * 60}"
    puts "成本验证结果（公差 ±#{TOLERANCE} CNY，逐行重建计算）"
    puts '=' * 60
    summary.each do |tab, s|
      status = s[:failures].zero? ? '✓' : '✗'
      puts "#{status} #{tab}: 验证 #{s[:checked]} 行，#{s[:failures]} 条不符"
    end

    if failures.any?
      puts "\n不符明细："
      failures.each { |f| puts "  #{f}" }
      puts "\n共 #{failures.length} 条不符"
      exit 1
    else
      total = summary.values.sum { |s| s[:checked] }
      puts "\n全部 #{total} 条验证通过 ✓"
    end
  end
end
