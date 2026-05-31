module Ec
  # Per-SKU profit attribution from Ozon accrual_by_day financial data.
  #
  # Usage:
  #   result = Ec::OzonProfitAttribution.new(
  #     account_id: 1,
  #     from_date:  Date.parse('2026-05-04'),
  #     to_date:    Date.parse('2026-05-10'),
  #     rate_cny_rub: 10.9306   # CBR 原始汇率（服务内部 ×1.03 换算货物成本）
  #   ).call
  class OzonProfitAttribution
    # ── fee classification by type_id ──────────────────────────────────────────
    DELIVERY_TYPE_IDS  = [16, 28, 29, 30, 31, 32, 98].to_set.freeze
    RETURN_TYPE_IDS    = [9, 45, 59, 60, 61].to_set.freeze
    STORAGE_TYPE_IDS   = [12, 15, 46, 78].to_set.freeze  # TemporaryPlacement etc.
    DISPATCH_TYPE_IDS  = [33, 71].to_set.freeze           # SellerReturns
    PACKING_TYPE_IDS   = [34].to_set.freeze           # PackingFee
    DEFECT_TYPE_IDS    = [14].to_set.freeze

    UNALLOCATED_TYPE_IDS = [93, 94, 96].to_set.freeze  # penalties, no SKU
    AD_TYPE_IDS          = [41, 54].to_set.freeze       # PPC / Promotion (NON_ITEM)
    CROSSDOCK_TYPE_ID    = 12

    # Fallback by type_name prefix for newer/unlisted type_ids
    DELIVERY_NAMES  = %w[Logistic LastMile Drop-Off Shipment Delivery].freeze
    RETURN_NAMES    = %w[ClientReturn ReturnFlow PickUpPointReturn PartialReturn Cancellation].freeze
    STORAGE_NAMES   = %w[TemporaryPlacement ReturnStorage].freeze
    DISPATCH_NAMES  = %w[SellerReturn].freeze
    PACKING_NAMES   = %w[PackingFee].freeze

    attr_reader :results, :unallocated, :summary

    def initialize(account_id:, from_date:, to_date:, rate_cny_rub: nil, sync_missing_ad_costs: true)
      @account_id    = account_id
      @from_date     = from_date.is_a?(Date) ? from_date : Date.parse(from_date.to_s)
      @to_date       = to_date.is_a?(Date) ? to_date : Date.parse(to_date.to_s)
      @rate_cny_rub  = (rate_cny_rub || default_rate).to_f
      @sync_missing_ad_costs = sync_missing_ad_costs
      # Apply 3% buffer to align with Python口径：rate_effective = rate_cny_rub × 1.03
      @rate_effective = @rate_cny_rub * 1.03
    end

    def call
      load_rows
      load_sku_mappings
      load_ad_costs
      load_destinations
      load_cost_data

      attribute_fees
      compute_counts
      merge_ad_costs
      split_by_destination
      apply_profit_chain

      build_output
      self
    end

    private

    # ── data loading ────────────────────────────────────────────────────────────

    def load_rows
      @rows = RawOzon::AccrualByDay
        .where(account_id: @account_id, accrual_date: @from_date..@to_date)
        .to_a
    end

    def load_sku_mappings
      # offer_id → sku_code（大写匹配，ec_skus 中 sku_code 均为大写）
      # 先建 code_by_upper，供 ozon_sku 映射时优先选能命中的 offer_id
      code_by_upper = Ec::Sku.pluck(:sku_code)
                              .each_with_object({}) { |c, h| h[c.upcase] = c }

      # ozon_sku → offer_id：同一 ozon_sku 可能对应多个 offer_id（数据录入错误/历史变更）
      # 优先选能在 ec_skus 里命中的 offer_id；均不命中时取最后一条
      ozon_to_offers = Hash.new { |h, k| h[k] = [] }
      RawOzon::PostingItem
        .where(account_id: @account_id)
        .where.not(ozon_sku: nil).where.not(offer_id: nil)
        .distinct.pluck(:ozon_sku, :offer_id)
        .each { |sku, oid| ozon_to_offers[sku] << oid }
      ozon_to_offer = ozon_to_offers.transform_values do |oids|
        oids.find { |oid| code_by_upper.key?(oid.to_s.upcase) } || oids.last
      end

      # sku_code → {cost_cny, import_vat_cny} (ec_sku_costs)
      cost_map = Ec::SkuCost.all.each_with_object({}) do |c, h|
        h[c.sku_code] = {
          cost_cny:       c.goods_cost_cny.to_f,
          import_vat_cny: c.import_vat_cny.to_f,
        }
      end

      @sku_to_code = {}
      ozon_to_offer.each do |ozon_sku, offer_id|
        code = code_by_upper[offer_id.to_s.upcase]
        @sku_to_code[ozon_sku] = code if code
      end

      @cost_by_sku = {}
      @sku_to_code.each do |ozon_sku, code|
        @cost_by_sku[ozon_sku] = cost_map[code] if cost_map[code]
      end
    end

    def load_ad_costs
      pairs = resolve_ad_cost_periods(@from_date, @to_date)

      if pairs.nil? && @sync_missing_ad_costs
        # 缓存未命中：当场 sync 并存库，下次直接命中策略1
        account = RawOzon::SellerAccount.find(@account_id)
        RawOzon::PerformanceSync.new(account, from_date: @from_date, to_date: @to_date)
          .run(sync_keys: %i[sync_performance_ppc_sku_spends sync_performance_promotion_sku_spends])
        pairs = [[@from_date, @to_date]]
      end

      spends = (pairs || []).reduce(RawOzon::PerformanceSkuSpend.none) do |scope, (wf, wt)|
        scope.or(RawOzon::PerformanceSkuSpend.where(account_id: @account_id, period_from: wf, period_to: wt))
      end

      @ppc_by_sku       = spends.where(ad_type: 'ppc').pluck(:ozon_sku_id, :spend)
                                .each_with_object(Hash.new(0.0)) { |(s, v), h| h[s] += v.to_f }
      @promotion_by_sku = spends.where(ad_type: 'promotion').pluck(:ozon_sku_id, :spend)
                                .each_with_object(Hash.new(0.0)) { |(s, v), h| h[s] += v.to_f }

      # 用 accrual_by_day type_id=41/54 总额归一化，确保报表与财务结算严格对齐
      rescale_ad_costs_to_accrual
    end

    def rescale_ad_costs_to_accrual
      accrual_ppc   = @rows.select { |r| r.type_id.to_i == 41 }.sum { |r| r.amount.to_f.abs }
      accrual_promo = @rows.select { |r| r.type_id.to_i == 54 }.sum { |r| r.amount.to_f.abs }

      perf_ppc   = @ppc_by_sku.values.sum
      perf_promo = @promotion_by_sku.values.sum

      if perf_ppc > 0 && accrual_ppc > 0
        ratio = accrual_ppc / perf_ppc
        @ppc_by_sku.transform_values! { |v| (v * ratio).round(2) }
        # 修正取整累积误差，加到最大 SKU 上
        diff = accrual_ppc.round(2) - @ppc_by_sku.values.sum.round(2)
        if diff.abs > 0 && (top = @ppc_by_sku.max_by { |_, v| v })
          @ppc_by_sku[top[0]] = (@ppc_by_sku[top[0]] + diff).round(2)
        end
      end

      if perf_promo > 0 && accrual_promo > 0
        ratio = accrual_promo / perf_promo
        @promotion_by_sku.transform_values! { |v| (v * ratio).round(2) }
        diff = accrual_promo.round(2) - @promotion_by_sku.values.sum.round(2)
        if diff.abs > 0 && (top = @promotion_by_sku.max_by { |_, v| v })
          @promotion_by_sku[top[0]] = (@promotion_by_sku[top[0]] + diff).round(2)
        end
      end

      # Performance 返回 0 但 accrual 有扣费时，记录孤儿金额 → 写入 unallocated
      # 无法按 SKU 拆分（Performance 未返回明细），整体进未分摊
      @orphaned_ppc_total   = (perf_ppc   == 0 && accrual_ppc   > 0) ? accrual_ppc   : 0.0
      @orphaned_promo_total = (perf_promo == 0 && accrual_promo > 0) ? accrual_promo : 0.0
    end

    # 返回可以直接查库的 [[period_from, period_to], ...] 组合，nil 表示需要去拉接口
    def resolve_ad_cost_periods(from_date, to_date)
      # 策略1：精确命中
      if RawOzon::PerformanceSkuSpend
           .where(account_id: @account_id, period_from: from_date, period_to: to_date)
           .exists?
        return [[from_date, to_date]]
      end

      # 策略2：自然周整数倍（头=周一，尾=周日）
      days = (to_date - from_date).to_i + 1
      if days >= 14 && (days % 7).zero? && from_date.cwday == 1 && to_date.cwday == 7
        week_pairs = (days / 7).times.map { |i| [from_date + i * 7, from_date + i * 7 + 6] }
        all_present = week_pairs.all? do |wf, wt|
          RawOzon::PerformanceSkuSpend
            .where(account_id: @account_id, period_from: wf, period_to: wt)
            .exists?
        end
        return week_pairs if all_present
      end

      nil
    end

    def load_destinations
      # All posting_destinations for this account
      @destinations = RawOzon::PostingDestination
        .where(account_id: @account_id)
        .pluck(:posting_number, :is_belarus)
        .each_with_object({}) { |(pn, by), h| h[pn] = by }
    end

    def load_cost_data; end  # already done in load_sku_mappings

    def default_rate
      Ec::SkuPlatformCost
        .where(platform: 'ozon')
        .pick(:exchange_rate_rub_cny)
        &.then { |r| 1.0 / r.to_f } || 11.0
    end

    # ── fee attribution ─────────────────────────────────────────────────────────

    def attribute_fees
      @fees         = Hash.new { |h, k| h[k] = zero_fees }
      @unalloc_rows = []

      # ALL SaleRevenue postings (positive AND negative) in the period → Acquiring attribution scope
      current_pkeys = Hash.new { |h, k| h[k] = Set.new }
      @rows.select { |r| r.type_id.to_i == 0 && r.ozon_sku_id }.each do |r|
        pk = posting_key(r.posting_number)
        current_pkeys[r.ozon_sku_id] << pk if pk
      end

      @rows.each do |row|
        tid    = row.type_id.to_i
        amount = row.amount.to_f
        sku    = row.ozon_sku_id
        name   = row.type_name.to_s

        next if AD_TYPE_IDS.include?(tid)

        if tid == CROSSDOCK_TYPE_ID
          if sku && sku != 0
            @fees[sku][:crossdock_fee] += amount
          else
            @unalloc_rows << row
          end
          next
        end

        if sku.nil? || sku == 0
          @unalloc_rows << row
          next
        end

        f = @fees[sku]

        case tid
        when 0   then f[:sales_revenue] += amount
        when 69  then f[:commission]     += amount
        when 1
          # Only attribute Acquiring for current-period postings; old-period ones go unallocated
          pk = posting_key(row.posting_number)
          if pk && current_pkeys[sku].include?(pk)
            f[:payment_fee] += amount
          else
            @unalloc_rows << row
          end
        when *DELIVERY_TYPE_IDS  then f[:delivery_charge] += amount
        when *RETURN_TYPE_IDS    then f[:return_delivery]  += amount
        when *STORAGE_TYPE_IDS   then f[:storage_fee]      += amount
        when *DISPATCH_TYPE_IDS  then f[:dispatch_fee]     += amount
        when *PACKING_TYPE_IDS   then f[:packing_fee]      += amount
        when *DEFECT_TYPE_IDS    then f[:defect_fee]       += amount
        else
          if DELIVERY_NAMES.any? { |n| name.start_with?(n) }
            f[:delivery_charge] += amount
          elsif RETURN_NAMES.any? { |n| name.start_with?(n) }
            f[:return_delivery] += amount
          elsif STORAGE_NAMES.any? { |n| name.start_with?(n) }
            f[:storage_fee] += amount
          elsif DISPATCH_NAMES.any? { |n| name.start_with?(n) }
            f[:dispatch_fee] += amount
          elsif PACKING_NAMES.any? { |n| name.start_with?(n) }
            f[:packing_fee] += amount
          else
            f[:other_fee] += amount
          end
        end
      end
    end

    # ── counting logic ───────────────────────────────────────────────────────────
    # Key rule: count by posting_number net SaleRevenue, NOT by row count.
    # net > 0  → order + sale; net < 0 → return; net == 0 → order + return (no sale)
    def compute_counts
      # posting_number net per SKU
      posting_net = Hash.new { |h, k| h[k] = Hash.new(0.0) }

      @rows.select { |r| r.type_id.to_i == 0 && r.ozon_sku_id }.each do |r|
        posting_net[r.ozon_sku_id][r.posting_number] += r.amount.to_f
      end

      @counts = {}
      posting_net.each do |sku, nets|
        order_pns = Set.new
        return_pns = Set.new
        sales_pns  = Set.new

        nets.each do |pn, net|
          if net > 0
            order_pns  << pn
            sales_pns  << pn
          elsif net < 0
            return_pns << pn
          else
            order_pns  << pn
            return_pns << pn
          end
        end

        @counts[sku] = {
          order_count:     order_pns.size,
          return_count:    return_pns.size,
          net_sales_count: [order_pns.size - return_pns.size, 0].max,
          sales_postings:  sales_pns,
        }
      end
    end

    # ── merge ad costs ────────────────────────────────────────────────────────────

    def merge_ad_costs
      all_skus = (@fees.keys + @ppc_by_sku.keys + @promotion_by_sku.keys).uniq
      all_skus.each do |sku|
        @fees[sku]  # ensure key exists
      end
    end

    # ── destination split (Belarus vs export) ────────────────────────────────────
    # Uses posting-level net amounts (mirrors Python phase1_report_v5.py logic).
    # Counts can be negative when returns exceed sales in a region within the period.
    # blr_sale = sum of net revenues for Belarus postings with net > 0 (VAT output base).

    def split_by_destination
      @dest_split = Hash.new { |h, k| h[k] = { blr_sale: 0.0, blr_count: 0, export_count: 0 } }

      # Accumulate posting-level net SaleRevenue per (sku, posting_number)
      posting_nets = Hash.new { |h, k| h[k] = Hash.new(0.0) }
      @rows.select { |r| r.type_id.to_i == 0 && r.ozon_sku_id && r.posting_number }.each do |r|
        posting_nets[r.ozon_sku_id][r.posting_number] += r.amount.to_f
      end

      # Count destinations by posting net: +1 sale, -1 return, skip zero
      posting_nets.each do |sku, pn_nets|
        pn_nets.each do |pn, net|
          next if net == 0
          is_by = @destinations[pn]
          ds = @dest_split[sku]
          if net > 0
            if is_by
              ds[:blr_count] += 1
              ds[:blr_sale]  += net
            else
              ds[:export_count] += 1
            end
          else
            is_by ? ds[:blr_count] -= 1 : ds[:export_count] -= 1
          end
        end
      end
    end

    # ── profit chain ──────────────────────────────────────────────────────────────

    def apply_profit_chain
      @profit = {}

      all_skus = (@fees.keys + @ppc_by_sku.keys + @promotion_by_sku.keys).uniq

      all_skus.each do |sku|
        f    = @fees[sku]
        cnt  = @counts[sku] || { order_count: 0, return_count: 0, net_sales_count: 0 }
        ds   = @dest_split[sku]
        cost = @cost_by_sku[sku]

        ppc_cost       = @ppc_by_sku[sku].to_f
        promotion_cost = @promotion_by_sku[sku].to_f
        total_ad_cost  = ppc_cost + promotion_cost

        book_profit = f[:sales_revenue] + f[:commission] + f[:delivery_charge] +
                      f[:payment_fee] + f[:dispatch_fee] + f[:packing_fee] +
                      f[:return_delivery] + f[:storage_fee] + f[:defect_fee] +
                      f[:crossdock_fee] + f[:other_fee]

        book_profit_after_ad = book_profit - total_ad_cost

        if cost
          goods_cost = -(cnt[:net_sales_count] * cost[:cost_cny] * @rate_effective)
        else
          goods_cost = nil
        end

        pre_tax = goods_cost ? book_profit_after_ad + goods_cost : nil

        # Belarus VAT and export VAT refund.
        # blr_count / export_count can be negative (returns > sales in that region).
        # export_refund can therefore be negative (prior refunds must be clawed back).
        if cost && ds
          import_vat_rub = cost[:import_vat_cny] * @rate_effective
          blr_tax_mag    = [ds[:blr_sale] * 20.0 / 120.0 - [ds[:blr_count], 0].max * import_vat_rub, 0.0].max
          blr_tax        = blr_tax_mag > 0 ? -blr_tax_mag : 0.0
          export_refund  = ds[:export_count] * import_vat_rub
        else
          blr_tax       = nil
          export_refund = nil
        end

        after_tax = if pre_tax && blr_tax && export_refund
          pre_tax + blr_tax + export_refund
        end

        @profit[sku] = {
          ozon_sku_id:    sku,
          sku_code:       @sku_to_code[sku],
          # platform fees
          sales_revenue:  f[:sales_revenue].round(2),
          commission:     f[:commission].round(2),
          delivery_charge: f[:delivery_charge].round(2),
          payment_fee:    f[:payment_fee].round(2),
          dispatch_fee:   f[:dispatch_fee].round(2),
          packing_fee:    f[:packing_fee].round(2),
          return_delivery: f[:return_delivery].round(2),
          storage_fee:    f[:storage_fee].round(2),
          defect_fee:     f[:defect_fee].round(2),
          crossdock_fee:  f[:crossdock_fee].round(2),
          other_fee:      f[:other_fee].round(2),
          # counts
          order_count:    cnt[:order_count],
          return_count:   cnt[:return_count],
          net_sales_count: cnt[:net_sales_count],
          # ad costs (stored positive in DB, displayed as negative costs in output)
          ppc_cost:        -ppc_cost.round(2),
          promotion_cost:  -promotion_cost.round(2),
          total_ad_cost:   -total_ad_cost.round(2),
          # destination (counts can be negative when returns exceed sales)
          blr_sale:       ds&.dig(:blr_sale)&.round(2) || 0.0,
          blr_count:      ds&.dig(:blr_count) || 0,
          export_count:   ds&.dig(:export_count) || 0,
          # cost & tax
          cost_cny:        cost&.dig(:cost_cny),
          import_vat_cny:  cost&.dig(:import_vat_cny),
          goods_cost:      goods_cost&.round(2),
          blr_tax:         blr_tax&.round(2),
          export_refund:   export_refund&.round(2),
          # profit chain
          book_profit:           book_profit.round(2),
          book_profit_after_ad:  book_profit_after_ad.round(2),
          pre_tax_profit:        pre_tax&.round(2),
          after_tax_profit:      after_tax&.round(2),
          after_tax_margin_pct:  (after_tax && f[:sales_revenue] != 0 ? after_tax / f[:sales_revenue] * 100 : nil)&.round(2),
        }
      end
    end

    def build_output
      @results = @profit.values.sort_by { |r| -(r[:after_tax_profit] || r[:book_profit_after_ad] || 0) }

      other_unalloc = @unalloc_rows
        .reject { |r| AD_TYPE_IDS.include?(r.type_id.to_i) }
        .sum    { |r| r.amount.to_f }

      # 孤儿广告费（Performance=0 但 accrual 有 41/54）：无法归 SKU，整体进未分摊
      orphaned_rows = []
      if @orphaned_ppc_total.to_f > 0
        orphaned_rows << { type_id: 41, type_name: 'PPC (нет данных Performance)', amount: -@orphaned_ppc_total.round(2), posting_number: nil, orphaned: true }
      end
      if @orphaned_promo_total.to_f > 0
        orphaned_rows << { type_id: 54, type_name: 'Продвижение (нет данных Performance)', amount: -@orphaned_promo_total.round(2), posting_number: nil, orphaned: true }
      end
      orphaned_total = -((@orphaned_ppc_total.to_f + @orphaned_promo_total.to_f))

      @unallocated = {
        other: other_unalloc.round(2),
        total: (other_unalloc + orphaned_total).round(2),
        rows:  @unalloc_rows
                 .reject { |r| AD_TYPE_IDS.include?(r.type_id.to_i) }
                 .map    { |r| { type_id: r.type_id, type_name: r.type_name, amount: r.amount.to_f, posting_number: r.posting_number } } +
               orphaned_rows,
      }

      @summary = build_summary
    end

    def build_summary
      all = @results
      {
        period:          "#{@from_date} ~ #{@to_date}",
        rate_cny_rub:    @rate_cny_rub,
        rate_effective:  @rate_effective.round(4),
        sku_count:       all.size,
        # revenue
        total_sales_revenue:   all.sum { |r| r[:sales_revenue] }.round(2),
        # platform fees
        total_commission:      all.sum { |r| r[:commission] }.round(2),
        total_delivery:        all.sum { |r| r[:delivery_charge] }.round(2),
        total_payment_fee:     all.sum { |r| r[:payment_fee] }.round(2),
        total_return_delivery: all.sum { |r| r[:return_delivery] }.round(2),
        total_storage:         all.sum { |r| r[:storage_fee] }.round(2),
        total_other_platform:  all.sum { |r| r[:dispatch_fee] + r[:packing_fee] + r[:defect_fee] + r[:crossdock_fee] + r[:other_fee] }.round(2),
        # ad
        total_ppc:       all.sum { |r| r[:ppc_cost] }.round(2),
        total_promotion: all.sum { |r| r[:promotion_cost] }.round(2),
        total_ad:        all.sum { |r| r[:total_ad_cost] }.round(2),
        # counts
        total_orders:    all.sum { |r| r[:order_count] },
        total_returns:   all.sum { |r| r[:return_count] },
        total_net_sales: all.sum { |r| r[:net_sales_count] },
        # destinations
        total_blr:       all.sum { |r| r[:blr_count] },
        total_export:    all.sum { |r| r[:export_count] },
        # cost & tax
        total_goods_cost:    all.sum { |r| r[:goods_cost] || 0 }.round(2),
        total_blr_tax:       all.sum { |r| r[:blr_tax] || 0 }.round(2),
        total_export_refund: all.sum { |r| r[:export_refund] || 0 }.round(2),
        # profit
        total_book_profit:         all.sum { |r| r[:book_profit] }.round(2),
        total_book_profit_after_ad: all.sum { |r| r[:book_profit_after_ad] }.round(2),
        total_pre_tax_profit:      all.sum { |r| r[:pre_tax_profit] || 0 }.round(2),
        total_after_tax_profit:    all.sum { |r| r[:after_tax_profit] || 0 }.round(2),
        # unallocated
        unallocated_total: @unallocated[:total],
      }
    end

    def posting_key(posting_number)
      return nil unless posting_number
      parts = posting_number.to_s.split('-')
      parts.length >= 2 ? "#{parts[0]}-#{parts[1]}" : posting_number
    end

    def zero_fees
      {
        sales_revenue: 0.0, commission: 0.0, delivery_charge: 0.0,
        payment_fee: 0.0, dispatch_fee: 0.0, packing_fee: 0.0,
        return_delivery: 0.0, storage_fee: 0.0, defect_fee: 0.0,
        crossdock_fee: 0.0, other_fee: 0.0,
      }
    end
  end
end
