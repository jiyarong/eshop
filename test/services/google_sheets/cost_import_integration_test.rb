require 'test_helper'

# 集成测试：Google Sheet 四个 Tab 的计算结果 vs. 数据库方法
#
# 每行：从 Sheet 读原始数值和 Sheet 侧公式结果列，在 DB 找对应
# Ec::SkuPlatformCost 记录，用 ±1 CNY 公差断言两侧一致。
#
# WB  结果列：AH(33)=最终成本, AI(34)=利润
# Ozon结果列：AI(34)=RF最终成本, AJ(35)=BY最终成本, AK(36)=RF毛利, AL(37)=BY毛利
#
# 运行：bundle exec rails test test/services/google_sheets/cost_import_integration_test.rb

module GoogleSheets
  class CostImportIntegrationTest < ActiveSupport::TestCase
    WB_COL_TOTAL    = 33  # AH
    WB_COL_PROFIT   = 34  # AI
    OZ_COL_RF_TOTAL = 34  # AI
    OZ_COL_BY_TOTAL = 35  # AJ
    OZ_COL_RF_PROF  = 36  # AK
    OZ_COL_BY_PROF  = 37  # AL

    def setup
      @svc = CostImportService.new
    end

    # ── 断言 ──────────────────────────────────────────────────────────────────

    def assert_approx(expected, actual, label)
      exp = expected.to_f
      act = actual.to_f
      diff = (exp - act).abs
      assert diff <= 1.0,
        "#{label}: Sheet=#{exp.round(2)}, DB=#{act.round(2)}, 差=#{diff.round(4)}"
    end

    # ── 委托私有方法 ──────────────────────────────────────────────────────────

    def fetch_rows(tab)   = @svc.send(:fetch_rows, tab)
    def resolve(row, cfg) = @svc.send(:resolve_sku, row, cfg)
    def to_d(v)           = @svc.send(:to_d, v)

    # ── WB 通用断言 ───────────────────────────────────────────────────────────

    def check_wb_tab(tab_name, company_type)
      config  = CostImportService::TAB_CONFIGS[tab_name]
      rows    = fetch_rows(tab_name)
      checked = 0

      rows.each_with_index do |row, idx|
        sku_code, delivery_mode = resolve(row, config)
        next unless sku_code

        dm = delivery_mode || config[:delivery_mode] || 'fbo'
        pc = Ec::SkuPlatformCost.find_by(
          sku_code:, platform: 'wb', delivery_mode: dm, company_type:
        )
        next unless pc

        sheet_total  = to_d(row[WB_COL_TOTAL])
        sheet_profit = to_d(row[WB_COL_PROFIT])
        next if sheet_total.zero? && sheet_profit.zero?

        label = "#{tab_name} 行#{idx + 2} #{sku_code}(#{dm})"
        assert_approx sheet_total,  pc.wb_total_cost_cny, "#{label} 最终成本"
        assert_approx sheet_profit, pc.profit_cny,         "#{label} 利润"
        checked += 1
      end

      assert checked > 0, "#{tab_name} 没有找到任何可比对的行（DB 可能未导入）"
      puts "  #{tab_name}: 校验 #{checked} 行 ✓"
    end

    # ── Ozon 通用断言 ─────────────────────────────────────────────────────────

    def check_ozon_tab(tab_name)
      config  = CostImportService::TAB_CONFIGS[tab_name]
      rows    = fetch_rows(tab_name)
      checked = 0

      rows.each_with_index do |row, idx|
        sku_code, = resolve(row, config)
        next unless sku_code

        dm = config[:delivery_mode]
        pc = Ec::SkuPlatformCost.find_by(
          sku_code:, platform: 'ozon', delivery_mode: dm, company_type: 'general'
        )
        next unless pc

        sheet_rf_total  = to_d(row[OZ_COL_RF_TOTAL])
        sheet_by_total  = to_d(row[OZ_COL_BY_TOTAL])
        sheet_rf_profit = to_d(row[OZ_COL_RF_PROF])
        sheet_by_profit = to_d(row[OZ_COL_BY_PROF])
        next if sheet_rf_total.zero? && sheet_rf_profit.zero?

        label = "#{tab_name} 行#{idx + 2} #{sku_code}"
        assert_approx sheet_rf_total,  pc.ozon_total_cost_rf_cny, "#{label} RF最终成本"
        assert_approx sheet_by_total,  pc.ozon_total_cost_by_cny, "#{label} BY最终成本"
        assert_approx sheet_rf_profit, pc.ozon_profit_rf_cny,     "#{label} RF毛利"
        assert_approx sheet_by_profit, pc.ozon_profit_by_cny,     "#{label} BY毛利"
        checked += 1
      end

      assert checked > 0, "#{tab_name} 没有找到任何可比对的行（DB 可能未导入）"
      puts "  #{tab_name}: 校验 #{checked} 行 ✓"
    end

    # ── 四个 Tab ──────────────────────────────────────────────────────────────

    test '成本模板确认1 WB大公司 Sheet vs DB' do
      check_wb_tab('成本模板确认1', 'general')
    end

    test '成本模板确认2 WB小公司 Sheet vs DB' do
      check_wb_tab('成本模板确认2', 'small')
    end

    test '成本模板确认3 Ozon FBO Sheet vs DB' do
      check_ozon_tab('成本模板确认3')
    end

    test '成本模板确认4 Ozon FBS Sheet vs DB' do
      check_ozon_tab('成本模板确认4')
    end
  end
end
