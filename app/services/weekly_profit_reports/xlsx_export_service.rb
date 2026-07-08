require "axlsx"

module WeeklyProfitReports
  class XlsxExportService
    MIME_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

    def self.call(report:)
      new(report:).call
    end

    def initialize(report:)
      @report = report.deep_symbolize_keys
      @layout = ExportLayoutBuilder.build(report: @report)
    end

    def call
      package = Axlsx::Package.new
      workbook = package.workbook
      styles = build_styles(workbook.styles)

      workbook.add_worksheet(name: excel_sheet_name) do |sheet|
        sheet.column_widths(*excel_column_widths) if @layout[:column_widths].present?

        @layout[:sections].each_with_index do |section, section_index|
          section[:rows].each_with_index do |row, row_index|
            normalized_row = row.map { |value| normalize_cell(value) }
            row_type = section[:row_types][row_index]
            style = row_style(styles, row_type, normalized_row.size)
            sheet.add_row(normalized_row, style: style)
          end

          next if section_index == @layout[:sections].size - 1

          ExportLayoutBuilder::GAP_ROWS.times { sheet.add_row([]) }
        end
      end

      {
        filename: export_filename,
        data: package.to_stream.read
      }
    end

    private

    def build_styles(styles)
      {
        header: styles.add_style(
          bg_color: "366092",
          fg_color: "FFFFFF",
          b: true,
          alignment: { horizontal: :center, vertical: :center, wrap_text: true }
        ),
        total: styles.add_style(bg_color: "FFC000", b: true),
        section: styles.add_style(bg_color: "D9E1F2", b: true),
        subtotal: styles.add_style(bg_color: "FFD966", b: true),
        summary_header: styles.add_style(
          bg_color: "366092",
          fg_color: "FFFFFF",
          b: true,
          alignment: { horizontal: :center, vertical: :center, wrap_text: true }
        ),
        summary: styles.add_style(alignment: { vertical: :center }),
        blank: styles.add_style
      }
    end

    def row_style(styles, row_type, size)
      style = case row_type
      when :header then styles[:header]
      when :summary_header then styles[:summary_header]
      when :total then styles[:total]
      when :section then styles[:section]
      when :subtotal then styles[:subtotal]
      when :summary then styles[:summary]
      else styles[:blank]
      end

      Array.new(size, style)
    end

    def normalize_cell(value)
      return value.to_f if value.is_a?(BigDecimal)

      value
    end

    def excel_column_widths
      Array(@layout[:column_widths]).map { |width| pixel_width_to_excel_width(width) }
    end

    def pixel_width_to_excel_width(width)
      return width unless width.is_a?(Numeric)

      converted = ((width.to_f - 5.0) / 7.0)
      [[converted.round(2), 2.5].max, 60.0].min
    end

    def excel_sheet_name
      @excel_sheet_name ||= @layout[:sheet_name].gsub(/[:\\\/\?\*\[\]]/, "-")[0, 31]
    end

    def export_filename
      [
        "weekly-profit",
        @report[:report_type].tr("_", "-"),
        week_label.downcase,
        store_slug.presence,
        "#{@report.dig(:period, :from_date)}_to_#{@report.dig(:period, :to_date)}"
      ].compact.join("-") + ".xlsx"
    end

    def week_label
      "W#{Date.iso8601(@report.dig(:period, :to_date).to_s).cweek}"
    end

    def store_slug
      return nil unless @report[:report_type] == "wr"

      @report.dig(:meta, :account, :name).to_s.parameterize.presence || "store"
    end
  end
end
