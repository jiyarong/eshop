module GoogleSheets
  # 将 Ec::WbOrderDetailReport 写入 Google Sheet。
  # Tab 命名：WOD:{week_label}-{shop_name}
  #
  # 单店铺：
  #   GoogleSheets::WbOrderDetailSheetService.new(
  #     account_id:   3,
  #     from_date:    '2026-05-04',
  #     to_date:      '2026-05-10',
  #     rate_cny_rub: 10.9306,
  #     rate_byn_rub: 26.4654,
  #     week_label:   'W19',
  #     shop_name:    'WorldChoice'
  #   ).call
  #
  # 全店铺：
  #   GoogleSheets::WbOrderDetailSheetService.run_all(
  #     from_date: '2026-05-04', to_date: '2026-05-10'
  #   )
  class WbOrderDetailSheetService < BaseService
    GAP_ROWS = 3
    NUM_HDR  = 2

    HDR_ZH = [
      'nmId', '品号', '品牌', '商品名称', 'shkId', '交易类型', '区域', '区域代码',
      '下单时间', '签收时间', '国家', '发货仓', '自提点/配送地址', '配送方式',
      '折后标价', 'SPP%', '客户支付', '佣金率%', '结算额(forPay)',
      '收单费', '配送费', '罚款', '补收运费', '自提点费用',
      '仓储费(分摊)', '广告费(分摊)', '账面小计',
      '税基(折后标价)', '货物成本(分摊)', '税前毛利', 'VAT净额', '税后净利', '利润率%',
    ].freeze

    HDR_RU = [
      'nmId', 'Артикул', 'Бренд', 'Название', 'shkId (заказ)', 'Тип', 'Регион', 'Тип отчёта',
      'Дата заказа', 'Дата продажи', 'Страна', 'Склад', 'ПВЗ / Адрес', 'Способ доставки',
      'Цена со скидкой', 'СПП%', 'Оплата клиента', 'Комиссия%', 'Расчёт (forPay)',
      'Эквайринг', 'Доставка', 'Штраф', 'Доп. доставка', 'Выдача ПВЗ',
      'Хранение (доля)', 'Реклама (доля)', 'Итого',
      'База НДС', 'Себестоимость', 'До налогов', 'НДС нетто', 'Чистая прибыль', 'Рентабельность%',
    ].freeze

    COL_TYPES = [
      :number, :text, :text, :text, :number, :text, :text, :number,  # meta
      :text, :text, :text, :text, :text, :text,                       # dates + location
      :number, :number, :number, :number, :number,                    # price cols
      :number, :number, :number, :number, :number,                    # fee cols 1-5
      :number, :number, :number,                                       # fee cols 6-8
      :number, :number, :number, :number, :number, :percent,          # profit
    ].freeze

    COL_WIDTHS = [
      90, 100, 80, 180, 110, 70, 60, 65,    # meta
      90, 90, 80, 90, 160, 100,             # dates + location
      80, 55, 80, 65, 90,                   # price
      70, 70, 60, 80, 80,                   # fees 1-5
      80, 80, 80,                            # fees 6-8
      90, 90, 80, 70, 80, 60,               # profit
    ].freeze

    COLORS = {
      '成交' => { red: 0.91, green: 0.96, blue: 0.91 },
      '退货' => { red: 1.0,  green: 0.92, blue: 0.93 },
    }.freeze

    def self.run_all(from_date:, to_date:, rate_cny_rub: nil, rate_byn_rub: nil, account_ids: nil)
      week_label = "W#{Date.parse(to_date.to_s).cweek}"
      week_start = Date.parse(from_date.to_s).beginning_of_week

      if rate_cny_rub.nil? || rate_byn_rub.nil?
        wr = Ec::WeeklyRate.resolve(week_start)
        raise "无法获取 #{from_date} 的汇率" unless wr
        rate_cny_rub ||= wr.rate_cny_rub
        rate_byn_rub ||= wr.rate_byn_rub
        puts "[WbOrderDetail] 汇率自动获取：#{wr.week_start} CNY/RUB=#{rate_cny_rub} BYN/RUB=#{rate_byn_rub}"
      end

      scope = RawWb::SellerAccount.where(is_active: true)
      scope = scope.where(id: account_ids) if account_ids

      scope.each do |account|
        shop_name = account.name.to_s.gsub(/[:\[\]\/\\?*]/, '-').strip
        new(
          account_id:   account.id,
          from_date:,
          to_date:,
          rate_cny_rub:,
          rate_byn_rub:,
          week_label:,
          shop_name:
        ).call
      end

      puts "✓ WbOrderDetail #{from_date}~#{to_date} 所有店铺写入完成"
    end

    def initialize(account_id:, from_date:, to_date:, rate_cny_rub:, rate_byn_rub:, week_label:, shop_name:)
      super()
      @account_id   = account_id
      @from_date    = from_date
      @to_date      = to_date
      @rate_cny_rub = rate_cny_rub
      @rate_byn_rub = rate_byn_rub
      @week_label   = week_label
      @shop_name    = shop_name
    end

    def call
      svc = Ec::WbOrderDetailReport.new(
        account_id:   @account_id,
        from_date:    @from_date,
        to_date:      @to_date,
        rate_cny_rub: @rate_cny_rub,
        rate_byn_rub: @rate_byn_rub
      ).call

      @order_rows   = svc.order_rows
      @summary      = svc.summary
      @orphan_costs = svc.orphan_costs

      print_reconciliation

      tab = "WOD:#{@week_label}-#{@shop_name}"
      @spreadsheet_sheets = nil
      ensure_sheet_exists(tab)
      clear_sheet(range: "#{tab}!A1:AZ")

      data_rows       = @order_rows.map { |r| to_sheet_row(r) }
      total_row       = build_totals_row
      orphan_row      = build_orphan_row
      grand_total_row = build_grand_total_row(total_row, orphan_row)
      all_detail = [HDR_ZH, HDR_RU] + data_rows + [total_row, orphan_row, grand_total_row]

      write_to_sheet(range: "#{tab}!A1", values: all_detail)

      @spreadsheet_sheets = nil
      sid = sheet_id(tab)
      if sid
        alloc_row_idx = NUM_HDR + data_rows.size       # 0-based: 分摊合计
        orphan_idx    = alloc_row_idx + 1              # 0-based: 孤儿行
        grand_idx     = alloc_row_idx + 2              # 0-based: 总计
        reqs = []
        reqs << req_clear_format(sid, num_rows: grand_idx + 5, num_cols: HDR_ZH.size)
        reqs << req_header_rows(sid, num_rows: NUM_HDR, num_cols: HDR_ZH.size)
        reqs += req_data_rows(sid, start_row: NUM_HDR, end_row: NUM_HDR + data_rows.size, col_types: COL_TYPES)
        reqs += color_rows(sid, data_rows)
        reqs << req_freeze_rows(sid, count: NUM_HDR)
        reqs += req_col_widths(sid, widths: COL_WIDTHS)
        reqs << req_bold_row(sid, row: alloc_row_idx, num_cols: HDR_ZH.size)
        reqs << req_orphan_row_style(sid, row: orphan_idx, num_cols: HDR_ZH.size)
        reqs << req_grand_total_row_style(sid, row: grand_idx, num_cols: HDR_ZH.size)
        batch_update(reqs)
      end

      puts "✓ WbOrderDetail #{@week_label} [#{@shop_name}]: #{data_rows.size} 行写入 Google Sheet"
    end

    private

    def build_totals_row
      rs = @order_rows
      sales = rs.select { |r| r[:order_type] == '成交' }
      sum = ->(key) { rs.sum { |r| r[key].to_f }.round(2) }
      [
        '合计', nil, nil, nil,
        nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil,
        nil, nil,
        sales.sum { |r| r[:retail_amount].to_f }.round(2),
        nil,
        sum.(:for_pay),
        sum.(:acquiring), sales.sum { |r| r[:delivery].to_f }.round(2),
        sum.(:penalty), sum.(:rebill), sales.sum { |r| r[:logistics_reimb].to_f + r[:pickup].to_f }.round(2),
        sum.(:storage), sum.(:ad), sum.(:net),
        sum.(:tax_base), sum.(:goods_cost), sum.(:pre_tax),
        sum.(:vat_net), sum.(:after_tax), nil,
      ]
    end

    def build_orphan_row
      oc  = @orphan_costs
      row = Array.new(HDR_ZH.size, nil)
      row[0]  = '未归属合计明细'
      row[20] = oc[:delivery]
      row[21] = oc[:penalty]
      row[22] = oc[:rebill]
      row[23] = (oc[:logistics_reimb].to_f + oc[:pickup].to_f).round(2)
      row[26] = oc[:net]
      row[31] = oc[:after_tax]
      row
    end

    def build_grand_total_row(total_row, orphan_row)
      grand = total_row.dup
      grand[0] = '总计'
      [20, 21, 22, 23, 26, 31].each do |ci|
        grand[ci] = (total_row[ci].to_f + orphan_row[ci].to_f).round(2)
      end
      grand[32] = nil  # 利润率不汇总
      grand
    end

    def req_orphan_row_style(sid, row:, num_cols:)
      {
        repeat_cell: {
          range: grid(sid, row, row + 1, 0, num_cols),
          cell:  { user_entered_format: {
            background_color: { red: 1.0, green: 0.95, blue: 0.8 },
            text_format: { italic: true },
          }},
          fields: 'userEnteredFormat(backgroundColor,textFormat)',
        }
      }
    end

    def req_grand_total_row_style(sid, row:, num_cols:)
      {
        repeat_cell: {
          range: grid(sid, row, row + 1, 0, num_cols),
          cell:  { user_entered_format: {
            background_color: { red: 1.0, green: 0.753, blue: 0.0 },
            text_format: { bold: true },
          }},
          fields: 'userEnteredFormat(backgroundColor,textFormat)',
        }
      }
    end

    def req_bold_row(sid, row:, num_cols:)
      {
        repeat_cell: {
          range: grid(sid, row, row + 1, 0, num_cols),
          cell:  { user_entered_format: { text_format: { bold: true } } },
          fields: 'userEnteredFormat.textFormat.bold',
        }
      }
    end

    def to_sheet_row(r)
      [
        r[:nm_id], r[:vendor_code], r[:brand], r[:product_name],
        r[:shk_id], r[:order_type], r[:region], r[:report_type],
        r[:order_dt], r[:sale_dt], r[:country], r[:office_name],
        r[:ppvz_office], r[:delivery_method],
        r[:retail_price_with_disc], r[:spp_pct], r[:retail_amount],
        r[:commission_pct], r[:for_pay],
        r[:acquiring], r[:delivery], r[:penalty], r[:rebill], (r[:logistics_reimb].to_f + r[:pickup].to_f).round(2),
        r[:storage], r[:ad], r[:net],
        r[:tax_base], r[:goods_cost], r[:pre_tax], r[:vat_net],
        r[:after_tax], r[:margin_pct],
      ]
    end

    def color_rows(sid, data_rows)
      nc   = HDR_ZH.size
      reqs = []
      data_rows.each_with_index do |row, i|
        color = COLORS[row[5].to_s]   # column 5 = order_type
        next unless color
        reqs << {
          repeat_cell: {
            range: grid(sid, i + NUM_HDR, i + NUM_HDR + 1, 0, nc),
            cell:  { user_entered_format: { background_color: color } },
            fields: 'userEnteredFormat.backgroundColor',
          }
        }
      end
      reqs
    end

    def print_reconciliation
      s = @summary
      puts "\n#{'=' * 55}"
      puts "  WbOrderDetail 对账: #{@shop_name} #{s[:period]}"
      puts "  税制: #{s[:tax_regime]}  CNY/RUB=#{s[:rate_cny_rub]}  BYN/RUB=#{s[:rate_byn_rub]}"
      puts '=' * 55
      puts "  成交 #{s[:sales_count]}  退货 #{s[:return_count]}  共 #{s[:total_rows]} 行"
      puts "  白俄 #{s[:blr_count]}  出口 #{s[:export_count]}"
      puts "  结算额合计(forPay): #{s[:total_forpay]}"
      puts "  配送费:             #{s[:total_delivery]}"
      puts "  仓储费:             #{s[:total_storage]}"
      puts "  广告费:             #{s[:total_ad]}"
      puts "  账面小计:           #{s[:total_net]}"
      puts "  货物成本:           #{s[:total_goods]}"
      puts "  税后净利(分摊口径): #{s[:total_after_tax]}"
      puts "  税后净利(未归属):   #{s[:orphan_after_tax]}"
      puts "  税后净利(总计):     #{s[:grand_after_tax]}"
      puts "  税后净利(SKU口径):  #{s[:sku_total_after_tax]}"
      puts "  残差(总计-SKU口径): #{s[:residual]}"
    end
  end
end
