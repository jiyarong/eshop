module Ec
  # WB 利润归集：按 (nmId, reportType) 维度聚合一个自然周的利润。
  #
  # 货币说明：
  #   财务明细（结算/费用）以 BYN 结算；仓储/广告以 RUB 结算；货物成本以 CNY 计。
  #   所有输出字段统一换算为 CNY：
  #     BYN → CNY：× rate_byn_rub ÷ rate_cny_rub
  #     RUB → CNY：÷ rate_cny_rub
  #
  # 税制从 account.company_type 自动读取：small → usn(6%)，general → osn(VAT 20%)
  #
  # 用法:
  #   svc = Ec::WbProfitAttribution.new(
  #     account_id:   2,
  #     from_date:    "2026-05-08",
  #     to_date:      "2026-05-14",
  #     rate_cny_rub: 10.93,   # CBR 原始汇率（服务内部 ×1.03 换算货物成本）
  #     rate_byn_rub: 26.41   # 1 BYN = X RUB（来自 CBR 或手动填入）
  #   ).call
  #
  #   svc.results      # Array of Hash，每个 nmId×reportType 一条，金额均为 CNY
  #   svc.unallocated  # 未归属行汇总
  #   svc.summary      # 全局汇总（CNY）
  class WbProfitAttribution
    attr_reader :results, :unallocated, :summary

    REPORT_TYPE_BLR    = 1  # 白俄本地
    REPORT_TYPE_EXPORT = 2  # 出口

    TAX_REGIME_MAP = { 'general' => 'osn', 'small' => 'usn' }.freeze

    def initialize(account_id:, from_date:, to_date:, rate_cny_rub:, rate_byn_rub:)
      @account      = RawWb::SellerAccount.find(account_id)
      @account_id   = account_id
      @from_date    = from_date.to_date
      @to_date      = to_date.to_date
      @rate_cny_rub = rate_cny_rub.to_f   # 1 CNY = X RUB
      @rate_byn_rub = rate_byn_rub.to_f   # 1 BYN = X RUB
      @tax_regime   = TAX_REGIME_MAP.fetch(@account.company_type.to_s, 'usn')
    end

    def call
      load_finance_rows
      build_shk_nm_mapping
      attribute_costs
      load_storage
      load_ad_costs
      load_goods_costs
      compute_profit
      self
    end

    private

    # ─── 货币换算 ─────────────────────────────────────────────────────────────────
    # 所有输出字段统一使用 BYN（白俄卢布），与 WB 财务报表原始结算货币一致。

    def byn_to_cny(v) = v.to_f * @rate_byn_rub / @rate_cny_rub
    def rub_to_cny(v) = v.to_f / @rate_cny_rub
    def rub_to_byn(v) = v.to_f / @rate_byn_rub
    def rub_to_byn_storage(v) = v.to_f / @rate_byn_rub  # 仓储费直接除汇率，Python 不加 1.03 缓冲
    def cny_to_byn(v) = v.to_f * @rate_cny_rub * 1.03 / @rate_byn_rub  # 3% 缓冲对齐 Python 口径

    # ─── Step 1: 加载财务明细行 ──────────────────────────────────────────────────

    def load_finance_rows
      @rows = RawWb::FinanceDetail
        .where(account_id: @account_id)
        .where('sale_dt BETWEEN ? AND ?', @from_date, @to_date)
        .to_a
    end

    # ─── Step 2: 构建 shkId → nmId 反查表 ────────────────────────────────────────

    def build_shk_nm_mapping
      @shk_to_nm = {}
      @rows.each do |r|
        next unless r.nm_id.to_i.positive? && r.shk_id.to_i.positive?
        @shk_to_nm[r.shk_id] ||= r.nm_id
      end
    end

    # ─── Step 3: 按 (nmId, reportType) 归集费用（原始货币，换算在 compute_profit）─

    def attribute_costs
      @buckets      = Hash.new { |h, k| h[k] = new_bucket }
      @unalloc_rows = []

      @rows.each do |r|
        nm_id = r.nm_id.to_i.positive? ? r.nm_id : @shk_to_nm[r.shk_id]

        if nm_id.blank?
          @unalloc_rows << r
          next
        end

        key    = [nm_id, r.report_type.to_i]
        bucket = @buckets[key]
        op     = r.seller_oper_name.to_s

        case
        when op.include?(RawWb::FinanceDetail::SALE_KEYWORD)
          bucket[:settlement_byn]    += r.for_pay.to_f
          bucket[:acquiring_byn]     += r.acquiring_fee.to_f
          bucket[:sales_qty]         += r.quantity.to_i
          bucket[:tax_base_byn]      += r.retail_price_with_disc.to_f * r.quantity.to_i
          bucket[:retail_amount_byn] += r.retail_amount.to_f * r.quantity.to_i
        when op.include?(RawWb::FinanceDetail::RETURN_KEYWORD)
          bucket[:settlement_byn] -= r.for_pay.to_f
          bucket[:acquiring_byn]  += r.acquiring_fee.to_f
          bucket[:return_qty]     += r.quantity.to_i.abs
        when op.include?(RawWb::FinanceDetail::LOGISTIC_KEYWORD)
          bucket[:delivery_byn]   += r.delivery_rub.to_f   # WB 此字段已是账户货币
        when op.include?(RawWb::FinanceDetail::REIMB_KEYWORD)
          bucket[:reimb_byn]           += r.rebill_logistic_cost.to_f
          bucket[:logistics_reimb_byn] += r.vw.to_f
        when op.include?(RawWb::FinanceDetail::PICKUP_KEYWORD)
          bucket[:pickup_byn]          += r.ppvz_reward.to_f + r.vw.to_f
        when op.include?(RawWb::FinanceDetail::PENALTY_KEYWORD)
          bucket[:penalty_byn]    += r.penalty.to_f
        when op.include?(RawWb::FinanceDetail::STORAGE_KEYWORD)
          # 被 paid_storage API 覆盖，不计入
        when op.include?(RawWb::FinanceDetail::DEDUCT_KEYWORD)
          # 被 ad_settled_fees API 覆盖，不计入
        end
      end
    end

    # ─── Step 4: 仓储费（RUB，全归 Type2 出口）──────────────────────────────────

    def load_storage
      nm_ids = @buckets.keys.map(&:first).uniq
      return if nm_ids.empty?

      RawWb::PaidStorage
        .where(account_id: @account_id)
        .where('calc_date BETWEEN ? AND ?', @from_date, @to_date)
        .group(:nm_id).sum(:warehouse_price_rub)
        .each { |nm_id, rub| @buckets[[nm_id, REPORT_TYPE_EXPORT]][:storage_rub] += rub.to_f }
    end

    # ─── Step 5: 广告费（RUB → BYN，按 fullstats 花费比例分摊）────────────────
    # 分摊逻辑（对齐 Python phase2_order_detail.py）：
    #   1. 从 ad_settled_fees 取各活动的结算总额（RUB）
    #   2. 从 ad_sku_spends 取活动内各 nm_id 的花费占比，按比例分摊结算额
    #      → 无 sku_spends 数据时降级为活动内均分（campaign_products 中的 nm_id 数量）
    #   3. 用隐含汇率（total_ad_rub / total_deduction_byn）将 RUB 转 BYN
    #      → 无 Удержание 记录时降级为 CBR 汇率
    #   4. 按各 nm_id 白俄/出口销量比例拆到两个 bucket

    def load_ad_costs
      fees = RawWb::AdSettledFee
        .where(account_id: @account_id)
        .where('period_from = ? AND period_to = ?', @from_date, @to_date)
        .to_a
      return if fees.empty?

      total_ad_rub = fees.sum { |f| f.upd_sum_rub.to_f }

      # 隐含汇率：total_ad_rub / total_deduction_byn
      # 对齐 Python Phase1：只统计 bonusTypeName 含 "Продвижение" 的 Удержание 行
      # 非广告类 Удержание（如 "Джем" 等促销服务）不参与隐含汇率计算
      implied_rate = nil
      if total_ad_rub > 0
        total_deduction_byn = @rows
          .select { |r|
            r.seller_oper_name.to_s.include?(RawWb::FinanceDetail::DEDUCT_KEYWORD) &&
            r.bonus_type_name.to_s.include?(RawWb::FinanceDetail::DEDUCT_AD_KEYWORD)
          }
          .sum { |r| r.deduction.to_f }
        implied_rate = total_ad_rub / total_deduction_byn if total_deduction_byn > 0
      end

      # 各活动内 nm_id 的 fullstats 花费合计（分摊比例的分子分母）
      campaign_ids = fees.map { |f|
        RawWb::AdCampaign.find_by(wb_advert_id: f.advert_id)&.id
      }.compact

      sku_spend_by_campaign = RawWb::AdSkuSpend
        .where(campaign_id: campaign_ids)
        .where('stat_date BETWEEN ? AND ?', @from_date, @to_date)
        .group(:campaign_id, :nm_id)
        .sum(:spend)
      # { [campaign_id, nm_id] => spend_rub }

      # 各活动 fullstats 总花费（用于计算比例分母）
      campaign_total_spend = sku_spend_by_campaign
        .each_with_object(Hash.new(0.0)) { |((cid, _), spend), h| h[cid] += spend }

      # 活动内 nm_id 列表（fullstats 无数据时用于均分兜底）
      fallback_nms_by_campaign = RawWb::AdCampaignProduct
        .where(campaign_id: campaign_ids)
        .group(:campaign_id)
        .pluck(:campaign_id, Arel.sql('array_agg(nm_id)'))
        .to_h

      fees.each do |fee|
        campaign = RawWb::AdCampaign.find_by(wb_advert_id: fee.advert_id)
        next unless campaign
        campaign_rub = fee.upd_sum_rub.to_f
        next if campaign_rub.zero?

        cid          = campaign.id
        total_spend  = campaign_total_spend[cid]
        nm_spends    = sku_spend_by_campaign.select { |(c, _), _| c == cid }

        if total_spend > 0
          # fullstats 数据存在：按实际花费比例分摊
          nm_spends.each do |(_, nm_id), nm_spend|
            distribute_ad(nm_id, campaign_rub * nm_spend / total_spend, implied_rate)
          end
        else
          # 降级：在 campaign_products 中的 nm_id 之间均分
          nm_ids = fallback_nms_by_campaign[cid] || []
          next if nm_ids.empty?
          per_nm = campaign_rub / nm_ids.size
          nm_ids.each { |nm_id| distribute_ad(nm_id, per_nm, implied_rate) }
        end
      end
    end

    # nm_id 的广告费（RUB）→ BYN，按白俄/出口销量比例写入两个 bucket
    def distribute_ad(nm_id, nm_rub, implied_rate)
      ad_byn = implied_rate ? nm_rub / implied_rate : nm_rub / @rate_byn_rub

      qty_blr = @buckets[[nm_id, REPORT_TYPE_BLR]][:sales_qty]
      qty_exp = @buckets[[nm_id, REPORT_TYPE_EXPORT]][:sales_qty]
      total   = qty_blr + qty_exp

      if total.zero?
        @buckets[[nm_id, REPORT_TYPE_BLR]][:ad_byn] += ad_byn
      else
        @buckets[[nm_id, REPORT_TYPE_BLR]][:ad_byn]   += ad_byn * qty_blr / total
        @buckets[[nm_id, REPORT_TYPE_EXPORT]][:ad_byn] += ad_byn * qty_exp / total
      end
    end

    # ─── Step 6: 货物成本（CNY）────────────────────────────────────────────────

    def load_goods_costs
      nm_ids   = @buckets.keys.map(&:first).uniq
      sku_map  = build_nm_to_sku_map(nm_ids)

      # 构建 sku_code.downcase → sku_code 索引，供大小写不敏感匹配
      sku_code_index = Ec::SkuCost.pluck(:sku_code).each_with_object({}) { |c, h| h[c.downcase] = c }
      costs          = Ec::SkuCost.all.index_by(&:sku_code)

      @goods_costs = {}
      sku_map.each do |nm_id, vendor_code|
        resolved = resolve_sku_code(vendor_code, sku_code_index)
        next unless resolved
        cost = costs[resolved]
        next unless cost
        @goods_costs[nm_id] = {
          total_cost_cny: cost.goods_cost_cny.to_f,
          import_vat_cny: cost.import_vat_cny.to_f,
          sku_code:       resolved,
        }
      end
    end

    # ─── Step 7: 利润计算，所有金额统一输出 BYN ────────────────────────────────

    def compute_profit
      nm_vendor = build_nm_to_sku_map(@buckets.keys.map(&:first).uniq)

      @results = @buckets.map do |(nm_id, report_type), b|
        cost_data = @goods_costs[nm_id]

        # BYN 字段直接取用（财务明细原始结算货币）
        settlement    = b[:settlement_byn]
        acquiring     = b[:acquiring_byn]
        delivery      = b[:delivery_byn]
        reimb         = b[:reimb_byn]
        logistics_reimb = b[:logistics_reimb_byn]
        pickup        = b[:pickup_byn]
        penalty       = b[:penalty_byn]
        tax_base      = b[:tax_base_byn]
        retail_amount = b[:retail_amount_byn]

        # RUB → BYN（仓储费，3% 缓冲对齐 Python）；广告费已在 load_ad_costs 折算为 BYN
        storage = rub_to_byn_storage(b[:storage_rub])
        ad      = b[:ad_byn]

        # 账面小计（BYN）— 对齐 Python Phase1：
        # acquiring/penalty/reimb/pickup 是 WB 内部调整，不影响 Итого，仅展示用
        net = settlement - delivery - storage - ad

        # 货物成本（CNY → BYN）— 基于净成交数，退货的货已退回不计成本
        net_qty        = [b[:sales_qty] - b[:return_qty], 0].max
        goods_cost     = cny_to_byn(net_qty * (cost_data&.dig(:total_cost_cny) || 0.0))
        import_vat_cny = cost_data&.dig(:import_vat_cny) || 0.0  # 展示列保持 CNY（与 Python 对齐）
        import_vat_byn = cny_to_byn(import_vat_cny)              # 税务计算用 BYN

        pre_tax   = net - goods_cost
        tax       = calc_tax_byn(tax_base, net_qty, import_vat_byn)
        after_tax = pre_tax - tax

        {
          nm_id:         nm_id,
          vendor_code:   nm_vendor[nm_id],
          report_type:   report_type,
          region:        report_type == REPORT_TYPE_BLR ? '白俄' : '出口',
          sales_qty:     b[:sales_qty],
          return_qty:    b[:return_qty],
          net_qty:       net_qty,
          retail_amount: retail_amount.round(2),
          import_vat:    import_vat_cny.round(4),
          settlement:    settlement.round(2),
          acquiring:     acquiring.round(2),
          delivery:      delivery.round(2),
          reimb:           reimb.round(2),
          logistics_reimb: logistics_reimb.round(2),
          pickup:          pickup.round(2),
          penalty:       penalty.round(2),
          storage:       storage.round(2),
          ad:            ad.round(2),
          net:           net.round(2),
          tax_base:      tax_base.round(2),
          goods_cost:    goods_cost.round(2),
          pre_tax:       pre_tax.round(2),
          tax:           tax.round(2),
          after_tax:     after_tax.round(2),
        }
      end.sort_by { |r| [r[:nm_id], r[:report_type]] }

      @unallocated = build_unallocated_summary
      @summary     = build_summary
    end

    # tax_base/import_vat 均已为 BYN，直接计算；用 net_qty 对齐 WOD/Python
    def calc_tax_byn(tax_base, net_qty, import_vat_per_unit)
      case @tax_regime
      when 'osn'
        vat_output = tax_base * 20.0 / 120
        vat_input  = net_qty * import_vat_per_unit
        vat_output - vat_input  # 允许负数（进项 > 销项时退税）
      when 'usn'
        tax_base * 0.06
      else
        0.0
      end
    end

    def build_unallocated_summary
      # 广告类 Удержание（bonusTypeName 含 "Продвижение"）已由 ad_settled_fees 路径处理，排除
      # 非广告类 Удержание（如 "Джем" 等服务扣款）保留，与 Python Phase1 口径一致
      @unalloc_rows
        .reject { |r|
          r.seller_oper_name.to_s.include?(RawWb::FinanceDetail::DEDUCT_KEYWORD) &&
          r.bonus_type_name.to_s.include?(RawWb::FinanceDetail::DEDUCT_AD_KEYWORD)
        }
        .group_by { |r|
          label = r.bonus_type_name.to_s.strip
          label.present? ? label : r.seller_oper_name.to_s
        }
        .transform_values do |rows|
          rows.sum { |r| r.paid_storage.to_f + r.deduction.to_f + r.penalty.to_f }
        end
    end

    def build_summary
      {
        tax_regime:       @tax_regime,
        total_sales_qty:  @results.sum { |r| r[:sales_qty] },
        total_return_qty: @results.sum { |r| r[:return_qty] },
        total_net:        @results.sum { |r| r[:net] }.round(2),
        total_goods_cost: @results.sum { |r| r[:goods_cost] }.round(2),
        total_pre_tax:    @results.sum { |r| r[:pre_tax] }.round(2),
        total_tax:        @results.sum { |r| r[:tax] }.round(2),
        total_after_tax:  @results.sum { |r| r[:after_tax] }.round(2),
        unallocated_rows: @unalloc_rows.size,
      }
    end

    def new_bucket
      {
        settlement_byn: 0.0, acquiring_byn: 0.0, delivery_byn: 0.0,
        reimb_byn: 0.0, logistics_reimb_byn: 0.0, pickup_byn: 0.0, penalty_byn: 0.0,
        storage_rub: 0.0, ad_byn: 0.0,
        sales_qty: 0, return_qty: 0, tax_base_byn: 0.0,
        retail_amount_byn: 0.0,
      }
    end

    # WB vendorCode → internal sku_code 别名表
    # 当 WB 侧代码与内部 sku_code 不同时在此登记
    VENDOR_CODE_ALIASES = {
      'par1'  => 'HD-QJ206',
      'par18' => 'HD-QJ310',
    }.freeze

    def build_nm_to_sku_map(nm_ids)
      sku_map = {}
      RawWb::Product.where(nm_id: nm_ids).pluck(:nm_id, :vendor_code).each do |nm_id, vc|
        sku_map[nm_id] = vc if vc.present?
      end
      sku_map
    end

    # 将 WB vendorCode 解析为 ec_sku_costs 中的 sku_code
    # 优先走别名表，其次大小写不敏感匹配
    def resolve_sku_code(vendor_code, sku_code_index)
      return nil if vendor_code.blank?
      alias_code = VENDOR_CODE_ALIASES[vendor_code.downcase]
      return alias_code if alias_code
      sku_code_index[vendor_code.downcase]
    end
  end
end
