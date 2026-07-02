module GoogleSheets
  class WeeklySummaryDeepService < WeeklySummaryService
    HDR_ZH = [
      "SKU", "净销量", "销售额(CNY)", "广告费(CNY)", "货物成本(CNY)",
      "税前毛利(CNY)", "税/营业税(CNY)", "税后净利(CNY)", "利润率%",
      "平均每单利润", "广告占比%", "成本回报率%", "ROI(按180天备货)"
    ].freeze

    HDR_RU = [
      "Артикул", "Чистые продажи", "Выручка(CNY)", "Реклама(CNY)", "Себестоимость(CNY)",
      "До налогов(CNY)", "Налог(CNY)", "Чистая прибыль(CNY)", "Рентабельность%",
      "Ср. прибыль/заказ", "Доля рекламы%", "Окупаемость себестоимости%", "ROI(180 дней запаса)"
    ].freeze

    COL_TYPES = %i[text int num num num num num num pct num pct pct num].freeze
    COL_WIDTHS = [120, 80, 100, 100, 100, 100, 100, 100, 80, 100, 90, 100, 120].freeze

    def self.run(from_date:, to_date:, week_label:)
      new(from_date: from_date, to_date: to_date, week_label: week_label).call
    end

    def call
      rows, @unalloc_cny = collect_rows(@from_date, @to_date, @rate)

      prev_from = @from_date - 7
      prev_to   = @to_date - 7
      prev_rate = Ec::WeeklyRate.resolve(prev_from)
      prev_rows, _ = prev_rate ? collect_rows(prev_from, prev_to, prev_rate) : [[], nil]

      aggregated_rows = aggregate_rows_by_sku(rows)
      @current_skus = aggregated_rows.map { |row| row[:sku] }
      prev_map = aggregate_rows_by_sku(prev_rows).index_by { |row| row[:sku] }

      tab = "WSU-DEEP:#{@week_label}"
      @spreadsheet_sheets = nil
      ensure_sheet_exists(tab)
      clear_sheet(range: "#{tab}!A1:Z")
      sid_pre = sheet_id(tab)
      batch_update([req_clear_format(sid_pre)]) if sid_pre

      data_rows = build_data_rows(aggregated_rows, prev_map)
      total_row = build_total_row(aggregated_rows)
      all_rows = [HDR_ZH, HDR_RU] + data_rows + [total_row]
      write_to_sheet(range: "#{tab}!A1", values: all_rows)

      summary_offset = all_rows.size + 3
      write_to_sheet(range: "#{tab}!A#{summary_offset + 1}", values: build_summary(aggregated_rows))

      @spreadsheet_sheets = nil
      sid = sheet_id(tab)
      if sid
        nc = COL_TYPES.size
        data_end = 2 + data_rows.size
        reqs = []
        reqs << req_header_rows(sid, num_rows: 2, num_cols: nc)
        reqs += req_data_rows(sid, start_row: 2, end_row: data_end, col_types: COL_TYPES)
        reqs << req_special_row(sid, row_index: data_end, style: :total, num_cols: nc)
        reqs << req_freeze_rows(sid, count: 2)
        reqs += req_col_widths(sid, widths: COL_WIDTHS)
        batch_update(reqs)
      end
    end

    private

    def build_data_rows(rows, prev_map)
      rows.sort_by { |row| -row[:after_tax].to_d }.map do |row|
        roi_result = projected_roi_for(row)

        [
          row[:sku],
          row[:net_sales],
          row[:revenue],
          row[:ads],
          row[:goods_cost],
          row[:pre_tax],
          row[:tax],
          row[:after_tax],
          percentage(row[:after_tax], row[:revenue]),
          ratio(row[:after_tax], row[:net_sales]),
          percentage(row[:ads], row[:revenue]),
          percentage(row[:after_tax], row[:goods_cost]),
          roi_result[:roi] && (BigDecimal(roi_result[:roi].to_s) * 100).round(2)
        ]
      end
    end

    def build_total_row(rows)
      total_revenue = sum_decimal(rows, :revenue)
      total_after_tax = sum_decimal(rows, :after_tax)

      [
        "合计 / Итого",
        rows.sum { |row| row[:net_sales].to_i },
        total_revenue,
        sum_decimal(rows, :ads),
        sum_decimal(rows, :goods_cost),
        sum_decimal(rows, :pre_tax),
        sum_decimal(rows, :tax),
        total_after_tax,
        percentage(total_after_tax, total_revenue),
        nil, nil, nil, nil
      ]
    end

    def build_summary(rows)
      total_rev = sum_decimal(rows, :revenue)
      total_after_tax = sum_decimal(rows, :after_tax)
      margin = percentage(total_after_tax, total_rev)
      total_unalloc = @unalloc_cny.to_h.values.sum { |value| BigDecimal(value.to_s) }.round(2)

      [
        ["项目", "金额(CNY)"],
        ["数据周期", "#{@from_date} ~ #{@to_date}"],
        ["汇率 CNY/RUB", @rate.rate_cny_rub],
        ["汇率 BYN/RUB", @rate.rate_byn_rub],
        [],
        ["── 合计 ──", ""],
        ["总SKU数", rows.size],
        ["总净销量", rows.sum { |row| row[:net_sales].to_i }],
        ["总销售额", total_rev],
        ["总广告费", sum_decimal(rows, :ads)],
        ["总货物成本", sum_decimal(rows, :goods_cost)],
        ["总税前毛利", sum_decimal(rows, :pre_tax)],
        ["总税后净利", total_after_tax],
        ["综合利润率", margin ? "#{margin}%" : "N/A"],
        [],
        ["── 未分摊费用（参考，负=成本）──", ""],
        ["未分摊合计", total_unalloc],
        ["税后净利（不含未分摊）", total_after_tax],
        ["税后净利（含未分摊）", (total_after_tax + total_unalloc).round(2)]
      ]
    end

    def projected_roi_for(row)
      sku = sku_map[row[:sku]]
      cost = sku&.cost

      Ec::ProjectedStockRoiCalculator.call(
        net_sales_quantity: row[:net_sales],
        operating_profit_cny: row[:after_tax],
        days_count: days_count,
        unit_goods_cost_cny: cost&.goods_cost_cny,
        unit_volume_l: cost&.pkg_volume_l
      )
    end

    def sku_map
      @sku_map ||= Ec::Sku.includes(:cost).where(sku_code: current_skus).index_by(&:sku_code)
    end

    def current_skus
      @current_skus ||= []
    end

    def days_count
      (@to_date - @from_date).to_i + 1
    end

    def ratio(numerator, denominator)
      denominator_value = BigDecimal(denominator.to_s)
      return nil if denominator_value <= 0

      BigDecimal(numerator.to_s) / denominator_value
    end

    def percentage(numerator, denominator)
      denominator_value = BigDecimal(denominator.to_s)
      return nil if denominator_value <= 0

      ((BigDecimal(numerator.to_s) / denominator_value) * 100).round(2)
    end

    def sum_decimal(rows, key)
      rows.sum { |row| BigDecimal(row[key].to_s) }.round(2)
    end

    def aggregate_rows_by_sku(rows)
      rows.group_by { |row| row[:sku].to_s.strip.upcase }
        .filter_map do |sku, sku_rows|
          next if sku.blank?

          {
            sku: sku,
            net_sales: sku_rows.sum { |row| row[:net_sales].to_i },
            revenue: sum_decimal(sku_rows, :revenue),
            ads: sum_decimal(sku_rows, :ads),
            goods_cost: sum_decimal(sku_rows, :goods_cost),
            pre_tax: sum_decimal(sku_rows, :pre_tax),
            tax: sum_decimal(sku_rows, :tax),
            after_tax: sum_decimal(sku_rows, :after_tax)
          }
        end
    end
  end
end
