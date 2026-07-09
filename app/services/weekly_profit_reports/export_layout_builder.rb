module WeeklyProfitReports
  class ExportLayoutBuilder
    GAP_ROWS = 3

    def self.build(report:)
      new(report:).build
    end

    def initialize(report:)
      @report = report.deep_symbolize_keys
    end

    def build
      case @report[:report_type]
      when "wr"
        build_wr_layout
      when "wsu"
        build_wsu_layout
      when "wsu_deep"
        build_wsu_deep_layout
      else
        raise ArgumentError, "unsupported_report_type"
      end
    end

    private

    def build_wsu_layout
      helper = GoogleSheets::WeeklySummaryService.allocate
      rows = @report[:rows] || []
      comparisons = @report.dig(:comparison, :rows) || {}
      summary = @report[:summary] || {}
      data_rows = helper.send(:build_query_data_rows, rows, comparisons)
      total_row = helper.send(:build_query_total_row, rows)
      summary_rows = helper.send(:build_query_summary_rows, summary)

      {
        sheet_name: "WSU:#{week_label}",
        column_widths: GoogleSheets::WeeklySummaryService::COL_WIDTHS,
        sections: [
          {
            rows: [GoogleSheets::WeeklySummaryService::HDR_ZH, GoogleSheets::WeeklySummaryService::HDR_RU] + data_rows + [total_row],
            row_types: [:header, :header] + Array.new(data_rows.size, :data) + [:total]
          },
          {
            rows: summary_rows,
            row_types: summary_row_types(summary_rows)
          }
        ]
      }
    end

    def build_wsu_deep_layout
      helper = GoogleSheets::WeeklySummaryDeepService.allocate
      rows = @report[:rows] || []
      summary = @report[:summary] || {}
      data_rows = helper.send(:build_query_data_rows, rows)
      total_row = helper.send(:build_query_total_row, rows)
      summary_rows = helper.send(:build_query_summary_rows, summary)

      {
        sheet_name: "WSU-DEEP:#{week_label}",
        column_widths: GoogleSheets::WeeklySummaryDeepService::COL_WIDTHS,
        sections: [
          {
            rows: [GoogleSheets::WeeklySummaryDeepService::HDR_ZH, GoogleSheets::WeeklySummaryDeepService::HDR_RU] + data_rows + [total_row],
            row_types: [:header, :header] + Array.new(data_rows.size, :data) + [:total]
          },
          {
            rows: summary_rows,
            row_types: summary_row_types(summary_rows)
          }
        ]
      }
    end

    def build_wr_layout
      case @report.dig(:meta, :platform)
      when "wb"
        build_wb_wr_layout
      when "ozon"
        build_ozon_wr_layout
      else
        raise ArgumentError, "unsupported_wr_platform"
      end
    end

    def build_wb_wr_layout
      helper = GoogleSheets::WbWeeklyReportService.allocate
      helper.instance_variable_set(:@results, @report[:rows] || [])
      helper.instance_variable_set(:@unallocated, wb_unallocated_hash)
      helper.instance_variable_set(:@summary, @report[:summary] || {})
      helper.instance_variable_set(:@from_date, report_from_date)
      helper.instance_variable_set(:@to_date, report_to_date)
      helper.instance_variable_set(:@rate_cny_rub, @report.dig(:meta, :rates, :rate_cny_rub))
      helper.instance_variable_set(:@rate_byn_rub, @report.dig(:meta, :rates, :rate_byn_rub))
      helper.instance_variable_set(:@name_map, sku_name_map)

      sku_rows = (@report[:rows] || [])
        .select { |row| row[:sales_qty].to_i > 0 || row[:storage].to_f != 0 || row[:ad].to_f != 0 || row[:delivery].to_f != 0 }
        .map { |row| helper.send(:sku_row, row) }
      total_row = helper.send(:build_sku_total_row)
      summary_defs = helper.send(:build_summary_rows)

      {
        sheet_name: "WR:#{week_label}-#{sanitized_shop_name}",
        column_widths: GoogleSheets::WbWeeklyReportService::SKU_COL_WIDTHS,
        sections: [
          {
            rows: [GoogleSheets::WbWeeklyReportService::SKU_HDR_ZH, GoogleSheets::WbWeeklyReportService::SKU_HDR_RU] + sku_rows + [total_row],
            row_types: [:header, :header] + Array.new(sku_rows.size, :data) + [:total]
          },
          {
            rows: [["项目 / Статья", "金额 BYN (#{report_from_date}~#{report_to_date})"]] + summary_defs.map { |row| [row[:label], row[:value]] },
            row_types: [:summary_header] + summary_defs.map { |row| summary_type_for(row[:type]) }
          }
        ]
      }
    end

    def build_ozon_wr_layout
      helper = GoogleSheets::OzonWeeklyReportService.allocate
      helper.instance_variable_set(:@results, @report[:rows] || [])
      helper.instance_variable_set(:@unallocated, @report.dig(:extras, :unallocated) || {})
      helper.instance_variable_set(:@from_date, report_from_date)
      helper.instance_variable_set(:@to_date, report_to_date)
      helper.instance_variable_set(:@rate_cny_rub, @report.dig(:meta, :rates, :rate_cny_rub))
      helper.instance_variable_set(:@name_map, sku_name_map)

      sku_rows = (@report[:rows] || []).map { |row| helper.send(:sku_row, row) }
      sku_total = helper.send(:sku_total_row, sku_rows)
      unallocated_rows = helper.send(:unallocated_rows, @report.dig(:extras, :unallocated) || {})
      summary_defs = helper.send(:build_report_rows)
      ad_rows = build_ozon_ad_rows
      ad_total = build_ozon_ad_total_row(ad_rows)
      destination_rows = build_ozon_destination_rows
      destination_total = build_ozon_destination_total_row(destination_rows)

      {
        sheet_name: "WR:#{week_label}-#{sanitized_shop_name}",
        column_widths: GoogleSheets::OzonWeeklyReportService::SKU_COL_WIDTHS,
        sections: [
          {
            rows: [GoogleSheets::OzonWeeklyReportService::SKU_HDR_ZH, GoogleSheets::OzonWeeklyReportService::SKU_HDR_RU] + sku_rows + [sku_total] + unallocated_rows,
            row_types: ozon_sku_row_types(sku_rows.size, unallocated_rows.size)
          },
          {
            rows: [["项目 / Статья", "金额 / Сумма (#{report_from_date}~#{report_to_date})"]] + summary_defs.map { |row| [row[:label], row[:value]] },
            row_types: [:summary_header] + summary_defs.map { |row| summary_type_for(row[:type]) }
          },
          {
            rows: [GoogleSheets::OzonWeeklyReportService::AD_HDR_ZH, GoogleSheets::OzonWeeklyReportService::AD_HDR_RU] + ad_rows + [ad_total],
            row_types: [:header, :header] + Array.new(ad_rows.size, :data) + [:total]
          },
          {
            rows: [GoogleSheets::OzonWeeklyReportService::DST_HDR_ZH, GoogleSheets::OzonWeeklyReportService::DST_HDR_RU] + destination_rows + [destination_total],
            row_types: [:header, :header] + Array.new(destination_rows.size, :data) + [:total]
          }
        ]
      }
    end

    def build_ozon_ad_rows
      (@report[:rows] || [])
        .select { |row| row[:ppc_cost].to_f != 0 || row[:promotion_cost].to_f != 0 }
        .sort_by { |row| row[:total_ad_cost].to_f }
        .map do |row|
          promotion = row[:promotion_cost].to_f.abs.round(2)
          ppc = row[:ppc_cost].to_f.abs.round(2)
          [row[:ozon_sku_id], row[:sku_code], promotion, ppc, (promotion + ppc).round(2)]
        end
    end

    def build_ozon_ad_total_row(rows)
      total_promotion = rows.sum { |row| row[2].to_f }.round(2)
      total_ppc = rows.sum { |row| row[3].to_f }.round(2)
      [nil, "合计 / Итого", total_promotion, total_ppc, (total_promotion + total_ppc).round(2)]
    end

    def build_ozon_destination_rows
      (@report[:rows] || [])
        .select { |row| row[:blr_count].to_i != 0 || row[:export_count].to_i != 0 }
        .sort_by { |row| -(row[:blr_count].to_i + row[:export_count].to_i) }
        .map do |row|
          [row[:ozon_sku_id], row[:sku_code], sku_name_map[row[:sku_code]], row[:blr_count], row[:export_count]]
        end
    end

    def build_ozon_destination_total_row(rows)
      [nil, "合计 / Итого", nil, rows.sum { |row| row[3].to_i }, rows.sum { |row| row[4].to_i }]
    end

    def ozon_sku_row_types(sku_count, unallocated_count)
      types = [:header, :header] + Array.new(sku_count, :data) + [:total]
      return types if unallocated_count.zero?

      types << :section
      inner_count = [unallocated_count - 2, 0].max
      types.concat(Array.new(inner_count, :summary))
      types << :total if unallocated_count > 1
      types
    end

    def summary_row_types(rows)
      rows.each_with_index.map do |row, index|
        if index.zero?
          :summary_header
        elsif row.all?(&:blank?)
          :blank
        elsif row.first.to_s.start_with?("──")
          :section
        else
          :summary
        end
      end
    end

    def summary_type_for(type)
      case type
      when :section then :section
      when :subtotal then :subtotal
      when :total then :total
      else :summary
      end
    end

    def week_label
      "W#{report_to_date.cweek}"
    end

    def report_from_date
      Date.iso8601(@report.dig(:period, :from_date).to_s)
    end

    def report_to_date
      Date.iso8601(@report.dig(:period, :to_date).to_s)
    end

    def sanitized_shop_name
      @report.dig(:meta, :account, :name).to_s.gsub(/[:\[\]\/\\?*]/, "-").strip
    end

    def sku_name_map
      @sku_name_map ||= Ec::Sku.pluck(:sku_code, :product_name_ru).each_with_object({}) do |(sku_code, name), map|
        map[sku_code] = name
      end
    end

    def wb_unallocated_hash
      (@report.dig(:extras, :unallocated) || {}).each_with_object({}) do |(name, amount), hash|
        hash[name.to_s] = amount
      end
    end
  end
end
