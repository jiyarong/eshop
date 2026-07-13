module Ec
  # Per-shkId profit breakdown for WB order detail report.
  #
  # Reuses WbProfitAttribution for SKU-level aggregates (storage, ad, goods_cost,
  # tax per nm_id × report_type), then distributes per-unit to each shkId row.
  #
  # All monetary output is in BYN (WB finance currency for Belarus accounts).
  #
  # Usage:
  #   svc = Ec::WbOrderDetailReport.new(
  #     account_id:   3,
  #     from_date:    '2026-05-04',
  #     to_date:      '2026-05-10',
  #     rate_cny_rub: 10.9306,
  #     rate_byn_rub: 26.4654
  #   ).call
  #   svc.order_rows  # Array<Hash> — one per shkId sale/return row
  #   svc.summary     # totals + cross-check vs SKU report
  class WbOrderDetailReport
    attr_reader :order_rows, :summary, :orphan_costs

    SALE_OP        = RawWb::FinanceDetail::SALE_KEYWORD
    RETURN_OP      = RawWb::FinanceDetail::RETURN_KEYWORD
    LOGISTIC_OP    = RawWb::FinanceDetail::LOGISTIC_KEYWORD
    CORR_LOGISTIC_OP = RawWb::FinanceDetail::CORR_LOGISTIC_KEYWORD
    REIMB_OP       = RawWb::FinanceDetail::REIMB_KEYWORD
    PICKUP_OP      = RawWb::FinanceDetail::PICKUP_KEYWORD
    PENALTY_OP     = RawWb::FinanceDetail::PENALTY_KEYWORD

    def initialize(account_id:, from_date:, to_date:, rate_cny_rub:, rate_byn_rub:)
      @account_id   = account_id
      @from_date    = from_date.to_date
      @to_date      = to_date.to_date
      @rate_cny_rub = rate_cny_rub.to_f
      @rate_byn_rub = rate_byn_rub.to_f
    end

    def call
      # SKU-level aggregates: storage, ad, goods_cost, tax already computed correctly
      attr_svc  = Ec::WbProfitAttribution.new(
        account_id:   @account_id,
        from_date:    @from_date,
        to_date:      @to_date,
        rate_cny_rub: @rate_cny_rub,
        rate_byn_rub: @rate_byn_rub
      ).call
      @sku_results = attr_svc.results.index_by { |r| [r[:nm_id], r[:report_type]] }
      @attr_summary = attr_svc.summary

      @rows = RawWb::FinanceDetail
        .where(account_id: @account_id)
        .where('sale_dt BETWEEN ? AND ?', @from_date, @to_date)
        .order(:sale_dt, :shk_id)
        .to_a

      build_shk_groups
      build_per_unit_costs
      build_product_names
      @order_rows   = build_order_rows   # also populates @orphan_rows
      @orphan_costs = build_orphan_costs
      @summary      = build_summary
      self
    end

    private

    # ── Group finance rows by shk_id ────────────────────────────────────────────

    def build_shk_groups
      @shk_to_nm = {}
      @rows.each do |r|
        next unless r.nm_id.to_i.positive? && r.shk_id.to_i.positive?
        @shk_to_nm[r.shk_id] ||= r.nm_id
      end

      @orphan_rows = { logistics: [], reimbs: [], pickups: [], penalties: [] }
      @shk_groups  = Hash.new { |h, k| h[k] = { sales: [], logistics: [], reimbs: [], pickups: [], penalties: [] } }

      @rows.each do |r|
        shk = r.shk_id.to_i
        op  = r.seller_oper_name.to_s

        if shk.zero?
          # shk_id=0：无法按订单分摊，直接归孤儿桶
          if    op.include?(LOGISTIC_OP) || op.include?(CORR_LOGISTIC_OP)
            @orphan_rows[:logistics] << r
          elsif op.include?(REIMB_OP)
            @orphan_rows[:reimbs] << r
          elsif op.include?(PICKUP_OP)
            @orphan_rows[:pickups] << r
          elsif op.include?(PENALTY_OP)
            @orphan_rows[:penalties] << r
          end
          next
        end

        if    op.include?(SALE_OP) || op.include?(RETURN_OP)
          @shk_groups[shk][:sales] << r
        elsif op.include?(LOGISTIC_OP) || op.include?(CORR_LOGISTIC_OP)
          @shk_groups[shk][:logistics] << r
        elsif op.include?(REIMB_OP)
          @shk_groups[shk][:reimbs] << r
        elsif op.include?(PICKUP_OP)
          @shk_groups[shk][:pickups] << r
        elsif op.include?(PENALTY_OP)
          @shk_groups[shk][:penalties] << r
        end
      end
    end

    # ── Per-unit costs from SKU-level results ────────────────────────────────────
    # WbProfitAttribution already resolved vendor_code aliases and computed correct
    # goods_cost (BYN) and import_vat (CNY). Divide by net_qty for per-shkId values.

    def build_per_unit_costs
      @per_unit = {}

      @sku_results.each do |(nm_id, rtype), r|
        sales_qty        = [r[:sales_qty].to_i, 1].max
        net_qty          = r[:net_qty].to_i
        cost_divisor     = net_qty.negative? ? net_qty.abs : sales_qty

        goods_cost_total = r[:goods_cost].to_f.abs
        # import_vat: total = net_qty × unit_cny, then spread using the same signed net logic as WR.
        total_import_vat_byn = r[:import_vat].to_f * net_qty * @rate_cny_rub * 1.03 / @rate_byn_rub

        @per_unit[[nm_id, rtype]] = {
          storage_byn:    r[:storage].to_f.abs / sales_qty,
          ad_byn:         r[:ad].to_f.abs      / sales_qty,
          goods_cost_byn: goods_cost_total      / cost_divisor,
          import_vat_byn: total_import_vat_byn.abs / cost_divisor,
          has_cost:       goods_cost_total > 0,
          negative_net:   net_qty.negative?,
        }
      end
    end

    # ── Product names from ec_skus + raw_wb_products ────────────────────────────

    def build_product_names
      nm_ids = @shk_groups.values.flat_map { |g| g[:sales].map(&:nm_id) }.uniq
      @nm_to_product = {}
      RawWb::Product.where(nm_id: nm_ids).each do |p|
        @nm_to_product[p.nm_id] = { name: p.title, vendor_code: p.vendor_code }
      end
    end

    # ── Build one output row per shkId × Продажа/Возврат ────────────────────────

    def build_order_rows
      rows = []
      tax_regime = @attr_summary[:tax_regime]

      @shk_groups.each do |shk_id, g|
        next if g[:sales].empty?

        delivery_byn      = g[:logistics].sum { |r| r.delivery_rub.to_f }
        logistics_reimb   = g[:reimbs].sum    { |r| r.vw.to_f }
        rebill_byn        = g[:reimbs].sum    { |r| r.rebill_logistic_cost.to_f }
        pickup_byn        = g[:pickups].sum   { |r| r.ppvz_reward.to_f + r.vw.to_f }
        penalty_byn       = g[:penalties].sum { |r| r.penalty.to_f }
        delivery_method   = g[:logistics].filter_map { |r| r.delivery_method.presence }.first

        # Paired group: shk has both sale and return in the same period.
        # Per-shk costs belong to the sale event; zeroing them on return rows prevents double-counting.
        has_sale   = g[:sales].any? { |r| r.seller_oper_name.to_s.include?(SALE_OP) }
        has_return = g[:sales].any? { |r| r.seller_oper_name.to_s.include?(RETURN_OP) }
        paired_group = has_sale && has_return

        g[:sales].each do |r|
          nm_id   = r.nm_id.to_i.positive? ? r.nm_id : @shk_to_nm[shk_id].to_i
          rtype   = r.report_type.to_i
          is_sale = r.seller_oper_name.to_s.include?(SALE_OP)
          for_pay = is_sale ? r.for_pay.to_f : -r.for_pay.to_f.abs

          pu      = @per_unit[[nm_id, rtype]] || {}
          # storage/ad are per-unit warehouse/marketing costs divided by sales_qty;
          # applying to returns would over-deduct (per_unit = total/sales, not total/(sales+returns))
          storage = is_sale ? pu[:storage_byn].to_f : 0.0
          ad      = is_sale ? pu[:ad_byn].to_f : 0.0

          # In paired groups costs are attributed to the sale row only; return row gets zero
          row_delivery        = (!is_sale && paired_group) ? 0.0 : delivery_byn
          row_penalty         = (!is_sale && paired_group) ? 0.0 : penalty_byn
          row_rebill          = (!is_sale && paired_group) ? 0.0 : rebill_byn
          row_logistics_reimb = (!is_sale && paired_group) ? 0.0 : logistics_reimb
          row_pickup          = (!is_sale && paired_group) ? 0.0 : pickup_byn

          net = (for_pay - row_delivery - row_penalty - row_rebill - row_pickup - row_logistics_reimb - storage - ad).round(2)

          prod     = @nm_to_product[nm_id] || {}
          qty      = r.quantity.to_i.nonzero? || 1
          tax_base = (r.retail_price_with_disc.to_f * qty).round(2)

          import_vat = pu[:import_vat_byn].to_f

          if is_sale
            goods_cost = pu[:has_cost] ? -pu[:goods_cost_byn].round(2) : nil
            pre_tax    = goods_cost ? (net + goods_cost).round(2) : net

            vat_net = if tax_regime == 'osn'
              ((tax_base * 20.0 / 120) - import_vat).round(2)
            else
              (tax_base * 0.06).round(2)
            end
            after_tax  = (pre_tax - vat_net).round(2)
            margin_pct = for_pay.abs > 0 ? (after_tax / for_pay * 100).round(1) : nil
          elsif pu[:negative_net]
            goods_cost = pu[:has_cost] ? pu[:goods_cost_byn].round(2) : nil
            pre_tax    = goods_cost ? (net + goods_cost).round(2) : net
            vat_net = if tax_regime == 'osn'
              import_vat.round(2)
            else
              0.0
            end
            after_tax  = (pre_tax - vat_net).round(2)
            margin_pct = nil
          else  # Возврат — no goods cost, no tax unless the SKU bucket is net negative
            goods_cost = nil; pre_tax = nil; vat_net = nil
            after_tax  = net
            margin_pct = nil
          end

          rows << {
            nm_id:          nm_id.positive? ? nm_id : nil,
            vendor_code:    r.sa_name,
            brand:          r.brand_name,
            product_name:   prod[:name],
            shk_id:,
            order_type:     is_sale ? '成交' : '退货',
            region:         rtype == 1 ? '白俄' : '出口',
            report_type:    rtype,
            order_dt:       r.order_dt&.to_s,
            sale_dt:        r.sale_dt&.to_s,
            country:        r.country,
            office_name:    r.office_name,
            ppvz_office:    r.ppvz_office_name,
            delivery_method:,
            retail_price_with_disc: r.retail_price_with_disc.to_f,
            spp_pct:        r.sale_percent.to_f,
            retail_amount:  r.retail_amount.to_f,
            commission_pct: r.commission_percent.to_f,
            for_pay:        for_pay.round(2),
            acquiring:      r.acquiring_fee.to_f.round(2),
            delivery:       row_delivery.round(2),
            penalty:          row_penalty.round(2),
            rebill:           row_rebill.round(2),
            logistics_reimb:  row_logistics_reimb.round(2),
            pickup:           row_pickup.round(2),
            storage:        -storage.round(2),
            ad:             -ad.round(2),
            net:,
            tax_base:,
            goods_cost:,
            pre_tax:,
            vat_net:        vat_net.nil? ? nil : -vat_net,
            after_tax:,
            margin_pct:,
          }
        end
      end

      # shk 有费用行但无销售行 → 归入孤儿桶
      # nm_id 可通过 shk_to_nm 解析，或费用行本身有直接 nm_id，则归孤儿（与 WR 口径一致）
      @shk_groups.each do |shk_id, g|
        next unless g[:sales].empty?
        all_cost_rows = g[:logistics] + g[:reimbs] + g[:pickups] + g[:penalties]
        nm_resolvable = @shk_to_nm[shk_id] || all_cost_rows.any? { |r| r.nm_id.to_i.positive? }
        next unless nm_resolvable
        @orphan_rows[:logistics] += g[:logistics]
        @orphan_rows[:reimbs]    += g[:reimbs]
        @orphan_rows[:pickups]   += g[:pickups]
        @orphan_rows[:penalties] += g[:penalties]
      end

      rows.sort_by { |r| [r[:sale_dt].to_s, r[:shk_id].to_i] }
    end

    # ── 孤儿费用汇总（shk 无法对应销售行的费用）──────────────────────────────
    def build_orphan_costs
      delivery        = @orphan_rows[:logistics].sum { |r| r.delivery_rub.to_f }.round(2)
      logistics_reimb = @orphan_rows[:reimbs].sum    { |r| r.vw.to_f }.round(2)
      rebill          = @orphan_rows[:reimbs].sum    { |r| r.rebill_logistic_cost.to_f }.round(2)
      pickup          = @orphan_rows[:pickups].sum   { |r| r.ppvz_reward.to_f + r.vw.to_f }.round(2)
      penalty         = @orphan_rows[:penalties].sum { |r| r.penalty.to_f }.round(2)
      net             = -(delivery + logistics_reimb + rebill + pickup + penalty).round(2)
      { delivery:, logistics_reimb:, rebill:, penalty:, pickup:, net:, after_tax: net }
    end

    # ── Summary ──────────────────────────────────────────────────────────────────

    def build_summary
      sales_ct  = @order_rows.count { |r| r[:order_type] == '成交' }
      ret_ct    = @order_rows.count { |r| r[:order_type] == '退货' }
      blr_ct    = @order_rows.count { |r| r[:report_type] == 1 && r[:order_type] == '成交' }
      exp_ct    = @order_rows.count { |r| r[:report_type] == 2 && r[:order_type] == '成交' }

      total_forpay  = @order_rows.sum { |r| r[:for_pay].to_f }.round(2)
      total_delivery= @order_rows.count { |r| r[:order_type] == '成交' } > 0 ?
                        @order_rows.select { |r| r[:order_type] == '成交' }.sum { |r| r[:delivery].to_f }.round(2) : 0.0
      total_storage = @order_rows.sum { |r| r[:storage].to_f }.round(2)
      total_ad      = @order_rows.sum { |r| r[:ad].to_f }.round(2)
      total_net     = @order_rows.sum { |r| r[:net].to_f }.round(2)
      total_goods   = @order_rows.sum { |r| r[:goods_cost].to_f }.round(2)
      total_after   = @order_rows.sum { |r| r[:after_tax].to_f }.round(2)

      sku_total_after = @sku_results.values.sum { |r| r[:after_tax].to_f }.round(2)
      orphan_after    = @orphan_costs[:after_tax].to_f
      grand_after     = (total_after + orphan_after).round(2)

      {
        period:              "#{@from_date} ~ #{@to_date}",
        rate_cny_rub:        @rate_cny_rub,
        rate_byn_rub:        @rate_byn_rub,
        tax_regime:          @attr_summary[:tax_regime],
        total_rows:          @order_rows.size,
        sales_count:         sales_ct,
        return_count:        ret_ct,
        blr_count:           blr_ct,
        export_count:        exp_ct,
        total_forpay:,
        total_delivery:,
        total_storage:,
        total_ad:,
        total_net:,
        total_goods:,
        total_after_tax:     total_after,
        orphan_after_tax:    orphan_after.round(2),
        grand_after_tax:     grand_after,
        sku_total_after_tax: sku_total_after,
        residual:            (grand_after - sku_total_after).round(2),
      }
    end
  end
end
