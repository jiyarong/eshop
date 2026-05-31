module Ec
  class SkuPlatformCost < ApplicationRecord
    self.table_name = 'ec_sku_platform_costs'

    belongs_to :sku,  class_name: 'Ec::Sku',     foreign_key: :sku_code, primary_key: :sku_code
    belongs_to :cost, class_name: 'Ec::SkuCost',  foreign_key: :sku_code, primary_key: :sku_code

    PLATFORMS      = %w[wb ozon].freeze
    DELIVERY_MODES = %w[fbo fbs].freeze
    COMPANY_TYPES  = %w[general small].freeze

    WB_RETURN_RATIO       = (18.0 / 82).freeze  # 返程费率默认值（各行实际值从 Sheet 导入）
    WB_FIXED_RETURN_RUB   = 50.freeze            # WB 固定退货运费(卢布)

    validates :sku_code,      presence: true
    validates :platform,      inclusion: { in: PLATFORMS }
    validates :delivery_mode, inclusion: { in: DELIVERY_MODES }
    validates :company_type,  inclusion: { in: COMPANY_TYPES }
    validates :sku_code, uniqueness: { scope: %i[platform delivery_mode company_type] }

    scope :wb,      -> { where(platform: 'wb') }
    scope :ozon,    -> { where(platform: 'ozon') }
    scope :fbo,     -> { where(delivery_mode: 'fbo') }
    scope :fbs,     -> { where(delivery_mode: 'fbs') }
    scope :general, -> { where(company_type: 'general') }
    scope :small,   -> { where(company_type: 'small') }

    # ── 统一接口（两平台均可调用） ──────────────────────────────────────────────

    # 计划售价 CNY（WB 用 target_price_rub；Ozon 用 RF 价）
    def revenue_cny
      price_rub = platform == 'wb' ? target_price_rub : target_price_rf_rub
      return 0 unless price_rub && exchange_rate_rub_cny&.nonzero?
      (price_rub / exchange_rate_rub_cny).round(4)
    end

    # 最终成本 CNY（WB = 单一市场；Ozon = 俄罗斯市场）
    def total_cost_cny
      platform == 'wb' ? wb_total_cost_cny : ozon_total_cost_rf_cny
    end

    def profit_cny
      (revenue_cny - total_cost_cny).round(4)
    end

    def margin
      return 0 if revenue_cny.zero?
      (profit_cny / revenue_cny).round(6)
    end

    def margin_pct
      "#{(margin * 100).round(2)}%"
    end

    # ── WB 专用计算 ──────────────────────────────────────────────────────────────

    # 基础运费 RUB：(升量取整-1)×14 + base（Tab1=60, Tab2=46）
    def wb_base_logistics_rub
      vol_ceil = cost&.pkg_volume_l.to_d.ceil
      return 0 if vol_ceil.zero?
      base = wb_logistics_base_rub&.positive? ? wb_logistics_base_rub.to_d : 60.to_d
      ((vol_ceil - 1) * 14 + base).to_d
    end

    # 平台运费 CNY（不含 FBO 到仓费）
    def wb_platform_freight_cny
      return 0 unless logistics_coeff && exchange_rate_rub_cny&.nonzero?
      (wb_base_logistics_rub * logistics_coeff.to_d / exchange_rate_rub_cny).round(4)
    end

    # 返程费 CNY = 平台运费 × 退货率（各 SKU 不同，从 Sheet 导入）
    def wb_return_cny
      ratio = wb_return_rate&.positive? ? wb_return_rate.to_d : WB_RETURN_RATIO
      (wb_platform_freight_cny * ratio).round(4)
    end

    # 退货运费 CNY = 50 RUB ÷ 汇率 × 固定退货率（同样从 Sheet 导入）
    def wb_fixed_return_cny
      return 0 unless exchange_rate_rub_cny&.nonzero?
      ratio = wb_fixed_return_rate&.positive? ? wb_fixed_return_rate.to_d : WB_RETURN_RATIO
      (WB_FIXED_RETURN_RUB / exchange_rate_rub_cny * ratio).round(4)
    end

    def wb_acquiring_cny
      (revenue_cny * acquiring_rate.to_d).round(4)
    end

    def wb_commission_cny
      (revenue_cny * commission_rate.to_d).round(4)
    end

    def wb_ad_spend_cny
      (revenue_cny * ad_spend_rate.to_d).round(4)
    end

    # 销售税 CNY
    #   general(大公司 20% НДС)：售价×20/120 − 进口增值税（销项抵进项）
    #   small  (小公司 6% УСН)  ：售价×6%
    def wb_sales_tax_cny
      if company_type == 'general'
        (revenue_cny * 20.0 / 120 - cost&.import_vat_cny.to_d).round(4)
      else
        (revenue_cny * sales_tax_rate.to_d).round(4)
      end
    end

    def wb_damage_cny
      (cost&.goods_cost_cny.to_d * cost&.damage_rate.to_d).round(4)
    end

    def wb_total_cost_cny
      [
        cost&.goods_cost_cny.to_d,   # 货物成本
        fbo_delivery_cny.to_d,        # FBO 到仓费
        wb_platform_freight_cny,      # 平台运费
        wb_return_cny,                # 返程费
        wb_fixed_return_cny,          # 退货运费
        storage_30d_cny.to_d,         # 仓储费
        wb_acquiring_cny,             # 收单费
        wb_ad_spend_cny,              # 广告费
        wb_damage_cny,                # 货损
        cost&.misc_cost_cny.to_d,    # 杂费
        wb_commission_cny,            # 佣金
        wb_sales_tax_cny,             # 销售税
      ].sum.round(4)
    end

    # ── Ozon 专用计算 ─────────────────────────────────────────────────────────────

    def ozon_vol_ceil
      cost&.pkg_volume_l.to_d.ceil
    end

    # 去程运费 RUB：(升量取整-3)×每升单价 + 前3升基础费
    # 当升量<3时，(vol-3)为负，自然折减基础费，与 Sheet 公式一致
    def ozon_fwd_rub
      extra = ozon_vol_ceil - 3
      (ozon_fwd_base_rub.to_d + extra * ozon_fwd_per_liter_rub.to_d).round(4)
    end

    # 返程运费 RUB（FBS 也使用 FBO 返程费率）
    def ozon_ret_rub
      extra = ozon_vol_ceil - 3
      (ozon_ret_base_rub.to_d + extra * ozon_ret_per_liter_rub.to_d).round(4)
    end

    # 退货运费折算 = (去程×2 + 返程×2) ÷ 8
    def ozon_return_amortized_rub
      ((ozon_fwd_rub * 2 + ozon_ret_rub * 2) / 8).round(4)
    end

    # 仓库费用合计 RUB
    #   FBO：操作费 + 操作费×(2+2)/8  = 操作费 × 1.5
    #   FBS：操作费 + 配送费 + 配送费×(2+2)/8 = 操作费 + 配送费 × 1.5
    def ozon_warehouse_total_rub
      op       = ozon_warehouse_op_rub.to_d
      delivery = ozon_fbs_delivery_rub.to_d
      if delivery_mode == 'fbs'
        op + delivery + (delivery * 4 / 8)
      else
        op + (op * 4 / 8)
      end
    end

    # 平台运费 CNY（含退货折算和仓库费用）
    def ozon_platform_freight_cny
      return 0 unless exchange_rate_rub_cny&.nonzero?
      total_rub = ozon_fwd_rub + ozon_return_amortized_rub + ozon_warehouse_total_rub
      (total_rub / exchange_rate_rub_cny).round(4)
    end

    # 俄罗斯售价 CNY
    def ozon_revenue_rf_cny
      return 0 unless target_price_rf_rub && exchange_rate_rub_cny&.nonzero?
      (target_price_rf_rub / exchange_rate_rub_cny).round(4)
    end

    # 白俄售价 CNY
    def ozon_revenue_by_cny
      return 0 unless target_price_by_rub && exchange_rate_rub_cny&.nonzero?
      (target_price_by_rub / exchange_rate_rub_cny).round(4)
    end

    # 平台费用（佣金+收单+广告）均基于俄罗斯售价
    def ozon_commission_cny
      (ozon_revenue_rf_cny * commission_rate.to_d).round(4)
    end

    def ozon_acquiring_cny
      (ozon_revenue_rf_cny * acquiring_rate.to_d).round(4)
    end

    def ozon_ad_spend_cny
      (ozon_revenue_rf_cny * ad_spend_rate.to_d).round(4)
    end

    # 白俄销售增值税 CNY = 白俄售价×20/120 − 进口增值税（进项抵扣）
    def ozon_sales_tax_by_cny
      (ozon_revenue_by_cny * 20.0 / 120 - cost&.import_vat_cny.to_d).round(4)
    end

    # 卖俄罗斯：进口增值税可全额抵扣，货物成本只计 ex-VAT 部分
    def ozon_total_cost_rf_cny
      [
        cost&.goods_cost_cny.to_d - cost&.import_vat_cny.to_d,
        ozon_platform_freight_cny,
        ozon_commission_cny,
        ozon_acquiring_cny,
        ozon_ad_spend_cny,
      ].sum.round(4)
    end

    # 卖白俄：货物成本全额计入，再加销售增值税（进项抵扣已含在 ozon_sales_tax_by_cny 里）
    def ozon_total_cost_by_cny
      [
        cost&.goods_cost_cny.to_d,
        ozon_platform_freight_cny,
        ozon_commission_cny,
        ozon_acquiring_cny,
        ozon_ad_spend_cny,
        ozon_sales_tax_by_cny,
      ].sum.round(4)
    end

    def ozon_profit_rf_cny
      (ozon_revenue_rf_cny - ozon_total_cost_rf_cny).round(4)
    end

    def ozon_profit_by_cny
      (ozon_revenue_by_cny - ozon_total_cost_by_cny).round(4)
    end

    def ozon_margin_rf
      return 0 if ozon_revenue_rf_cny.zero?
      (ozon_profit_rf_cny / ozon_revenue_rf_cny).round(6)
    end

    def ozon_margin_by
      return 0 if ozon_revenue_by_cny.zero?
      (ozon_profit_by_cny / ozon_revenue_by_cny).round(6)
    end
  end
end
