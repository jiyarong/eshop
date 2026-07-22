module GoogleSheets
  # WB 周报写入 Google Sheets，每个店铺每周写入单个 Tab（带 WR: 前缀）：
  #   WR:{week_label}-{shop_name}
  #
  # Tab 内容从上到下：SKU明细 → 汇总（两节间隔 3 行）
  #
  # 批量入口（推荐）:
  #   GoogleSheets::WbWeeklyReportService.run_all(
  #     from_date:    '2026-05-08',
  #     to_date:      '2026-05-14',
  #     rate_cny_rub: 11.26,
  #     rate_byn_rub: 26.41
  #   )
  class WbWeeklyReportService < BaseService
    GAP_ROWS = 3

    def self.run_all(from_date:, to_date:, rate_cny_rub:, rate_byn_rub:, account_ids: nil)
      week_label = "W#{Date.parse(to_date.to_s).cweek}"
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

      puts "✓ WbWeeklyReport #{week_label} (#{from_date}~#{to_date}) 所有店铺写入完成"
    end

    def initialize(account_id:, from_date:, to_date:, rate_cny_rub:, rate_byn_rub:,
                   week_label:, shop_name:)
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
      ensure_ad_fees_synced!
      ensure_storage_synced!

      report = WeeklyProfitReports::ReportQueryRunner.run(
        params: {
          report_type: "wr",
          store_ref: "wb:#{@account_id}",
          from_date: @from_date,
          to_date: @to_date
        },
        today: Date.current
      )

      @results     = report[:rows]
      @unallocated = report.dig(:extras, :unallocated) || {}
      @summary     = report[:summary]
      @name_map    = Ec::Sku.pluck(:sku_code, :product_name_ru)
                            .each_with_object({}) { |(c, n), h| h[c] = n }

      tab = "WR:#{@week_label}-#{@shop_name}"
      @spreadsheet_sheets = nil
      ensure_sheet_exists(tab)
      clear_sheet(range: "#{tab}!A1:Z")
      sid_pre = sheet_id(tab)
      batch_update([req_clear_format(sid_pre)]) if sid_pre

      # ── Section 1: SKU ───────────────────────────────────────────────────
      sku_data_rows = @results
        .select { |r| r[:sales_qty] > 0 || r[:storage] != 0 || r[:ad] != 0 || r[:delivery] != 0 }
        .map { |r| sku_row(r) }
      sku_total_row = build_sku_total_row
      sku_all_rows  = [SKU_HDR_ZH, SKU_HDR_RU] + sku_data_rows + [sku_total_row]
      sku_height    = sku_all_rows.size

      # ── Section 2: 汇总 ──────────────────────────────────────────────────
      rows_data      = build_summary_rows
      summary_offset = sku_height + GAP_ROWS
      summary_rows   = [['项目 / Статья', "金额 BYN (#{@from_date}~#{@to_date})"]] +
                       rows_data.map { |rd| [rd[:label], rd[:value]] }

      # ── Write all sections ───────────────────────────────────────────────
      write_to_sheet(range: "#{tab}!A1",                     values: sku_all_rows)
      write_to_sheet(range: "#{tab}!A#{summary_offset + 1}", values: summary_rows)

      # ── Apply styles ─────────────────────────────────────────────────────
      @spreadsheet_sheets = nil
      sid = sheet_id(tab)
      return unless sid

      nc       = SKU_COL_TYPES.size
      data_end = 2 + sku_data_rows.size

      reqs = []
      reqs << req_header_rows(sid, num_rows: 2, num_cols: nc)
      reqs += req_data_rows(sid, start_row: 2, end_row: data_end, col_types: SKU_COL_TYPES)
      reqs << req_special_row(sid, row_index: data_end, style: :total, num_cols: nc)
      reqs += summary_style_reqs(sid, offset: summary_offset, rows_data:)
      reqs << req_freeze_rows(sid, count: 2)
      reqs += req_col_widths(sid, widths: SKU_COL_WIDTHS)
      batch_update(reqs)

      puts "✓ WB #{@week_label} [#{@shop_name}] (#{@summary[:tax_regime].upcase}) 周报写入完成"
    end

    private

    def ensure_storage_synced!
      from_dt = @from_date.to_date
      to_dt   = @to_date.to_date

      max_date = RawWb::PaidStorage
        .where(account_id: @account_id)
        .where('calc_date BETWEEN ? AND ?', from_dt, to_dt)
        .maximum(:calc_date)

      return if max_date && max_date >= to_dt

      days_back = (Date.current - from_dt).to_i + 1
      account   = RawWb::SellerAccount.find(@account_id)
      RawWb::WeeklySync.new(account, days: days_back).run(sync_keys: [:sync_paid_storage])
      puts "  → 按需同步仓储费 #{from_dt}~#{to_dt} [#{@shop_name}]"
    end

    def ensure_ad_fees_synced!
      from_dt = @from_date.to_date
      to_dt   = @to_date.to_date

      exists = RawWb::AdSettledFee
        .where(account_id: @account_id)
        .where('period_from <= ? AND period_to >= ?', from_dt, to_dt)
        .exists?

      unless exists
        count = RawWb::WeeklySync.sync_ad_fees_for_period(
          account_id: @account_id,
          from_date:  from_dt,
          to_date:    to_dt
        )
        puts "  → 按需同步广告费 #{from_dt}~#{to_dt} [#{@shop_name}]: #{count} 条"
      end

      # 同步 ad_campaigns，确保 ad_settled_fees 中所有 advert_id 都有对应记录
      # 有新活动未被 WeeklySync 覆盖时（活动创建晚于上次 sync），此处补拉
      account = RawWb::SellerAccount.find(@account_id)
      RawWb::WeeklySync.new(account, days: 1).run(sync_keys: [:sync_ad_campaigns])
    end

    # ══════════════════════════════════════════════════════════
    # Section 1: SKU 明细
    # ══════════════════════════════════════════════════════════

    SKU_HDR_ZH = [
      'nmId', '品号', '商品名称', '区域',
      '下单数', '退货', '净销量',
      '标价收入',
      '结算额', '收单费', '配送费', '补收运费', '自提点费', '罚款',
      '仓储费', '广告费',
      '账面小计',
      '税基(折后价)', '进口VAT/件', '货物成本', '税前利润', '税额', '税后净利',
    ].freeze

    SKU_HDR_RU = [
      'nmId', 'Артикул', 'Название', 'Регион',
      'Заказано', 'Возвраты', 'Чистые продажи',
      'Выручка (справ.)',
      'forPay', 'Эквайринг', 'Доставка', 'Доп.доставка', 'Выдача ПВЗ', 'Штраф',
      'Хранение', 'Реклама',
      'Итого',
      'База (цена)', 'Ввозной НДС/шт', 'Себестоимость', 'До налогов', 'Налог', 'Чистая прибыль',
    ].freeze

    SKU_COL_TYPES = [
      :text, :text, :text, :text,
      :integer, :integer, :integer,
      :number,
      :number, :number, :number, :number, :number, :number,
      :number, :number,
      :number,
      :number, :number, :number, :number, :number, :number,
    ].freeze

    SKU_COL_WIDTHS = [
      180, 200, 200, 55,
      55, 55, 65,
      90,
      80, 75, 75, 80, 75, 70,
      75, 75,
      85,
      90, 80, 90, 90, 80, 100,
    ].freeze

    def sku_row(r)
      name = @name_map[r[:vendor_code]] || @name_map[r[:vendor_code]&.upcase]
      [
        r[:nm_id], r[:vendor_code], name, r[:region],
        r[:sales_qty], r[:return_qty], r[:net_qty],
        r[:retail_amount],
        r[:settlement], r[:acquiring], r[:delivery],
        r[:reimb], (r[:logistics_reimb].to_f + r[:pickup].to_f).round(2), r[:penalty],
        r[:storage], r[:ad],
        r[:net],
        r[:tax_base], r[:import_vat], r[:goods_cost],
        r[:pre_tax], r[:tax], r[:after_tax],
      ]
    end

    def build_sku_total_row
      rs = @results.select { |r| r[:sales_qty] > 0 || r[:storage] != 0 || r[:ad] != 0 || r[:delivery] != 0 }
      [
        nil, '合计 / Итого', nil, nil,
        rs.sum { |r| r[:sales_qty] }, rs.sum { |r| r[:return_qty] }, rs.sum { |r| r[:net_qty] },
        rs.sum { |r| r[:retail_amount] }.round(2),
        rs.sum { |r| r[:settlement] }.round(2),
        rs.sum { |r| r[:acquiring] }.round(2),
        rs.sum { |r| r[:delivery] }.round(2),
        rs.sum { |r| r[:reimb] }.round(2),
        rs.sum { |r| r[:logistics_reimb].to_f + r[:pickup].to_f }.round(2),
        rs.sum { |r| r[:penalty] }.round(2),
        rs.sum { |r| r[:storage] }.round(2),
        rs.sum { |r| r[:ad] }.round(2),
        rs.sum { |r| r[:net] }.round(2),
        rs.sum { |r| r[:tax_base] }.round(2),
        nil,
        rs.sum { |r| r[:goods_cost] }.round(2),
        rs.sum { |r| r[:pre_tax] }.round(2),
        rs.sum { |r| r[:tax] }.round(2),
        rs.sum { |r| r[:after_tax] }.round(2),
      ]
    end

    # ══════════════════════════════════════════════════════════
    # Section 2: 汇总
    # ══════════════════════════════════════════════════════════

    def build_summary_rows
      rs    = @results
      ua    = @unallocated
      rsum  = ->(key) { rs.sum { |r| r[key].to_f }.round(2) }
      regime = @summary[:tax_regime].upcase

      total_sales  = rsum.(:sales_qty)
      total_ret    = rsum.(:return_qty)
      total_settl  = rsum.(:settlement)
      total_acq    = rsum.(:acquiring)
      total_deliv  = rsum.(:delivery)
      total_reimb  = rsum.(:reimb)
      total_pickup = rs.sum { |r| r[:logistics_reimb].to_f + r[:pickup].to_f }.round(2)
      total_pen    = rsum.(:penalty)
      total_stor   = rsum.(:storage)
      total_ad     = rsum.(:ad)
      total_net    = rsum.(:net)
      total_goods  = rsum.(:goods_cost)
      total_pre    = rsum.(:pre_tax)
      total_tax    = rsum.(:tax)
      total_after  = rsum.(:after_tax)
      ua_total     = ua.values.sum.round(2)

      net_after_ua = (total_after - ua_total).round(2)
      margin_pct   = total_settl != 0 ? (net_after_ua / total_settl * 100).round(2) : nil

      [
        { label: '数据周期 / Период',            value: "#{@from_date} ~ #{@to_date}", type: :normal },
        { label: '汇率 CNY/RUB',                  value: @rate_cny_rub,                 type: :normal },
        { label: '汇率 BYN/RUB',                  value: @rate_byn_rub,                 type: :normal },
        { label: "税制 / Налоговый режим",        value: regime,                         type: :normal },
        { label: '销售件数 / Продажи',            value: total_sales,                    type: :normal },
        { label: '退货件数 / Возвраты',           value: total_ret,                      type: :normal },
        { label: '── 收入 ──',                    value: nil,                            type: :section },
        { label: '结算额(forPay) / Расчёт',       value: total_settl,                    type: :normal },
        { label: '── 平台费用 ──',                value: nil,                            type: :section },
        { label: '收单费 / Эквайринг',            value: -total_acq,                     type: :normal },
        { label: '配送费 / Доставка',             value: -total_deliv,                   type: :normal },
        { label: '补收运费 / Доп.доставка',       value: -total_reimb,                   type: :normal },
        { label: '自提点费 / Выдача ПВЗ',         value: -total_pickup,                  type: :normal },
        { label: '罚款 / Штраф',                  value: -total_pen,                     type: :normal },
        { label: '仓储费 / Хранение',             value: -total_stor,                    type: :normal },
        { label: '广告费 / Реклама',              value: -total_ad,                      type: :normal },
        { label: '账面小计 / Итого',              value: total_net,                       type: :subtotal },
        { label: '── 货物成本 ──',                value: nil,                            type: :section },
        { label: '货物成本 / Себестоимость',       value: -total_goods,                   type: :normal },
        { label: '税前利润 / До налогов',          value: total_pre,                      type: :subtotal },
        { label: '── 税务 ──',                    value: nil,                            type: :section },
        { label: "税额 (#{regime}) / Налог",      value: -total_tax,                     type: :normal },
        { label: '── 未归属费用 ──',              value: nil,                            type: :section },
        *ua.map { |op, amt| { label: op, value: -amt.round(2), type: :normal } },
        { label: '未归属合计',                     value: -ua_total,                      type: :normal },
        { label: '── 利润 ──',                    value: nil,                             type: :section },
        { label: '税后净利(SKU) / Чистая прибыль (SKU)',    value: total_after,           type: :subtotal },
        { label: '扣除未分摊后净利 / Чистая прибыль (с нераспред.)', value: net_after_ua, type: :total },
        { label: '税后利润率 / Рентабельность',    value: margin_pct,                     type: :normal },
      ]
    end

    def summary_style_reqs(sid, offset:, rows_data:)
      reqs = []
      reqs << req_header_rows(sid, start_row: offset, num_rows: 1, num_cols: 2)

      rows_data.each_with_index do |rd, i|
        row_idx = offset + 1 + i
        case rd[:type]
        when :section  then reqs << req_special_row(sid, row_index: row_idx, style: :sub,     num_cols: 2)
        when :subtotal then reqs << req_special_row(sid, row_index: row_idx, style: :section, num_cols: 2)
        when :total    then reqs << req_special_row(sid, row_index: row_idx, style: :total,   num_cols: 2)
        end

        next unless rd[:value].is_a?(Numeric)
        fmt = rd[:label].include?('率') ? FMT_PERCENT : FMT_NUMBER
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

      reqs += req_data_rows(sid, start_row: offset + 1, end_row: offset + 1 + rows_data.size,
                            col_types: [:text, :text])
      reqs
    end
  end
end
