module GoogleSheets
  # 一次运行写全 Ozon 周报，每个店铺每周写入单个 Tab（带 WR: 前缀）：
  #   WR:{week_label}-{shop_name}
  #
  # Tab 内容从上到下：SKU明细 → 汇总 → 广告 → 目的国（各节间隔 3 行）
  #
  # 批量入口（推荐）：
  #   GoogleSheets::OzonWeeklyReportService.run_all(
  #     from_date:    '2026-05-04',
  #     to_date:      '2026-05-10',
  #     rate_cny_rub: 10.9306   # CBR 原始汇率（OzonProfitAttribution 内部 ×1.03）
  #   )
  class OzonWeeklyReportService < BaseService
    GAP_ROWS = 3

    def self.run_all(from_date:, to_date:, rate_cny_rub:, account_ids: nil)
      week_num   = Date.parse(to_date.to_s).cweek
      week_label = "W#{week_num}"
      scope = RawOzon::SellerAccount.where(is_active: true)
      scope = scope.where(id: account_ids) if account_ids

      scope.each do |account|
        shop_name = account.company_name.to_s.gsub(/[:\[\]\/\\?*]/, '-').strip
        new(
          account_id:   account.id,
          from_date:,
          to_date:,
          rate_cny_rub:,
          week_label:,
          shop_name:
        ).call
      end

      puts "✓ OzonWeeklyReport #{week_label} (#{from_date}~#{to_date}) 所有店铺写入完成"
    end

    def initialize(account_id:, from_date:, to_date:, rate_cny_rub:, week_label:, shop_name:)
      super()
      @account_id   = account_id
      @from_date    = from_date
      @to_date      = to_date
      @rate_cny_rub = rate_cny_rub
      @week_label   = week_label
      @shop_name    = shop_name
    end

    def call
      svc = Ec::OzonProfitAttribution.new(
        account_id:   @account_id,
        from_date:    @from_date,
        to_date:      @to_date,
        rate_cny_rub: @rate_cny_rub
      ).call

      @results     = svc.results
      @unallocated = svc.unallocated
      @name_map    = Ec::Sku.pluck(:sku_code, :product_name_ru)
                            .each_with_object({}) { |(c, n), h| h[c] = n }

      tab = "WR:#{@week_label}-#{@shop_name}"
      @spreadsheet_sheets = nil
      ensure_sheet_exists(tab)
      clear_sheet(range: "#{tab}!A1:AZ")

      # ── Section 1: SKU ───────────────────────────────────────────────────
      sku_data_rows = @results.map { |r| sku_row(r) }
      sku_total     = sku_total_row(sku_data_rows)
      ua_rows       = unallocated_rows(@unallocated)
      sku_all_rows  = [SKU_HDR_ZH, SKU_HDR_RU] + sku_data_rows + [sku_total] + ua_rows
      sku_height    = sku_all_rows.size

      # ── Section 2: 汇总 ──────────────────────────────────────────────────
      rows_data      = build_report_rows
      summary_offset = sku_height + GAP_ROWS
      summary_rows   = [['项目 / Статья', "金额 / Сумма (#{@from_date}~#{@to_date})"]] +
                       rows_data.map { |rd| [rd[:label], rd[:value]] }
      summary_height = summary_rows.size

      # ── Section 3: 广告 ──────────────────────────────────────────────────
      ad_offset    = summary_offset + summary_height + GAP_ROWS
      ad_data_rows = @results
        .select { |r| r[:ppc_cost].to_f != 0 || r[:promotion_cost].to_f != 0 }
        .sort_by { |r| r[:total_ad_cost].to_f }
        .map do |r|
          promo = r[:promotion_cost].to_f.abs.round(2)
          ppc   = r[:ppc_cost].to_f.abs.round(2)
          [r[:ozon_sku_id], r[:sku_code], promo, ppc, (promo + ppc).round(2)]
        end
      ad_total_promo = ad_data_rows.sum { |r| r[2] }.round(2)
      ad_total_ppc   = ad_data_rows.sum { |r| r[3] }.round(2)
      ad_total_row   = [nil, '合计 / Итого', ad_total_promo, ad_total_ppc, (ad_total_promo + ad_total_ppc).round(2)]
      ad_all_rows    = [AD_HDR_ZH, AD_HDR_RU] + ad_data_rows + [ad_total_row]
      ad_height      = ad_all_rows.size

      # ── Section 4: 目的国 ────────────────────────────────────────────────
      dst_offset    = ad_offset + ad_height + GAP_ROWS
      dst_data_rows = @results
        .select { |r| r[:blr_count].to_i != 0 || r[:export_count].to_i != 0 }
        .sort_by { |r| -(r[:blr_count].to_i + r[:export_count].to_i) }
        .map { |r| [r[:ozon_sku_id], r[:sku_code], @name_map[r[:sku_code]], r[:blr_count], r[:export_count]] }
      dst_total_row = [nil, '合计 / Итого', nil,
                       dst_data_rows.sum { |r| r[3].to_i },
                       dst_data_rows.sum { |r| r[4].to_i }]
      dst_all_rows  = [DST_HDR_ZH, DST_HDR_RU] + dst_data_rows + [dst_total_row]

      # ── Write all sections ───────────────────────────────────────────────
      write_to_sheet(range: "#{tab}!A1",                     values: sku_all_rows)
      write_to_sheet(range: "#{tab}!A#{summary_offset + 1}", values: summary_rows)
      write_to_sheet(range: "#{tab}!A#{ad_offset + 1}",      values: ad_all_rows)
      write_to_sheet(range: "#{tab}!A#{dst_offset + 1}",     values: dst_all_rows)

      # ── Apply styles ─────────────────────────────────────────────────────
      @spreadsheet_sheets = nil
      sid = sheet_id(tab)
      return unless sid

      reqs = []
      reqs += sku_style_reqs(sid, num_data: sku_data_rows.size, ua_count: ua_rows.size, has_total: true)
      reqs += summary_style_reqs(sid, offset: summary_offset, rows_data:)
      reqs += ad_style_reqs(sid, offset: ad_offset, num_data: ad_data_rows.size)
      reqs += dst_style_reqs(sid, offset: dst_offset, num_data: dst_data_rows.size)
      reqs << req_freeze_rows(sid, count: 2)
      reqs += req_col_widths(sid, widths: SKU_COL_WIDTHS)
      batch_update(reqs)

      puts "✓ Ozon #{@week_label} [#{@shop_name}] 周报：单 Tab 已写入 Google Sheet"
    end

    private

    # ══════════════════════════════════════════════════════════════════
    # Section 1: SKU 明细
    # ══════════════════════════════════════════════════════════════════

    SKU_HDR_ZH = [
      'SKU', '品号', '商品名称',
      '销售收入', '平台佣金', '物流费', '支付手续费', '出货费', '打包费',
      '退货处理费', '临时仓储', '残次品处理', '越库费',
      '客户下单数', '净成交数', '退货笔数',
      '广告费', '广告费占比%',
      '账面利润', '扣广告后利润',
      '白俄订单数', '出口订单数',
      '货物成本', '白俄增值税', '出口退税',
      '税前毛利', '税后净利', '税后利润率%',
    ].freeze

    SKU_HDR_RU = [
      'SKU', 'Артикул', 'Название товара',
      'Выручка', 'Комиссия Ozon', 'Доставка', 'Эквайринг', 'Отгрузка', 'Упаковка',
      'Обработка возврата', 'Врем. хранение', 'Списание брака', 'Кросс-докинг',
      'Заказано', 'Чистые продажи', 'Возвратов',
      'Реклама', 'Доля рекламы %',
      'Маржа Ozon', 'Маржа после рекламы',
      'Заказы в РБ', 'Заказы на экспорт',
      'Себестоимость', 'НДС РБ', 'Возмещение НДС (экспорт)',
      'Прибыль до налогов', 'Чистая прибыль', 'Рентабельность %',
    ].freeze

    SKU_COL_TYPES = [
      :text, :text, :text,
      :number, :number, :number, :number, :number, :number,
      :number, :number, :number, :number,
      :integer, :integer, :integer,
      :number, :percent,
      :number, :number,
      :integer, :integer,
      :number, :number, :number,
      :number, :number, :percent,
    ].freeze

    SKU_COL_WIDTHS = [
      220, 220, 220,
      90, 90, 90, 90, 80, 80,
      90, 90, 90, 90,
      75, 75, 75,
      90, 70,
      100, 100,
      65, 65,
      90, 90, 90,
      100, 100, 70,
    ].freeze

    def sku_row(r)
      sales    = r[:sales_revenue].to_f
      total_ad = r[:total_ad_cost].to_f
      after_tax = r[:after_tax_profit]
      ad_pct    = sales != 0 ? (total_ad.abs / sales * 100).round(1) : nil
      margin    = (sales != 0 && after_tax) ? (after_tax / sales * 100).round(1) : nil
      [
        r[:ozon_sku_id], r[:sku_code], @name_map[r[:sku_code]],
        r[:sales_revenue], r[:commission], r[:delivery_charge],
        r[:payment_fee], r[:dispatch_fee], r[:packing_fee],
        r[:return_delivery], r[:storage_fee], r[:defect_fee], r[:crossdock_fee],
        r[:order_count], r[:net_sales_count], r[:return_count],
        total_ad.round(2), ad_pct,
        r[:book_profit], r[:book_profit_after_ad],
        r[:blr_count], r[:export_count],
        r[:goods_cost], r[:blr_tax], r[:export_refund],
        r[:pre_tax_profit], after_tax, margin,
      ]
    end

    def sku_total_row(data_rows)
      return ['合计 / Итого'] + Array.new(SKU_COL_TYPES.size - 1) if data_rows.empty?

      fsum = ->(i) { data_rows.sum { |r| r[i].to_f }.round(2) }
      isum = ->(i) { data_rows.sum { |r| r[i].to_i } }

      total_sales = fsum.call(3)
      total_ad    = fsum.call(16)
      total_after = fsum.call(26)
      ad_pct      = total_sales != 0 ? (total_ad.abs / total_sales * 100).round(1) : nil
      margin_pct  = total_sales != 0 ? (total_after / total_sales * 100).round(1) : nil

      [
        '合计 / Итого', nil, nil,
        total_sales,    fsum.call(4),  fsum.call(5),  fsum.call(6),
        fsum.call(7),   fsum.call(8),  fsum.call(9),  fsum.call(10),
        fsum.call(11),  fsum.call(12),
        isum.call(13),  isum.call(14), isum.call(15),
        total_ad, ad_pct,
        fsum.call(18),  fsum.call(19),
        isum.call(20),  isum.call(21),
        fsum.call(22),  fsum.call(23), fsum.call(24),
        fsum.call(25),  total_after,   margin_pct,
      ]
    end

    def unallocated_rows(unalloc)
      rows = WeeklyProfitReports::OzonUnallocatedRows.normalize(unalloc)
      return [] if rows.empty?

      result = [['未分摊费用 / Нераспределённые расходы']]
      rows.each do |row|
        result << [nil, row[:type_name], nil, row[:amount]]
      end
      result << [nil, '合计 / Итого', nil, unalloc[:total].to_f.round(2)]
      result
    end

    def sku_style_reqs(sid, num_data:, ua_count:, has_total: false)
      nc        = SKU_COL_TYPES.size
      num_hdr   = 2
      data_end  = num_hdr + num_data
      ua_start  = data_end + (has_total ? 1 : 0)

      reqs = []
      reqs << req_header_rows(sid, num_rows: num_hdr, num_cols: nc)
      reqs += req_data_rows(sid, start_row: num_hdr, end_row: data_end, col_types: SKU_COL_TYPES)

      if has_total
        reqs << req_special_row(sid, row_index: data_end, style: :total, num_cols: nc)
      end

      if ua_count > 0
        ua_hdr = ua_start
        ua_end = ua_start + ua_count
        reqs << req_special_row(sid, row_index: ua_hdr,     style: :section, num_cols: nc)
        reqs << req_special_row(sid, row_index: ua_end - 1, style: :total,   num_cols: nc)
        if ua_count > 2
          reqs += req_data_rows(sid, start_row: ua_hdr + 1, end_row: ua_end - 1,
                                col_types: Array.new(nc, :text))
        end
      end

      reqs
    end

    # ══════════════════════════════════════════════════════════════════
    # Section 2: 汇总
    # ══════════════════════════════════════════════════════════════════

    def build_report_rows
      rs = @results
      ua = @unallocated

      def rsum(results, key) = results.sum { |r| r[key].to_f }.round(2)

      total_sales    = rsum(rs, :sales_revenue)
      total_comm     = rsum(rs, :commission)
      total_deliv    = rsum(rs, :delivery_charge)
      total_pay      = rsum(rs, :payment_fee)
      total_dispatch = rsum(rs, :dispatch_fee)
      total_packing  = rsum(rs, :packing_fee)
      total_ret      = rsum(rs, :return_delivery)
      total_stor     = rsum(rs, :storage_fee)
      total_defect   = rsum(rs, :defect_fee)
      total_cross    = rsum(rs, :crossdock_fee)
      total_platform = (total_comm + total_deliv + total_pay + total_dispatch + total_packing +
                        total_ret  + total_stor  + total_defect + total_cross).round(2)
      total_promo    = rs.sum { |r| r[:promotion_cost].to_f.abs }.round(2)
      total_ppc      = rs.sum { |r| r[:ppc_cost].to_f.abs }.round(2)
      total_ad       = rsum(rs, :total_ad_cost)
      total_goods    = rsum(rs, :goods_cost)
      total_blr_tax  = rsum(rs, :blr_tax)
      total_exp_ref  = rsum(rs, :export_refund)
      total_pre_tax  = rsum(rs, :pre_tax_profit)
      total_after_tax = rsum(rs, :after_tax_profit)
      ua_total       = ua[:total].to_f.round(2)
      blr_orders     = rs.sum { |r| r[:blr_count].to_i }
      exp_orders     = rs.sum { |r| r[:export_count].to_i }

      margin_pct     = total_sales != 0 ? (total_after_tax / total_sales * 100).round(2) : nil
      margin_incl    = total_sales != 0 ? ((total_after_tax + ua_total) / total_sales * 100).round(2) : nil

      [
        { label: '数据周期 / Период',          value: "#{@from_date} ~ #{@to_date}", type: :normal },
        { label: '汇率 RUB/CNY',               value: @rate_cny_rub,                 type: :normal },
        { label: 'SKU总数 / Всего SKU',        value: rs.size,                       type: :normal },
        { label: '有销售 / С продажами',       value: rs.count { |r| r[:sales_revenue].to_f != 0 }, type: :normal },
        { label: '仅广告 / Только реклама',    value: rs.count { |r| r[:sales_revenue].to_f == 0 && r[:total_ad_cost].to_f != 0 }, type: :normal },
        { label: '白俄订单 / Заказы РБ',       value: blr_orders,                    type: :normal },
        { label: '出口订单 / Заказы экспорт',  value: exp_orders,                    type: :normal },
        { label: '── 收入 / Доходы ──',        value: nil,                           type: :section },
        { label: '销售收入 / Выручка',         value: total_sales,                   type: :normal },
        { label: '── 已分摊费用 / Распределённые расходы ──', value: nil,           type: :section },
        { label: '平台佣金 / Комиссия Ozon',   value: total_comm,                    type: :normal },
        { label: '物流费 / Доставка',          value: total_deliv,                   type: :normal },
        { label: '支付手续费 / Эквайринг',     value: total_pay,                     type: :normal },
        { label: '出货费 / Отгрузка',          value: total_dispatch,                type: :normal },
        { label: '打包费 / Упаковка',          value: total_packing,                 type: :normal },
        { label: '退货处理费 / Обработка',     value: total_ret,                     type: :normal },
        { label: '临时仓储 / Хранение',        value: total_stor,                    type: :normal },
        { label: '残次品 / Брак',              value: total_defect,                  type: :normal },
        { label: '越库费 / Кросс-докинг',      value: total_cross,                   type: :normal },
        { label: '平台费合计 / Платформа итого', value: total_platform,              type: :subtotal },
        { label: '── 广告费 / Реклама ──',     value: nil,                           type: :section },
        { label: 'Promotion / Продвижение',     value: -total_promo,                  type: :normal },
        { label: 'PPC / Оплата за клики',       value: -total_ppc,                    type: :normal },
        { label: '广告费合计 / Реклама итого',  value: total_ad,                      type: :subtotal },
        { label: '平台+广告合计',               value: (total_platform + total_ad).round(2), type: :subtotal },
        { label: '── 货物成本 / Себестоимость ──', value: nil,                       type: :section },
        { label: '货物成本 / Себестоимость',    value: total_goods,                   type: :normal },
        { label: '── 税务 / Налоги ──',        value: nil,                           type: :section },
        { label: '白俄增值税 / НДС РБ',        value: total_blr_tax,                 type: :normal },
        { label: '出口退税 / Возмещение НДС',  value: total_exp_ref,                 type: :normal },
        { label: '── 未分摊 / Нераспределено ──', value: nil,                        type: :section },
        { label: 'Ускоренная проверка (96)',    value: ua.dig(:rows)&.select { |r| r[:type_id].to_i == 96 }&.sum { |r| r[:amount].to_f }&.round(2) || 0, type: :normal },
        { label: 'Штраф задержка отгрузки (94)', value: ua.dig(:rows)&.select { |r| r[:type_id].to_i == 94 }&.sum { |r| r[:amount].to_f }&.round(2) || 0, type: :normal },
        { label: 'Эквайринг не привязан (1)',  value: ua.dig(:rows)&.select { |r| r[:type_id].to_i == 1 }&.sum { |r| r[:amount].to_f }&.round(2) || 0, type: :normal },
        { label: '未分摊合计 / Нераспред. итого', value: ua_total,                   type: :subtotal },
        { label: '── 利润 / Прибыль ──',       value: nil,                           type: :section },
        { label: '税前毛利 / Прибыль до налогов', value: total_pre_tax,              type: :normal },
        { label: '税后净利 / Чистая прибыль',  value: total_after_tax,               type: :total },
        { label: '税后利润率 / Рентабельность', value: margin_pct,                   type: :normal },
        { label: '税后净利(含未分摊)',           value: (total_after_tax + ua_total).round(2), type: :total },
        { label: '税后利润率(含未分摊)',         value: margin_incl,                  type: :normal },
      ]
    end

    def summary_style_reqs(sid, offset:, rows_data:)
      reqs = []
      reqs << req_header_rows(sid, start_row: offset, num_rows: 1, num_cols: 2)

      rows_data.each_with_index do |rd, i|
        row_idx = offset + 1 + i
        case rd[:type]
        when :section  then reqs << req_special_row(sid, row_index: row_idx, style: :sub,     num_cols: 2)
        when :total    then reqs << req_special_row(sid, row_index: row_idx, style: :total,   num_cols: 2)
        when :subtotal then reqs << req_special_row(sid, row_index: row_idx, style: :section, num_cols: 2)
        end

        next unless rd[:value].is_a?(Numeric)
        fmt = rd[:value].is_a?(Float) && rd[:label].include?('率') ? FMT_PERCENT : FMT_NUMBER
        reqs << {
          repeat_cell: {
            range: grid(sid, row_idx, row_idx + 1, 1, 2),
            cell: { user_entered_format: {
              number_format: { type: 'NUMBER', pattern: fmt },
              horizontal_alignment: 'RIGHT',
            }},
            fields: 'userEnteredFormat(numberFormat,horizontalAlignment)',
          }
        }
      end

      reqs << {
        repeat_cell: {
          range: grid(sid, offset, offset + 1 + rows_data.size, 0, 1),
          cell: { user_entered_format: {
            wrap_strategy: 'WRAP',
            vertical_alignment: 'MIDDLE',
          }},
          fields: 'userEnteredFormat(wrapStrategy,verticalAlignment)',
        }
      }
      reqs += req_data_rows(sid, start_row: offset + 1, end_row: offset + 1 + rows_data.size,
                            col_types: [:text, :text])
      reqs
    end

    # ══════════════════════════════════════════════════════════════════
    # Section 3: 广告费
    # ══════════════════════════════════════════════════════════════════

    AD_HDR_ZH = ['SKU', '品号', 'Promotion', 'PPC', '广告费合计'].freeze
    AD_HDR_RU = ['SKU', 'Артикул', 'Продвижение', 'Оплата за клики', 'Реклама итого'].freeze
    AD_COL_TYPES  = [:text, :text, :number, :number, :number].freeze

    def ad_style_reqs(sid, offset:, num_data:)
      nc   = AD_COL_TYPES.size
      reqs = []
      reqs << req_header_rows(sid, start_row: offset, num_rows: 2, num_cols: nc)
      reqs += req_data_rows(sid, start_row: offset + 2, end_row: offset + 2 + num_data,
                            col_types: AD_COL_TYPES)
      reqs << req_special_row(sid, row_index: offset + 2 + num_data,
                              style: :total, num_cols: nc)
      reqs
    end

    # ══════════════════════════════════════════════════════════════════
    # Section 4: 订单目的国
    # ══════════════════════════════════════════════════════════════════

    DST_HDR_ZH  = ['SKU', '品号', '商品名称', '白俄订单', '出口订单'].freeze
    DST_HDR_RU  = ['SKU', 'Артикул', 'Название товара', 'Заказы РБ', 'Заказы экспорт'].freeze
    DST_COL_TYPES  = [:text, :text, :text, :integer, :integer].freeze

    def dst_style_reqs(sid, offset:, num_data:)
      nc   = DST_COL_TYPES.size
      reqs = []
      reqs << req_header_rows(sid, start_row: offset, num_rows: 2, num_cols: nc)
      reqs += req_data_rows(sid, start_row: offset + 2, end_row: offset + 2 + num_data,
                            col_types: DST_COL_TYPES)
      reqs << req_special_row(sid, row_index: offset + 2 + num_data,
                              style: :total, num_cols: nc)
      reqs
    end
  end
end
