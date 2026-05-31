module GoogleSheets
  # 将 Ec::OzonOrderDetailReport 写入 Google Sheet。
  # Tab 命名：OD:{week_label}-{shop_name}
  # 内容：Section 1 订单明细（按结算日排序）+ Section 2 汇总对账（隔 3 行）
  #
  # 单店铺：
  #   GoogleSheets::OzonOrderDetailSheetService.new(
  #     account_id:   1,
  #     from_date:    '2026-04-27',
  #     to_date:      '2026-05-03',
  #     rate_cny_rub: 11.26,
  #     week_label:   'W18',
  #     shop_name:    'Nevastal'
  #   ).call
  #
  # 全店铺：
  #   GoogleSheets::OzonOrderDetailSheetService.run_all(
  #     from_date: '2026-04-27', to_date: '2026-05-03', rate_cny_rub: 11.26
  #   )
  class OzonOrderDetailSheetService < BaseService
    GAP_ROWS = 3

    HDR_ZH = [
      '品号', 'SKU', '商品名称', '订单号', '下单时间', '结算日', '签收时间', '订单类型',
      '城市', '国家', '配送方式', '配送模式', '发货仓', '支付方式',
      '销售收入', '平台佣金', '配送费', '支付手续费', '退仓取件费', '打包费',
      '退货处理费', '退货暂存费', '越库费(分摊)',
      '账面利润', '广告费(分摊)', '扣广告后', '货物成本(分摊)',
      '税前毛利', '白俄增值税', '出口退税', '税后净利', '税后利润率%',
    ].freeze

    HDR_RU = [
      'Артикул', 'SKU', 'Название', '№ заказа', 'Дата заказа', 'Дата расчёта', 'Дата доставки', 'Тип',
      'Город', 'Страна', 'Способ доставки', 'Схема', 'Склад', 'Оплата',
      'Выручка', 'Комиссия Ozon', 'Логистика', 'Эквайринг', 'Вывоз со склада', 'Упаковка',
      'Обработка возврата', 'Хранение возврата', 'Кросс-докинг',
      'Маржа Ozon', 'Реклама (доля)', 'Маржа после рекл.', 'Себестоимость',
      'Прибыль до налогов', 'НДС РБ', 'Возмещение НДС', 'Чистая прибыль', 'Рентабельность %',
    ].freeze

    COL_TYPES = [
      :text, :text, :text, :text, :text, :text, :text, :text,  # meta (8)
      :text, :text, :text, :text, :text, :text,                 # location (6)
      :number, :number, :number, :number, :number, :number,     # fees 1-6
      :number, :number, :number,                                 # fees 7-9
      :number, :number, :number, :number,                        # profit 1-4
      :number, :number, :number, :number, :percent,              # profit 5-9
    ].freeze

    COL_WIDTHS = [
      100, 100, 160, 180, 115, 80, 80, 70,   # meta
      80, 65, 130, 65, 100, 100,              # location
      82, 82, 82, 82, 80, 70,                # fees 1-6
      82, 82, 80,                             # fees 7-9
      85, 80, 85, 82,                         # profit 1-4
      82, 80, 80, 85, 65,                     # profit 5-9
    ].freeze

    NUM_HDR = 2

    def self.run_all(from_date:, to_date:, rate_cny_rub: nil)
      week_label = "W#{Date.parse(to_date.to_s).cweek}"
      if rate_cny_rub.nil?
        wr = Ec::WeeklyRate.resolve(Date.parse(from_date.to_s).beginning_of_week)
        raise "无法获取 #{from_date} 的汇率（CBR 失败且无历史记录）" unless wr
        rate_cny_rub = wr.rate_cny_rub
        puts "[OzonOrderDetail] 汇率自动获取：#{wr.week_start} CNY/RUB=#{rate_cny_rub}"
      end

      RawOzon::SellerAccount.where(is_active: true).each do |account|
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

      puts "✓ OzonOrderDetail #{from_date}~#{to_date} 所有店铺写入完成"
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
      svc = Ec::OzonOrderDetailReport.new(
        account_id:   @account_id,
        from_date:    @from_date,
        to_date:      @to_date,
        rate_cny_rub: @rate_cny_rub
      ).call

      @order_rows = svc.order_rows
      @summary    = svc.summary

      print_reconciliation

      tab = "OD:#{@week_label}-#{@shop_name}"
      @spreadsheet_sheets = nil
      ensure_sheet_exists(tab)
      clear_sheet(range: "#{tab}!A1:AZ")

      data_rows    = @order_rows.map { |r| to_sheet_row(r) }
      all_detail   = [HDR_ZH, HDR_RU] + data_rows
      summary_rows = build_summary_rows

      write_to_sheet(range: "#{tab}!A1", values: all_detail)
      write_to_sheet(range: "#{tab}!A#{all_detail.size + GAP_ROWS + 1}", values: summary_rows)

      @spreadsheet_sheets = nil
      sid = sheet_id(tab)
      if sid
        summary_offset = all_detail.size + GAP_ROWS
        reqs = []
        reqs << req_clear_format(sid, num_rows: summary_offset + summary_rows.size + 5,
                                      num_cols: HDR_ZH.size)
        reqs << req_header_rows(sid, num_rows: NUM_HDR, num_cols: HDR_ZH.size)
        reqs += req_data_rows(sid, start_row: NUM_HDR, end_row: NUM_HDR + data_rows.size,
                              col_types: COL_TYPES)
        reqs << req_freeze_rows(sid, count: NUM_HDR)
        reqs += req_col_widths(sid, widths: COL_WIDTHS)
        reqs += summary_style_reqs(sid, offset: summary_offset, rows: summary_rows)
        batch_update(reqs)
      end

      puts "✓ OzonOrderDetail #{@week_label} [#{@shop_name}]: #{data_rows.size} 行写入 Google Sheet"
    end

    private

    # ── Row conversion ────────────────────────────────────────────────────────────

    def to_sheet_row(r)
      [
        r[:sku_code], r[:ozon_sku_id], r[:product_name], r[:posting_number],
        r[:order_date], r[:accrual_date], r[:delivering_date], r[:order_type],
        r[:city], r[:country], r[:delivery_method], r[:delivery_schema],
        r[:warehouse], r[:payment_type],
        r[:revenue], r[:commission], r[:delivery], r[:acquiring],
        r[:dispatch], r[:packing], r[:return_delivery], r[:storage], r[:crossdock],
        r[:book_profit], r[:ad_cost], r[:book_adj],
        r[:goods_cost], r[:pre_tax], r[:blr_tax], r[:export_refund],
        r[:after_tax], r[:margin_pct],
      ]
    end

    # ── Summary section ───────────────────────────────────────────────────────────

    def build_summary_rows
      s = @summary
      rev_diff  = (s[:total_revenue]  - s[:sku_total_revenue]).round(2)
      book_diff = (s[:total_book]     - s[:sku_total_book]).round(2)
      ad_diff   = (s[:total_ad_full]  - s[:sku_total_ad]).round(2)

      rows = [
        ['项目 / Статья', '数值'],
        ['数据周期 / Период',       "#{@from_date} ~ #{@to_date}"],
        ['汇率 RUB/CNY',            s[:rate_cny_rub]],
        ['总行数 / Всего строк',    s[:total_rows]],
        ['── 订单计数 ──',           nil],
        ['成交 / Продажи',          s[:sales_count]],
        ['退货 / Возвраты',         s[:return_count]],
        ['取消 / Отмены',           s[:cancel_count]],
        ['仓储退货 / Возврат скл.',  s[:sr_count]],
        ['白俄成交 / Продажи РБ',   s[:blr_count]],
        ['出口成交 / Экспорт',      s[:rus_count]],
        ['── 金额对账（vs SKU报告）──', nil],
        ['销售收入（订单明细）',     s[:total_revenue]],
        ['销售收入（SKU报告）',      s[:sku_total_revenue]],
        ["  差异#{rev_diff.abs  < 0.1 ? ' ✅' : ' ❌'}", rev_diff],
        ['账面利润（订单明细）',     s[:total_book]],
        ['账面利润（SKU报告）',      s[:sku_total_book]],
        ["  差异#{book_diff.abs < 0.1 ? ' ✅' : ' ❌'}", book_diff],
        ['广告费合计（分摊+孤儿）',  s[:total_ad_full]],
        ['广告费（SKU报告）',        s[:sku_total_ad]],
        ["  差异#{ad_diff.abs   < 0.1 ? ' ✅' : ' ❌'}", ad_diff],
        ['── 利润链汇总 ──',         nil],
        ['广告费（已分摊）/ Реклама распред.', s[:total_ad]],
      ]

      # Show orphan ad SKUs if any
      if s[:orphan_ad] != 0
        rows << ['广告费（无成交SKU，未分摊）', s[:orphan_ad]]
        s[:orphan_ad_skus].each do |sk|
          rows << ["  #{sk[:sku_code]} (#{sk[:ozon_sku_id]})", sk[:ad]]
        end
      end

      rows += [
        ['货物成本 / Себестоимость',    s[:total_goods]],
        ['税后净利(订单口径)',           s[:total_after_tax]],
      ]

      # Explain remaining gap vs SKU-level: orphan ad + no-cost SKU contribution
      if s[:orphan_ad].to_f != 0
        rows << ['  其中孤儿广告（无成交SKU）', s[:orphan_ad]]
      end
      if s[:nocost_contrib].to_f != 0
        rows << ['  其中无成本SKU贡献', s[:nocost_contrib]]
      end

      rows += [
        ['税后净利(SKU口径) / Чистая прибыль', s[:sku_total_after_tax]],
        ['未分摊 / Нераспред.',               s[:ua_total]],
        ['税后净利(含未分摊)',                  s[:sku_total_after_tax_ua]],
      ]
      rows
    end

    # ── Styles ────────────────────────────────────────────────────────────────────

    def summary_style_reqs(sid, offset:, rows:)
      reqs = []
      reqs << req_header_rows(sid, start_row: offset, num_rows: 1, num_cols: 2)

      rows.each_with_index do |row, i|
        row_idx = offset + i
        label   = row[0].to_s
        if label.start_with?('──')
          reqs << req_special_row(sid, row_index: row_idx, style: :section, num_cols: 2)
        elsif label.include?('税后净利(含')
          reqs << req_special_row(sid, row_index: row_idx, style: :total, num_cols: 2)
        end
        next unless row[1].is_a?(Numeric) && row[1].is_a?(Float)
        reqs << {
          repeat_cell: {
            range: grid(sid, row_idx, row_idx + 1, 1, 2),
            cell:  { user_entered_format: {
              number_format:       { type: 'NUMBER', pattern: FMT_NUMBER },
              horizontal_alignment: 'RIGHT',
            }},
            fields: 'userEnteredFormat(numberFormat,horizontalAlignment)',
          }
        }
      end
      reqs
    end

    def print_reconciliation
      s = @summary
      puts "\n#{'=' * 55}"
      puts "  OzonOrderDetail 对账: #{@shop_name} #{s[:period]}"
      puts '=' * 55
      rev_diff  = (s[:total_revenue] - s[:sku_total_revenue]).round(2)
      book_diff = (s[:total_book]    - s[:sku_total_book]).round(2)
      ad_diff = (s[:total_ad_full] - s[:sku_total_ad]).round(2)
      puts "  #{rev_diff.abs  < 0.1 ? '✅' : '❌'} 销售收入:  #{s[:total_revenue]} vs SKU #{s[:sku_total_revenue]} diff=#{rev_diff}"
      puts "  #{book_diff.abs < 0.1 ? '✅' : '❌'} 账面利润:  #{s[:total_book]} vs SKU #{s[:sku_total_book]} diff=#{book_diff}"
      puts "  #{ad_diff.abs   < 0.1 ? '✅' : '❌'} 广告费:    #{s[:total_ad_full]} vs SKU #{s[:sku_total_ad]} diff=#{ad_diff} (孤儿: #{s[:orphan_ad]})"
      puts "  货物成本:         #{s[:total_goods]}"
      puts "  税后净利(订单口径): #{s[:total_after_tax]}"
      puts "  税后净利(SKU口径):  #{s[:sku_total_after_tax]}"
      puts "    孤儿广告:       #{s[:orphan_ad]}"
      puts "    无成本SKU贡献:  #{s[:nocost_contrib]}"
      puts "    其余残差:       #{(s[:total_after_tax].to_f - s[:sku_total_after_tax].to_f - s[:orphan_ad].to_f.abs - s[:nocost_contrib].to_f).round(2)}"
      puts "  未分摊:           #{s[:ua_total]}"
      puts "  成交 #{s[:sales_count]}  退货 #{s[:return_count]}  取消 #{s[:cancel_count]}  仓储退 #{s[:sr_count]}"
      puts "  白俄 #{s[:blr_count]}  出口 #{s[:rus_count]}  共 #{s[:total_rows]} 行"
    end
  end
end
