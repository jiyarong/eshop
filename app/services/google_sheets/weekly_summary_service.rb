module GoogleSheets
  # 跨平台、跨店铺的周利润汇总报表，Tab 命名 WSU:W{n}
  #
  # 数据来源：WbProfitAttribution + OzonProfitAttribution
  # 币种：全部换算为 CNY
  #   WB  (BYN) × rate_byn_rub / rate_cny_rub → CNY
  #   Ozon (RUB) / rate_cny_rub              → CNY
  #
  # 用法：
  #   GoogleSheets::WeeklySummaryService.run(
  #     from_date:  '2026-05-25',
  #     to_date:    '2026-05-31',
  #     week_label: 'W22'
  #   )
  class WeeklySummaryService < BaseService
    HDR_ZH = ['SKU', '平台', '店铺', '净销量', '销售额(CNY)', '广告费(CNY)', '货物成本(CNY)',
              '税前毛利(CNY)', '税/营业税(CNY)', '税后净利(CNY)', '利润率%',
              '上周净销量', '上周销售额(CNY)', '销量环比%', '销售额环比%'].freeze

    HDR_RU = ['Артикул', 'Платформа', 'Магазин', 'Чистые продажи', 'Выручка(CNY)',
              'Реклама(CNY)', 'Себестоимость(CNY)', 'До налогов(CNY)', 'Налог(CNY)',
              'Чистая прибыль(CNY)', 'Рентабельность%',
              'Продажи пр.н.', 'Выручка пр.н.(CNY)', 'Δ продаж%', 'Δ выручки%'].freeze

    COL_TYPES = %i[text text text int num num num num num num pct int num pct pct].freeze
    COL_WIDTHS = [100, 60, 120, 70, 100, 90, 100, 100, 100, 100, 70, 80, 100, 70, 70].freeze

    def self.run(from_date:, to_date:, week_label:)
      new(from_date: from_date, to_date: to_date, week_label: week_label).call
    end

    def initialize(from_date:, to_date:, week_label:)
      super()
      @from_date  = from_date.to_date
      @to_date    = to_date.to_date
      @week_label = week_label
      @rate       = Ec::WeeklyRate.resolve(@from_date)
      raise "找不到 #{@from_date} 的汇率，请先录入 ec_weekly_rates" unless @rate
    end

    def call
      puts "→ WeeklySummaryService #{@week_label} (#{@from_date}~#{@to_date}) CNY/RUB=#{@rate.rate_cny_rub} BYN/RUB=#{@rate.rate_byn_rub}"

      rows, @unalloc_cny = collect_rows(@from_date, @to_date, @rate)

      prev_from = @from_date - 7
      prev_to   = @to_date   - 7
      prev_rate = Ec::WeeklyRate.resolve(prev_from)
      prev_rows, _ = prev_rate ? collect_rows(prev_from, prev_to, prev_rate) : [[], nil]
      prev_map  = prev_rows.index_by { |r| [r[:sku], r[:platform], r[:shop]] }

      tab = "WSU:#{@week_label}"
      @spreadsheet_sheets = nil
      ensure_sheet_exists(tab)
      clear_sheet(range: "#{tab}!A1:Z")
      sid_pre = sheet_id(tab)
      batch_update([req_clear_format(sid_pre)]) if sid_pre

      data_rows = build_data_rows(rows, prev_map)
      total_row = build_total_row(rows)

      all_rows  = [HDR_ZH, HDR_RU] + data_rows + [total_row]
      write_to_sheet(range: "#{tab}!A1", values: all_rows)

      # ── 摘要区（隔3行，纵向） ──────────────────────────────────────────────
      summary_offset = all_rows.size + 3
      write_to_sheet(range: "#{tab}!A#{summary_offset + 1}", values: build_summary(rows))

      # ── 样式 ──────────────────────────────────────────────────────────────
      @spreadsheet_sheets = nil
      sid = sheet_id(tab)
      if sid
        nc       = COL_TYPES.size
        data_end = 2 + data_rows.size
        reqs = []
        reqs << req_header_rows(sid, num_rows: 2, num_cols: nc)
        reqs += req_data_rows(sid, start_row: 2, end_row: data_end, col_types: COL_TYPES)
        reqs << req_special_row(sid, row_index: data_end, style: :total, num_cols: nc)
        reqs << req_freeze_rows(sid, count: 2)
        reqs += req_col_widths(sid, widths: COL_WIDTHS)
        batch_update(reqs)
      end

      puts "✓ WSU:#{@week_label} 写入完成（#{data_rows.size} 行）"
    end

    private

    # ── 数据采集 ──────────────────────────────────────────────────────────────

    def collect_rows(from_date, to_date, rate)
      byn_cny    = rate.rate_byn_rub / rate.rate_cny_rub
      rub_cny    = 1.0 / rate.rate_cny_rub
      rows       = []
      unalloc    = { wb: 0.0, ozon: 0.0 }

      RawWb::SellerAccount.all.each do |acct|
        svc = Ec::WbProfitAttribution.new(
          account_id:   acct.id,
          from_date:    from_date,
          to_date:      to_date,
          rate_cny_rub: rate.rate_cny_rub,
          rate_byn_rub: rate.rate_byn_rub
        ).call

        shop = acct.name.to_s.strip
        svc.results.group_by { |r| r[:vendor_code] }.each do |sku, rs|
          next if sku.blank?
          net_sales  = rs.sum { |r| r[:sales_qty] - r[:return_qty] }
          revenue    = (rs.sum { |r| r[:settlement] }    * byn_cny).round(2)
          ads        = (rs.sum { |r| r[:ad] }             * byn_cny).round(2)
          goods_cost = (rs.sum { |r| r[:goods_cost] }     * byn_cny).round(2)
          pre_tax    = (rs.sum { |r| r[:pre_tax] }        * byn_cny).round(2)
          after_tax  = (rs.sum { |r| r[:after_tax] }      * byn_cny).round(2)
          tax        = (pre_tax - after_tax).round(2)

          rows << { sku: sku, platform: 'WB', shop: shop,
                    net_sales: net_sales, revenue: revenue, ads: ads,
                    goods_cost: goods_cost, pre_tax: pre_tax, tax: tax, after_tax: after_tax }
        end

        # WB unallocated: label=>byn_amount hash，值为正数代表成本，取负表示对利润的冲击
        unalloc[:wb] += -(svc.unallocated.values.sum.to_f * byn_cny).round(2)
      end

      RawOzon::SellerAccount.all.each do |acct|
        svc = Ec::OzonProfitAttribution.new(
          account_id:            acct.id,
          from_date:             from_date,
          to_date:               to_date,
          rate_cny_rub:          rate.rate_cny_rub,
          sync_missing_ad_costs: false
        ).call

        shop = acct.company_name.to_s.strip
        svc.results.each do |r|
          next if r[:sku_code].blank?
          revenue    = (r[:sales_revenue]         * rub_cny).round(2)
          ads        = (-(r[:ppc_cost].to_f + r[:promotion_cost].to_f) * rub_cny).round(2)
          goods_cost = (-r[:goods_cost].to_f       * rub_cny).round(2)
          pre_tax    = (r[:pre_tax_profit].to_f    * rub_cny).round(2)
          after_tax  = (r[:after_tax_profit].to_f  * rub_cny).round(2)
          tax        = (pre_tax - after_tax).round(2)

          rows << { sku: r[:sku_code], platform: 'Ozon', shop: shop,
                    net_sales: r[:net_sales_count], revenue: revenue, ads: ads,
                    goods_cost: goods_cost, pre_tax: pre_tax, tax: tax, after_tax: after_tax }
        end

        # Ozon unallocated: other 是非广告类未归属费用（RUB），total 含孤儿广告
        unalloc[:ozon] += (svc.unallocated[:total].to_f * rub_cny).round(2)
      end

      [rows, unalloc]
    end

    # ── 行构建 ────────────────────────────────────────────────────────────────

    def build_data_rows(rows, prev_map)
      rows.sort_by { |r| -(r[:after_tax] || 0) }.map do |r|
        prev       = prev_map[[r[:sku], r[:platform], r[:shop]]]
        margin     = r[:revenue] != 0 ? (r[:after_tax] / r[:revenue] * 100).round(1) : nil
        prev_sales = prev&.dig(:net_sales)
        prev_rev   = prev&.dig(:revenue)
        sales_chg  = (prev_sales && prev_sales != 0) ? ((r[:net_sales] - prev_sales).to_f / prev_sales * 100).round(1) : nil
        rev_chg    = (prev_rev && prev_rev != 0) ? ((r[:revenue] - prev_rev) / prev_rev * 100).round(1) : nil

        [r[:sku], r[:platform], r[:shop], r[:net_sales],
         r[:revenue], r[:ads], r[:goods_cost], r[:pre_tax], r[:tax], r[:after_tax],
         margin, prev_sales, prev_rev, sales_chg, rev_chg]
      end
    end

    def build_total_row(rows)
      total_rev   = rows.sum { |r| r[:revenue] }.round(2)
      total_at    = rows.sum { |r| r[:after_tax] }.round(2)
      margin      = total_rev != 0 ? (total_at / total_rev * 100).round(1) : nil
      ['合计 / Итого', '', '',
       rows.sum { |r| r[:net_sales] },
       total_rev,
       rows.sum { |r| r[:ads] }.round(2),
       rows.sum { |r| r[:goods_cost] }.round(2),
       rows.sum { |r| r[:pre_tax] }.round(2),
       rows.sum { |r| r[:tax] }.round(2),
       total_at,
       margin, '', '', '', '']
    end

    def build_summary(rows)
      wb_rows   = rows.select { |r| r[:platform] == 'WB' }
      ozon_rows = rows.select { |r| r[:platform] == 'Ozon' }
      total_rev = rows.sum { |r| r[:revenue] }.round(2)
      total_at  = rows.sum { |r| r[:after_tax] }.round(2)
      margin    = total_rev != 0 ? (total_at / total_rev * 100).round(1) : nil

      wb_unalloc   = @unalloc_cny&.dig(:wb).to_f.round(2)
      ozon_unalloc = @unalloc_cny&.dig(:ozon).to_f.round(2)
      total_unalloc = (wb_unalloc + ozon_unalloc).round(2)

      [
        ['项目', '金额(CNY)'],
        ['数据周期', "#{@from_date} ~ #{@to_date}"],
        ['汇率 CNY/RUB', @rate.rate_cny_rub],
        ['汇率 BYN/RUB', @rate.rate_byn_rub],
        [],
        ['── WB ──', ''],
        ['销售额',   wb_rows.sum { |r| r[:revenue] }.round(2)],
        ['广告费',   wb_rows.sum { |r| r[:ads] }.round(2)],
        ['货物成本', wb_rows.sum { |r| r[:goods_cost] }.round(2)],
        ['税前毛利', wb_rows.sum { |r| r[:pre_tax] }.round(2)],
        ['税后净利', wb_rows.sum { |r| r[:after_tax] }.round(2)],
        [],
        ['── Ozon ──', ''],
        ['销售额',   ozon_rows.sum { |r| r[:revenue] }.round(2)],
        ['广告费',   ozon_rows.sum { |r| r[:ads] }.round(2)],
        ['货物成本', ozon_rows.sum { |r| r[:goods_cost] }.round(2)],
        ['税前毛利', ozon_rows.sum { |r| r[:pre_tax] }.round(2)],
        ['税后净利', ozon_rows.sum { |r| r[:after_tax] }.round(2)],
        [],
        ['── 合计 ──', ''],
        ['总销售额', total_rev],
        ['总税后净利', total_at],
        ['综合利润率', margin ? "#{margin}%" : 'N/A'],
        [],
        ['── 未分摊费用（参考，负=成本）──', ''],
        ['WB 未分摊', wb_unalloc],
        ['Ozon 未分摊（含孤儿广告）', ozon_unalloc],
        ['未分摊合计', total_unalloc],
        [],
        ['── 含未分摊利润 ──', ''],
        ['税后净利（不含未分摊）', total_at],
        ['未分摊净影响', total_unalloc],
        ['税后净利（含未分摊）', (total_at + total_unalloc).round(2)],
        ['综合利润率（含未分摊）', total_rev != 0 ? "#{((total_at + total_unalloc) / total_rev * 100).round(1)}%" : 'N/A'],
      ]
    end
  end
end
