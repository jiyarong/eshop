# 成本计算逻辑单元测试
# 数据来源：Google Sheet "1JbhVK4adukKD2b2KnAHHbruCsB9Y9G7xixFkVqMTrpg"
#   成本模板确认1（WB 大公司）→ test_wb_general_*
#   成本模板确认2（WB 小公司）→ test_wb_small_*
#   成本模板确认3（Ozon FBO） → test_ozon_fbo_*
#   成本模板确认4（Ozon FBS） → test_ozon_fbs_*
#
# 公差：±1 CNY（Sheet 中间步骤存在展示取整，累积误差在此范围内）

require 'test_helper'

module Ec
  class SkuPlatformCostTest < ActiveSupport::TestCase
    # ── 辅助：构造内存对象，绕过 DB ──────────────────────────────────────────────

    def build_cost(attrs = {})
      c = Ec::SkuCost.new(attrs)
      # customs_duty_rate / import_vat_rate 默认如模板公式
      c.customs_duty_rate ||= 0.10
      c.import_vat_rate   ||= 0.20
      c
    end

    def build_platform_cost(cost_obj, attrs = {})
      pc = Ec::SkuPlatformCost.new(attrs)
      pc.define_singleton_method(:cost) { cost_obj }
      pc
    end

    # 断言两个值在 ±1 CNY 以内
    def assert_approx(expected, actual, msg = nil)
      diff = (expected.to_f - actual.to_f).abs
      assert diff <= 1.0, "#{msg}：期望 #{expected}，实际 #{actual}，差 #{diff.round(4)}"
    end

    # ── 成本模板确认1：WB 大公司（20% НДС），KJ-217-GD FBS ─────────────────────
    # Sheet 公式驱动行，结果可精确对照

    def wb_general_cost
      build_cost(
        purchase_price_cny: 270,
        freight_to_by_cny:  22.5,
        customs_misc_cny:   2.81,
        # 关税公式 = E*0.1 = 27；进口增值税 = (E+H)*0.2 = (270+27)*0.2 = 59.4
        customs_duty_rate:  0.10,
        import_vat_rate:    0.20,
        pkg_length_cm:      85,
        pkg_width_cm:       52,
        pkg_height_cm:      5,
        damage_rate:        0,
        misc_cost_cny:      2,
      )
    end

    def wb_general_platform_cost(cost_obj)
      build_platform_cost(cost_obj,
        platform:              'wb',
        delivery_mode:         'fbs',
        company_type:          'general',
        wb_logistics_base_rub: 60,    # Tab1 公式 +46+14
        logistics_coeff:       1.55,
        fbo_delivery_cny:      8.07,  # (200 * 2.4201) / 60，来自 Sheet 实际值
        acquiring_rate:        0.031,
        ad_spend_rate:         0.15,
        commission_rate:       0.218,
        sales_tax_rate:        nil,   # general 用 20%НДС 公式
        exchange_rate_rub_cny: 11.7,
        target_price_rub:      17000,
        storage_30d_cny:       0,
      )
    end

    test 'WB general - 货物成本' do
      c = wb_general_cost
      # 270 + 22.5 + 2.81 + 27 + 59.4 = 381.71
      assert_approx 381.71, c.goods_cost_cny, '货物成本'
    end

    test 'WB general - 包装升量' do
      c = wb_general_cost
      # 85×52×5/1000 = 22.1 → ceil = 23
      assert_equal 23, c.pkg_volume_l.ceil, '升量取整'
    end

    test 'WB general - 基础运费 RUB' do
      pc = wb_general_platform_cost(wb_general_cost)
      # (23-1)*14+60 = 368
      assert_approx 368, pc.wb_base_logistics_rub, '基础运费'
    end

    test 'WB general - 平台运费 CNY' do
      pc = wb_general_platform_cost(wb_general_cost)
      # 368 * 1.55 / 11.7 ≈ 48.75
      assert_approx 48.8, pc.wb_platform_freight_cny, '平台运费'
    end

    test 'WB general - 返程费 CNY' do
      pc = wb_general_platform_cost(wb_general_cost)
      # 48.75 * 18/82 ≈ 10.70
      assert_approx 10.70, pc.wb_return_cny, '返程费'
    end

    test 'WB general - 退货运费 CNY' do
      pc = wb_general_platform_cost(wb_general_cost)
      # 50/11.7 * 18/82 ≈ 0.94
      assert_approx 0.94, pc.wb_fixed_return_cny, '退货运费'
    end

    test 'WB general - 收单费 CNY' do
      pc = wb_general_platform_cost(wb_general_cost)
      # 17000/11.7 * 0.031 ≈ 45.04
      assert_approx 45.04, pc.wb_acquiring_cny, '收单费'
    end

    test 'WB general - 广告费 CNY' do
      pc = wb_general_platform_cost(wb_general_cost)
      # 17000/11.7 * 0.15 ≈ 217.95
      assert_approx 217.95, pc.wb_ad_spend_cny, '广告费'
    end

    test 'WB general - 佣金 CNY' do
      pc = wb_general_platform_cost(wb_general_cost)
      # 17000/11.7 * 0.218 ≈ 316.75
      assert_approx 317, pc.wb_commission_cny, '佣金'
    end

    test 'WB general - 销售税 CNY (20% НДС)' do
      pc = wb_general_platform_cost(wb_general_cost)
      # 17000/11.7 * 20/120 - 59.4 ≈ 182.8
      assert_approx 182.8, pc.wb_sales_tax_cny, '20%销售税'
    end

    test 'WB general - 最终成本 CNY' do
      pc = wb_general_platform_cost(wb_general_cost)
      # Sheet AH3 = 1,215
      assert_approx 1215, pc.wb_total_cost_cny, '最终成本'
    end

    test 'WB general - 利润 CNY' do
      pc = wb_general_platform_cost(wb_general_cost)
      # Sheet AI3 = 238
      assert_approx 238, pc.profit_cny, '利润'
    end

    # ── 成本模板确认2：WB 小公司（6% УСН），KJ-226 FBO Рязань ──────────────────

    def wb_small_cost
      build_cost(
        purchase_price_cny: 210,
        freight_to_by_cny:  22.5,
        customs_misc_cny:   2.81,
        customs_duty_rate:  0.10,
        import_vat_rate:    0.20,
        pkg_length_cm:      77,
        pkg_width_cm:       17,
        pkg_height_cm:      7,
        damage_rate:        0,
        misc_cost_cny:      2,
      )
    end

    def wb_small_platform_cost(cost_obj)
      build_platform_cost(cost_obj,
        platform:              'wb',
        delivery_mode:         'fbo',
        company_type:          'small',
        wb_logistics_base_rub: 46,    # Tab2 公式，只有 46 基础
        logistics_coeff:       1.25,
        fbo_delivery_cny:      10,    # 手填
        acquiring_rate:        0.031,
        ad_spend_rate:         0.07,
        commission_rate:       0.175,
        sales_tax_rate:        0.06,  # 6% УСН
        exchange_rate_rub_cny: 11.7,
        target_price_rub:      11000,
        storage_30d_cny:       0,
      )
    end

    test 'WB small - 货物成本' do
      c = wb_small_cost
      # 210 + 22.5 + 2.81 + 21 + 46.2 = 302.51
      assert_approx 302.5, c.goods_cost_cny, '货物成本'
    end

    test 'WB small - 基础运费 RUB (base=46)' do
      pc = wb_small_platform_cost(wb_small_cost)
      # 77*17*7/1000=9.163 → ceil=10; (10-1)*14+46 = 172
      assert_approx 172, pc.wb_base_logistics_rub, '基础运费'
    end

    test 'WB small - 平台运费 CNY' do
      pc = wb_small_platform_cost(wb_small_cost)
      # 172 * 1.25 / 11.7 ≈ 18.38
      assert_approx 18.4, pc.wb_platform_freight_cny, '平台运费'
    end

    test 'WB small - 销售税 CNY (6% УСН)' do
      pc = wb_small_platform_cost(wb_small_cost)
      # 11000/11.7 * 0.06 ≈ 56.41
      assert_approx 56.4, pc.wb_sales_tax_cny, '6%营业额税'
    end

    test 'WB small - 最终成本 CNY' do
      pc = wb_small_platform_cost(wb_small_cost)
      # Sheet AH2 = 654
      assert_approx 654, pc.wb_total_cost_cny, '最终成本'
    end

    test 'WB small - 利润 CNY' do
      pc = wb_small_platform_cost(wb_small_cost)
      # Sheet AI2 = 286
      assert_approx 286, pc.profit_cny, '利润'
    end

    # ── 成本模板确认3：Ozon FBO，Алкотестер ─────────────────────────────────────

    def ozon_fbo_cost
      build_cost(
        purchase_price_cny:   25,
        freight_to_by_cny:    nil,
        customs_misc_cny:     nil,
        customs_duty_rate:    0,
        import_vat_rate:      0.20,
        pkg_volume_override_l: 0.26,  # 直接填升量
        damage_rate:          0,
        misc_cost_cny:        0,
      )
    end

    def ozon_fbo_platform_cost(cost_obj)
      build_platform_cost(cost_obj,
        platform:                 'ozon',
        delivery_mode:            'fbo',
        company_type:             'general',
        # 去程费率（FBO）
        ozon_fwd_base_rub:        87.44,
        ozon_fwd_per_liter_rub:   15.25,
        # 返程费率（FBO/FBS 均用 FBO 费率）
        ozon_ret_base_rub:        87.44,
        ozon_ret_per_liter_rub:   15.25,
        ozon_warehouse_op_rub:    25,
        ozon_fbs_delivery_rub:    nil,
        commission_rate:          0.38,
        acquiring_rate:           0.02,
        ad_spend_rate:            0.15,
        exchange_rate_rub_cny:    11.7,
        target_price_rf_rub:      1600,
        target_price_by_rub:      3000,
      )
    end

    test 'Ozon FBO - 货物成本' do
      c = ozon_fbo_cost
      # 25 + 0 + 0 + 0 + 5 = 30
      assert_approx 30, c.goods_cost_cny, '货物成本'
    end

    test 'Ozon FBO - 升量取整' do
      c = ozon_fbo_cost
      # 0.26 → ceil = 1
      assert_equal 1, c.pkg_volume_l.ceil, '升量取整'
    end

    test 'Ozon FBO - 去程运费 RUB' do
      pc = ozon_fbo_platform_cost(ozon_fbo_cost)
      # (1-3)*15.25+87.44 = -30.5+87.44 = 56.94
      assert_approx 56.94, pc.ozon_fwd_rub, '去程运费'
    end

    test 'Ozon FBO - 退货折算 RUB' do
      pc = ozon_fbo_platform_cost(ozon_fbo_cost)
      # (56.94*2 + 56.94*2)/8 = 28.47
      assert_approx 28.47, pc.ozon_return_amortized_rub, '退货折算'
    end

    test 'Ozon FBO - 平台运费 CNY' do
      pc = ozon_fbo_platform_cost(ozon_fbo_cost)
      # (56.94 + 28.47 + 25 + 12.5) / 11.7 = 122.91/11.7 ≈ 10.50
      assert_approx 10.5, pc.ozon_platform_freight_cny, '平台运费'
    end

    test 'Ozon FBO - 佣金 CNY (基于俄罗斯售价)' do
      pc = ozon_fbo_platform_cost(ozon_fbo_cost)
      # 1600/11.7 * 0.38 ≈ 52.0
      assert_approx 52.0, pc.ozon_commission_cny, '佣金'
    end

    test 'Ozon FBO - 收单费 CNY' do
      pc = ozon_fbo_platform_cost(ozon_fbo_cost)
      # 1600/11.7 * 0.02 ≈ 2.74
      assert_approx 2.7, pc.ozon_acquiring_cny, '收单费'
    end

    test 'Ozon FBO - 卖俄罗斯最终成本 CNY' do
      pc = ozon_fbo_platform_cost(ozon_fbo_cost)
      # Sheet AI2 = 110.7
      assert_approx 110.7, pc.ozon_total_cost_rf_cny, '卖俄罗斯最终成本'
    end

    test 'Ozon FBO - 白俄销售增值税 CNY' do
      pc = ozon_fbo_platform_cost(ozon_fbo_cost)
      # 3000/11.7 * 20/120 - 5 ≈ 37.74
      assert_approx 37.74, pc.ozon_sales_tax_by_cny, '白俄增值税'
    end

    test 'Ozon FBO - 卖白俄最终成本 CNY' do
      pc = ozon_fbo_platform_cost(ozon_fbo_cost)
      # Sheet AJ2 = 153.5
      assert_approx 153.5, pc.ozon_total_cost_by_cny, '卖白俄最终成本'
    end

    test 'Ozon FBO - 俄罗斯毛利 CNY' do
      pc = ozon_fbo_platform_cost(ozon_fbo_cost)
      # Sheet AK2 = 26.0
      assert_approx 26.0, pc.ozon_profit_rf_cny, '俄罗斯毛利'
    end

    test 'Ozon FBO - 白俄毛利 CNY' do
      pc = ozon_fbo_platform_cost(ozon_fbo_cost)
      # Sheet AL2 = 103.0
      assert_approx 103.0, pc.ozon_profit_by_cny, '白俄毛利'
    end

    # ── 成本模板确认4：Ozon FBS，Полотенцесушитель с полкой (золото) ─────────────

    def ozon_fbs_cost
      build_cost(
        purchase_price_cny:   270,
        freight_to_by_cny:    22.5,
        customs_misc_cny:     2.81,
        customs_duty_rate:    0.10,   # 27 = 270*0.1
        import_vat_rate:      0.20,   # 59.4 = (270+27)*0.2
        pkg_volume_override_l: 22.1,
        damage_rate:          0,
        misc_cost_cny:        0,
      )
    end

    def ozon_fbs_platform_cost(cost_obj)
      build_platform_cost(cost_obj,
        platform:                 'ozon',
        delivery_mode:            'fbs',
        company_type:             'general',
        # 去程费率（FBS 更贵）
        ozon_fwd_base_rub:        117.94,
        ozon_fwd_per_liter_rub:   23.39,
        # 返程费率（固定用 FBO 费率）
        ozon_ret_base_rub:        87.44,
        ozon_ret_per_liter_rub:   15.25,
        ozon_warehouse_op_rub:    30,
        ozon_fbs_delivery_rub:    25,
        commission_rate:          0.075,
        acquiring_rate:           0.01,
        ad_spend_rate:            0.15,
        exchange_rate_rub_cny:    11.7,
        target_price_rf_rub:      14000,
        target_price_by_rub:      16800,
      )
    end

    test 'Ozon FBS - 货物成本' do
      c = ozon_fbs_cost
      # 270+22.5+2.81+27+59.4 = 381.71
      assert_approx 381.71, c.goods_cost_cny, '货物成本'
    end

    test 'Ozon FBS - 升量取整' do
      c = ozon_fbs_cost
      # 22.1 → ceil = 23
      assert_equal 23, c.pkg_volume_l.ceil, '升量取整'
    end

    test 'Ozon FBS - 去程运费 RUB' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # (23-3)*23.39+117.94 = 467.8+117.94 = 585.74
      assert_approx 585.74, pc.ozon_fwd_rub, '去程运费'
    end

    test 'Ozon FBS - 返程运费 RUB (FBO 费率)' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # (23-3)*15.25+87.44 = 305+87.44 = 392.44
      assert_approx 392.44, pc.ozon_ret_rub, '返程运费'
    end

    test 'Ozon FBS - 退货折算 RUB' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # (585.74*2 + 392.44*2)/8 = 244.545
      assert_approx 244.55, pc.ozon_return_amortized_rub, '退货折算'
    end

    test 'Ozon FBS - 仓库费用合计 RUB' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # op(30) + delivery(25) + delivery/2(12.5) = 67.5
      assert_approx 67.5, pc.ozon_warehouse_total_rub, '仓库费用'
    end

    test 'Ozon FBS - 平台运费 CNY' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # (585.74+244.55+67.5)/11.7 = 897.79/11.7 ≈ 76.7
      assert_approx 76.7, pc.ozon_platform_freight_cny, '平台运费'
    end

    test 'Ozon FBS - 佣金 CNY (7.5%)' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # 14000/11.7 * 0.075 ≈ 89.7
      assert_approx 89.7, pc.ozon_commission_cny, '佣金'
    end

    test 'Ozon FBS - 收单费 CNY (1%)' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # 14000/11.7 * 0.01 ≈ 12.0
      assert_approx 12.0, pc.ozon_acquiring_cny, '收单费'
    end

    test 'Ozon FBS - 广告费 CNY (15%)' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # 14000/11.7 * 0.15 ≈ 179.5
      assert_approx 179.5, pc.ozon_ad_spend_cny, '广告费'
    end

    test 'Ozon FBS - 卖俄罗斯最终成本 CNY' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # Sheet AI2 = 680.2
      assert_approx 680.2, pc.ozon_total_cost_rf_cny, '卖俄罗斯最终成本'
    end

    test 'Ozon FBS - 白俄销售增值税 CNY' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # 16800/11.7 * 20/120 - 59.4 ≈ 179.92
      assert_approx 179.92, pc.ozon_sales_tax_by_cny, '白俄增值税'
    end

    test 'Ozon FBS - 卖白俄最终成本 CNY' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # Sheet AJ2 = 919.6
      assert_approx 919.6, pc.ozon_total_cost_by_cny, '卖白俄最终成本'
    end

    test 'Ozon FBS - 俄罗斯毛利 CNY' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # Sheet AK2 = 516.3
      assert_approx 516.3, pc.ozon_profit_rf_cny, '俄罗斯毛利'
    end

    test 'Ozon FBS - 白俄毛利 CNY' do
      pc = ozon_fbs_platform_cost(ozon_fbs_cost)
      # Sheet AL2 = 516.3
      assert_approx 516.3, pc.ozon_profit_by_cny, '白俄毛利'
    end
  end
end
