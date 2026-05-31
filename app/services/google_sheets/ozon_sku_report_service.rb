module GoogleSheets
  # 将 Ec::OzonProfitAttribution 的 SKU 利润归集结果写入 Google Sheet 指定 Tab。
  #
  # 用法：
  #   GoogleSheets::OzonSkuReportService.new(
  #     account_id:   1,
  #     from_date:    '2026-05-04',
  #     to_date:      '2026-05-10',
  #     rate_cny_rub: 11.2585,
  #     tab_name:     'SKU-Report-W19'
  #   ).call
  class OzonSkuReportService < BaseService
    HEADER_ZH = [
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

    HEADER_RU = [
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

    # 列类型（28列）：text/number/integer/percent
    COL_TYPES = [
      :text,    # 0  SKU
      :text,    # 1  sku_code
      :text,    # 2  name
      :number,  # 3  sales_revenue
      :number,  # 4  commission
      :number,  # 5  delivery_charge
      :number,  # 6  payment_fee
      :number,  # 7  dispatch_fee
      :number,  # 8  packing_fee
      :number,  # 9  return_delivery
      :number,  # 10 storage_fee
      :number,  # 11 defect_fee
      :number,  # 12 crossdock_fee
      :integer, # 13 order_count
      :integer, # 14 net_sales_count
      :integer, # 15 return_count
      :number,  # 16 total_ad_cost
      :percent, # 17 ad_pct %
      :number,  # 18 book_profit
      :number,  # 19 book_profit_after_ad
      :integer, # 20 blr_count
      :integer, # 21 export_count
      :number,  # 22 goods_cost
      :number,  # 23 blr_tax
      :number,  # 24 export_refund
      :number,  # 25 pre_tax_profit
      :number,  # 26 after_tax_profit
      :percent, # 27 margin_pct %
    ].freeze

    COL_WIDTHS = [
      110, 110, 220,           # SKU / 品号 / 名称
      90, 90, 90, 90, 80, 80,  # 收入 + 各费用
      90, 90, 90, 90,          # 退货/仓储/残次/越库
      75, 75, 75,              # 计数
      90, 70,                  # 广告费 + 占比
      100, 100,                # 账面利润 / 扣广后
      65, 65,                  # 白俄 / 出口 计数
      90, 90, 90,              # 货物成本 / 白俄税 / 出口退税
      100, 100, 70,            # 税前 / 税后 / 利润率
    ].freeze

    def initialize(account_id:, from_date:, to_date:, rate_cny_rub:, tab_name:)
      super()
      @account_id   = account_id
      @from_date    = from_date
      @to_date      = to_date
      @rate_cny_rub = rate_cny_rub
      @tab_name     = tab_name
    end

    def call
      svc = Ec::OzonProfitAttribution.new(
        account_id:   @account_id,
        from_date:    @from_date,
        to_date:      @to_date,
        rate_cny_rub: @rate_cny_rub
      ).call

      name_map  = Ec::Sku.pluck(:sku_code, :product_name_ru)
                         .each_with_object({}) { |(code, name), h| h[code] = name }
      data_rows = build_rows(svc.results, name_map)
      ua_rows   = unallocated_rows(svc.unallocated)

      num_hdr  = 2
      num_data = data_rows.size
      all_rows = [HEADER_ZH, HEADER_RU] + data_rows + ua_rows

      @spreadsheet_sheets = nil  # 强制刷新
      ensure_sheet_exists(@tab_name)
      clear_sheet(range: "#{@tab_name}!A1:AZ")
      write_to_sheet(range: "#{@tab_name}!A1", values: all_rows)

      apply_styles(num_hdr:, num_data:, ua_rows: ua_rows.size)
      puts "✓ #{@tab_name}: #{svc.results.size} SKU 行已写入 Google Sheet（含样式）"
    end

    private

    def apply_styles(num_hdr:, num_data:, ua_rows:)
      sid      = sheet_id(@tab_name)
      return unless sid
      num_cols = COL_TYPES.size
      data_end = num_hdr + num_data     # 0-indexed exclusive end of data rows

      reqs = []

      # 表头两行：蓝底白字
      reqs << req_header_rows(sid, num_rows: num_hdr, num_cols: num_cols)

      # 数据行：边框 + 数字格式
      reqs += req_data_rows(sid, start_row: num_hdr, end_row: data_end, col_types: COL_TYPES)

      # 未分摊区域
      if ua_rows > 0
        ua_header_row = data_end           # "未分摊费用" 标题行
        ua_item_end   = data_end + ua_rows # 明细 + 合计行

        reqs << req_special_row(sid, row_index: ua_header_row, style: :section, num_cols: num_cols)

        # 合计行（最后一行）用金色
        reqs << req_special_row(sid, row_index: ua_item_end - 1, style: :total, num_cols: num_cols)

        # 明细行加边框
        if ua_rows > 2
          reqs += req_data_rows(sid,
            start_row: ua_header_row + 1,
            end_row:   ua_item_end - 1,
            col_types: Array.new(num_cols, :text)
          )
        end
      end

      # 冻结表头 + 列宽
      reqs << req_freeze_rows(sid, count: num_hdr)
      reqs += req_col_widths(sid, widths: COL_WIDTHS)

      batch_update(reqs)
    end

    def build_rows(results, name_map)
      results.map do |r|
        sales     = r[:sales_revenue].to_f
        total_ad  = r[:total_ad_cost].to_f
        after_tax = r[:after_tax_profit]

        ad_pct     = sales != 0 ? (total_ad.abs / sales * 100).round(1) : nil
        margin_pct = (sales != 0 && after_tax) ? (after_tax / sales * 100).round(1) : nil

        [
          r[:ozon_sku_id], r[:sku_code], name_map[r[:sku_code]],
          r[:sales_revenue], r[:commission], r[:delivery_charge],
          r[:payment_fee], r[:dispatch_fee], r[:packing_fee],
          r[:return_delivery], r[:storage_fee], r[:defect_fee], r[:crossdock_fee],
          r[:order_count], r[:net_sales_count], r[:return_count],
          total_ad.round(2), ad_pct,
          r[:book_profit], r[:book_profit_after_ad],
          r[:blr_count], r[:export_count],
          r[:goods_cost], r[:blr_tax], r[:export_refund],
          r[:pre_tax_profit], after_tax, margin_pct,
        ]
      end
    end

    def unallocated_rows(unalloc)
      rows = unalloc[:rows] || []
      return [] if rows.empty?

      label_map = {
        96 => 'Ускоренная проверка (AcceleratedReviewCollection)',
        94 => 'Штраф за задержку отгрузки (DefectFine)',
        1  => 'Эквайринг: не привязан к заказу',
        52 => 'Подписка Premium (PremiumSubscription)',
      }

      grouped = rows.reject { |r| [41, 54].include?(r[:type_id].to_i) }
                    .group_by { |r| r[:type_id].to_i }

      result = [['未分摊费用 / Нераспределённые расходы']]
      grouped.each do |tid, group|
        label  = label_map[tid] || "type_id=#{tid}"
        amount = group.sum { |r| r[:amount].to_f }.round(2)
        result << [nil, label, nil, amount]
      end
      result << [nil, '合计 / Итого', nil, unalloc[:total].to_f.round(2)]
      result
    end
  end
end
