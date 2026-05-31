module Ec
  # Per-posting profit breakdown for Ozon order detail report.
  #
  # Reuses OzonProfitAttribution for SKU-level aggregates (ad costs, crossdock,
  # counts, BLR/export split) and adds posting-level fee granularity on top.
  #
  # Usage:
  #   svc = Ec::OzonOrderDetailReport.new(
  #     account_id:   1,
  #     from_date:    '2026-04-27',
  #     to_date:      '2026-05-03',
  #     rate_cny_rub: 11.26
  #   ).call
  #   svc.order_rows   # Array<Hash> — one per (posting_number, ozon_sku_id)
  #   svc.unallocated  # same structure as OzonProfitAttribution#unallocated
  #   svc.summary      # totals + cross-check vs SKU report
  class OzonOrderDetailReport
    attr_reader :order_rows, :unallocated, :summary

    def initialize(account_id:, from_date:, to_date:, rate_cny_rub:)
      @account_id   = account_id
      @from_date    = from_date.is_a?(Date) ? from_date : Date.parse(from_date.to_s)
      @to_date      = to_date.is_a?(Date)   ? to_date   : Date.parse(to_date.to_s)
      @rate_cny_rub = rate_cny_rub.to_f
      @rate_eff     = @rate_cny_rub * 1.03  # aligns with OzonProfitAttribution
    end

    def call
      # SKU-level aggregates: ad costs (rescaled), crossdock, counts, BLR/export split
      attr_svc     = Ec::OzonProfitAttribution.new(
        account_id: @account_id, from_date: @from_date,
        to_date: @to_date, rate_cny_rub: @rate_cny_rub
      ).call
      @sku_map     = attr_svc.results.index_by { |r| r[:ozon_sku_id] }
      @unallocated = attr_svc.unallocated
      attr_summary = attr_svc.summary

      rows = RawOzon::AccrualByDay
        .where(account_id: @account_id, accrual_date: @from_date..@to_date)
        .to_a

      fee, accrual_meta = build_fee_hash(rows)
      match_acquiring!(fee, rows)

      posting_numbers = fee.keys.map(&:first).uniq
      posting_meta    = load_posting_meta(posting_numbers)
      sku_name_map    = Ec::Sku.pluck(:sku_code, :product_name_ru).to_h

      @order_rows = build_order_rows(fee, accrual_meta, posting_meta, sku_name_map)
      @summary    = build_summary(attr_summary)
      self
    end

    private

    # ── Step 1: build per-(posting_number, ozon_sku_id) fee hash ────────────────

    def build_fee_hash(rows)
      fee  = Hash.new { |h, k| h[k] = zero_fees }
      meta = {}

      ad_ids = Ec::OzonProfitAttribution::AD_TYPE_IDS

      rows.each do |r|
        pn  = r.posting_number.to_s.strip
        sku = r.ozon_sku_id || 0
        tid = r.type_id.to_i
        amt = r.amount.to_f
        d   = r.accrual_date

        if pn.present?
          meta[pn] ||= { date: d }
          meta[pn][:date] = d if d < meta[pn][:date]
        end

        next if ad_ids.include?(tid)    # handled by OzonProfitAttribution
        next if pn.blank?
        next if tid == 1                # Acquiring — matched separately

        key = [pn, sku]
        f   = fee[key]
        tn  = r.type_name.to_s

        case tid
        when 0   then f[:revenue]         += amt
        when 69  then f[:commission]       += amt
        when 12  then next                          # CrossDock — amortized from SKU level
        when *Ec::OzonProfitAttribution::DELIVERY_TYPE_IDS then f[:delivery]        += amt
        when *Ec::OzonProfitAttribution::RETURN_TYPE_IDS   then f[:return_delivery] += amt
        when *Ec::OzonProfitAttribution::STORAGE_TYPE_IDS  then f[:storage]         += amt
        when *Ec::OzonProfitAttribution::DISPATCH_TYPE_IDS then f[:dispatch]        += amt
        when *Ec::OzonProfitAttribution::PACKING_TYPE_IDS  then f[:packing]         += amt
        when *Ec::OzonProfitAttribution::DEFECT_TYPE_IDS   then f[:delivery]        += amt
        else
          dnames = Ec::OzonProfitAttribution::DELIVERY_NAMES
          rnames = Ec::OzonProfitAttribution::RETURN_NAMES
          snames = Ec::OzonProfitAttribution::STORAGE_NAMES
          pnames = Ec::OzonProfitAttribution::PACKING_NAMES
          if    dnames.any? { |n| tn.start_with?(n) } then f[:delivery]        += amt
          elsif rnames.any? { |n| tn.start_with?(n) } then f[:return_delivery] += amt
          elsif snames.any? { |n| tn.start_with?(n) } then f[:storage]         += amt
          elsif pnames.any? { |n| tn.start_with?(n) } then f[:packing]         += amt
          # else: non-item unallocated row — OzonProfitAttribution already handles it
          end
        end
      end

      [fee, meta]
    end

    # ── Step 2: match Acquiring at posting level ─────────────────────────────────

    def match_acquiring!(fee, rows)
      acq_by_pkey_sku = Hash.new(0.0)

      rows.each do |r|
        next unless r.type_id.to_i == 1 && r.posting_number.present?
        sku = r.ozon_sku_id || 0
        pk  = posting_key(r.posting_number)
        acq_by_pkey_sku[[pk, sku]] += r.amount.to_f
      end

      revenue_postings = Hash.new { |h, k| h[k] = [] }
      fee.each do |(pn, sku), v|
        next unless v[:revenue] > 0
        pk = posting_key(pn)
        revenue_postings[[pk, sku]] << pn
      end

      acq_by_pkey_sku.each do |(pk, sku), total|
        matched = revenue_postings[[pk, sku]]
        next if matched.empty?
        per = total / matched.size
        matched.each { |pn| fee[[pn, sku]][:acquiring] += per }
      end
    end

    # ── Step 3: load posting metadata from destinations + postings tables ────────

    def load_posting_meta(posting_numbers)
      return {} if posting_numbers.empty?

      meta = {}

      RawOzon::PostingDestination
        .where(account_id: @account_id, posting_number: posting_numbers)
        .each do |d|
          meta[d.posting_number] = {
            city:            d.city,
            warehouse:       d.warehouse_name,
            delivery_method: d.delivery_method_name,
            delivery_schema: d.delivery_schema,
            is_belarus:      d.is_belarus,
          }
        end

      RawOzon::PostingFbs
        .where(account_id: @account_id, posting_number: posting_numbers)
        .each do |p|
          meta[p.posting_number] ||= {}
          meta[p.posting_number].merge!(
            order_date:      p.in_process_at,
            delivering_date: p.delivering_date,
            payment_type:    p.analytics_data&.dig('payment_type_group_name'),
          )
        end

      RawOzon::PostingFbo
        .where(account_id: @account_id, posting_number: posting_numbers)
        .each do |p|
          meta[p.posting_number] ||= {}
          meta[p.posting_number].merge!(
            order_date:      p.in_process_at,
            delivering_date: p.fact_delivery_date,
            payment_type:    p.analytics_data&.dig('payment_type_group_name'),
          )
        end

      meta
    end

    # ── Step 4: build output rows ────────────────────────────────────────────────

    def build_order_rows(fee, accrual_meta, posting_meta, sku_name_map)
      sorted_keys = fee.keys.sort_by { |pn, sku|
        [accrual_meta.dig(pn, :date) || Date.new, pn, sku.to_s]
      }

      # Pass 1: count OD's own positive-revenue postings per SKU (used as distribution
      # denominators so per-SKU sums match OzonProfitAttribution totals exactly).
      # Using WR's net_sales_count as denominator would mismatch when OD has a
      # different positive-revenue-posting count (e.g. partial-period returns).
      od_pos_ct    = Hash.new(0)
      od_blr_ct    = Hash.new(0)
      od_export_ct = Hash.new(0)
      od_blr_rev   = Hash.new(0.0)
      sorted_keys.each do |(pn, sku_id)|
        next unless sku_id != 0 && fee[[pn, sku_id]][:revenue].round(2) > 0
        dest = posting_meta[pn] || {}
        od_pos_ct[sku_id] += 1
        if dest[:is_belarus]
          od_blr_ct[sku_id]  += 1
          od_blr_rev[sku_id] += fee[[pn, sku_id]][:revenue]
        else
          od_export_ct[sku_id] += 1
        end
      end

      # Pass 2: build rows
      sorted_keys.map do |(pn, sku_id)|
        v    = fee[[pn, sku_id]]
        dest = posting_meta[pn] || {}
        meta = accrual_meta[pn] || {}

        sku_r    = @sku_map[sku_id] || {}
        sku_code = sku_r[:sku_code]
        is_by    = dest[:is_belarus] || false
        rev_val  = v[:revenue].round(2)

        plat_fees = (v[:commission] + v[:delivery] + v[:acquiring] +
                     v[:dispatch]  + v[:packing]  + v[:return_delivery] + v[:storage]).round(2)

        pos_ct = od_pos_ct[sku_id]

        # CrossDock + Ad: distribute using OD's own positive-posting count.
        # This guarantees sum(per-posting) == SKU-level total, matching WR.
        crossdock_per = (sku_id != 0 && pos_ct > 0 && rev_val > 0) ?
                          (sku_r[:crossdock_fee].to_f / pos_ct).round(2) : 0.0

        book_profit = (rev_val + plat_fees + crossdock_per).round(2)

        ad_per   = (sku_id != 0 && pos_ct > 0 && rev_val > 0) ?
                     (sku_r[:total_ad_cost].to_f.abs / pos_ct).round(2) : 0.0
        book_adj = (book_profit - ad_per).round(2)

        cost_cny       = sku_r[:cost_cny]
        import_vat_cny = sku_r[:import_vat_cny]

        if cost_cny && sku_id != 0
          unit_cost = (cost_cny * @rate_eff).round(2)

          if rev_val > 0
            # Sale: charge goods cost; apply tax adjustments using OD's own counts.
            blr_ct = od_blr_ct[sku_id]
            exp_ct = od_export_ct[sku_id]

            ivat_rub = import_vat_cny.to_f * @rate_eff
            if is_by && blr_ct > 0 && ivat_rub > 0
              # Per-posting BLR tax: compute from OD's own BLR revenue, not WR totals.
              # Matches Python: blr_tax_total / blr_c using local od_blr_rev.
              blr_output    = od_blr_rev[sku_id] * 20.0 / 120.0
              blr_input     = blr_ct * ivat_rub
              blr_tax_total = [blr_output - blr_input, 0.0].max
              blr_tax_per       = -(blr_tax_total / blr_ct).round(2)
              export_refund_per = nil
            elsif !is_by && ivat_rub > 0
              # Per-unit export VAT refund — same for every sale of this SKU.
              # Matches Python: rus_refund_per = ivat * rate (no division by count).
              blr_tax_per       = nil
              export_refund_per = ivat_rub.round(2)
            else
              blr_tax_per = nil; export_refund_per = nil
            end

            pre_tax   = (book_adj - unit_cost).round(2)
            after_tax = (pre_tax + blr_tax_per.to_f + export_refund_per.to_f).round(2)
            margin_pct = (after_tax / rev_val * 100).round(1)
            goods_cost_val = -unit_cost

          elsif rev_val < 0
            # Return: recover goods cost so per-SKU sum aligns with WR's net_sales_count.
            # WR goods_cost = net_sales_count × unit_cost; OD achieves the same total by
            # charging unit_cost on each sale and refunding it on each return.
            blr_tax_per = nil; export_refund_per = nil; pre_tax = nil
            goods_cost_val = unit_cost   # positive = cost recovered
            after_tax  = (book_adj + unit_cost).round(2)
            margin_pct = nil

          else
            # Cancel (rev=0): no goods cost, no tax adjustment
            unit_cost = nil; goods_cost_val = nil
            blr_tax_per = nil; export_refund_per = nil; pre_tax = nil
            after_tax = book_adj; margin_pct = nil
          end

        else
          unit_cost = nil; goods_cost_val = nil; pre_tax = nil
          blr_tax_per = nil; export_refund_per = nil
          after_tax = book_adj; margin_pct = nil
        end

        order_type = if pn.start_with?('sr')
          '退货(仓储)'
        elsif rev_val > 0
          '成交'
        elsif rev_val < 0
          '退货'
        else
          '取消'
        end

        {
          sku_code:        sku_code || '',
          ozon_sku_id:     sku_id != 0 ? sku_id : nil,
          product_name:    sku_code ? sku_name_map[sku_code] : '',
          posting_number:  pn,
          order_date:      dest[:order_date]&.strftime('%Y-%m-%d %H:%M'),
          accrual_date:    meta[:date]&.to_s,
          delivering_date: dest[:delivering_date]&.strftime('%Y-%m-%d'),
          order_type:,
          city:                 dest[:city],
          country:              is_by ? 'Беларусь' : 'РФ',
          delivery_method: dest[:delivery_method],
          delivery_schema: dest[:delivery_schema],
          warehouse:            dest[:warehouse],
          payment_type:    dest[:payment_type],
          revenue:         rev_val,
          commission:      v[:commission].round(2),
          delivery:        v[:delivery].round(2),
          acquiring:       v[:acquiring].round(2),
          dispatch:        v[:dispatch].round(2),
          packing:         v[:packing].round(2),
          return_delivery: v[:return_delivery].round(2),
          storage:         v[:storage].round(2),
          crossdock:       crossdock_per,
          book_profit:,
          ad_cost:         ad_per > 0 ? -ad_per : nil,
          book_adj:,
          goods_cost:      goods_cost_val,
          pre_tax:,
          blr_tax:         blr_tax_per,
          export_refund:   export_refund_per,
          after_tax:,
          margin_pct:,
        }
      end
    end

    # ── Step 5: summary ──────────────────────────────────────────────────────────

    def build_summary(attr_summary)
      total_rev    = @order_rows.sum { |r| r[:revenue].to_f }.round(2)
      total_book   = @order_rows.sum { |r| r[:book_profit].to_f }.round(2)
      total_ad     = @order_rows.sum { |r| r[:ad_cost].to_f }.round(2)
      total_goods  = @order_rows.sum { |r| r[:goods_cost].to_f }.round(2)
      total_after  = @order_rows.sum { |r| r[:after_tax].to_f }.round(2)
      ua_total     = @unallocated[:total].to_f

      # Orphan ad: SKUs with ad costs but no positive-revenue postings in this period.
      # Cannot be distributed per-posting (pos_ct=0), so not captured in total_after_tax.
      # Conceptually belongs in unattributed — it's a real cost with no posting to attach to.
      orphan_ad = @sku_map.values
        .select { |r| r[:total_ad_cost].to_f != 0 && r[:net_sales_count].to_i == 0 }
        .sum    { |r| r[:total_ad_cost].to_f }
        .round(2)

      # No-cost SKU contribution: postings for SKUs with no ec_sku_cost entry.
      # WR treats after_tax_profit as nil for these (not computed), so they're
      # excluded from sku_total_after_tax. OD includes their book_adj in total_after_tax.
      nocost_contrib = @order_rows
        .select { |r| r[:ozon_sku_id].present? && @sku_map[r[:ozon_sku_id]]&.fetch(:cost_cny, nil).nil? }
        .sum    { |r| r[:after_tax].to_f }
        .round(2)
      orphan_ad_skus = @sku_map.values
        .select { |r| r[:total_ad_cost].to_f != 0 && r[:net_sales_count].to_i == 0 }
        .map    { |r| { sku_code: r[:sku_code], ozon_sku_id: r[:ozon_sku_id], ad: r[:total_ad_cost].to_f.round(2) } }

      sales_ct  = @order_rows.count { |r| r[:order_type] == '成交' }
      ret_ct    = @order_rows.count { |r| r[:order_type] == '退货' }
      cancel_ct = @order_rows.count { |r| r[:order_type] == '取消' }
      sr_ct     = @order_rows.count { |r| r[:order_type] == '退货(仓储)' }
      blr_ct    = @order_rows.count { |r| r[:country] == 'Беларусь' && r[:revenue].to_f > 0 }
      rus_ct    = @order_rows.count { |r| r[:country] == 'РФ'       && r[:revenue].to_f > 0 }

      {
        period:        "#{@from_date} ~ #{@to_date}",
        rate_cny_rub:  @rate_cny_rub,
        total_rows:    @order_rows.size,
        sales_count:   sales_ct,
        return_count:  ret_ct,
        cancel_count:  cancel_ct,
        sr_count:      sr_ct,
        blr_count:     blr_ct,
        rus_count:     rus_ct,
        total_revenue:      total_rev,
        total_book:,
        total_ad:,
        orphan_ad:,
        orphan_ad_skus:,
        total_ad_full:      (total_ad + orphan_ad).round(2),
        total_goods:,
        total_after_tax:    total_after,
        ua_total:,
        nocost_contrib:,
        # After distribution fixes, total_after_tax ≈ sku_total_after_tax
        # + orphan_ad_abs + nocost_contrib (two remaining irreconcilable gaps).
        sku_total_after_tax:    @sku_map.values.sum { |r| r[:after_tax_profit].to_f }.round(2),
        sku_total_after_tax_ua: (@sku_map.values.sum { |r| r[:after_tax_profit].to_f } + ua_total).round(2),
        # cross-check vs OzonProfitAttribution (should differ < 0.10)
        sku_total_revenue:      attr_summary[:total_sales_revenue],
        sku_total_book:         attr_summary[:total_book_profit],
        sku_total_ad:           attr_summary[:total_ad],
      }
    end

    def posting_key(pn)
      return nil unless pn
      parts = pn.to_s.split('-')
      parts.length >= 2 ? "#{parts[0]}-#{parts[1]}" : pn
    end

    def zero_fees
      { revenue: 0.0, commission: 0.0, delivery: 0.0, acquiring: 0.0,
        dispatch: 0.0, packing: 0.0, return_delivery: 0.0, storage: 0.0 }
    end
  end
end