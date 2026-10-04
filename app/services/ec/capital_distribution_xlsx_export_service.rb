require "axlsx"

module Ec
  class CapitalDistributionXlsxExportService
    MIME_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

    def self.call(summary:, sku_rows:, batch_rows:, from_date:, to_date:, locale: I18n.locale)
      new(summary:, sku_rows:, batch_rows:, from_date:, to_date:, locale:).call
    end

    def initialize(summary:, sku_rows:, batch_rows:, from_date:, to_date:, locale: I18n.locale)
      @summary = summary.deep_symbolize_keys
      @sku_rows = Array(sku_rows).map(&:deep_symbolize_keys)
      @batch_rows = Array(batch_rows).map(&:deep_symbolize_keys)
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @locale = locale
    end

    def call
      package = Axlsx::Package.new

      I18n.with_locale(locale) do
        styles = build_styles(package.workbook.styles)
        add_summary_sheet(package.workbook, styles)
        add_sku_sheet(package.workbook, styles)
        add_batch_sheet(package.workbook, styles)
      end

      {
        filename: "capital-distribution-#{from_date.iso8601}_to_#{to_date.iso8601}.xlsx",
        data: package.to_stream.read,
        content_type: MIME_TYPE
      }
    end

    private

    attr_reader :summary, :sku_rows, :batch_rows, :from_date, :to_date, :locale

    def add_summary_sheet(workbook, styles)
      workbook.add_worksheet(name: translate("sheets.summary")) do |sheet|
        sheet.column_widths(34, 22)
        sheet.add_row(
          [translate("summary_columns.metric"), translate("summary_columns.value")],
          style: Array.new(2, styles[:header])
        )

        summary_rows.each do |label, value, number_format|
          row = sheet.add_row([label, normalize_cell(value)], style: [styles[:label], styles[:body]])
          row.cells[1].style = number_format ? styles.fetch(number_format) : styles[:body]
        end

        freeze_header(sheet)
      end
    end

    def add_sku_sheet(workbook, styles)
      columns = sku_columns

      workbook.add_worksheet(name: translate("sheets.sku_summary")) do |sheet|
        sheet.column_widths(*columns.map { |column| column.fetch(:width) })
        sheet.add_row(columns.map { |column| column.fetch(:label) }, style: Array.new(columns.size, styles[:header]))

        sku_rows.each do |record|
          add_record_row(sheet, record, columns, styles)
        end

        configure_table_sheet(sheet, columns.size, sku_rows.size)
      end
    end

    def add_batch_sheet(workbook, styles)
      columns = batch_columns

      workbook.add_worksheet(name: translate("sheets.batch_detail")) do |sheet|
        sheet.column_widths(*columns.map { |column| column.fetch(:width) })
        sheet.add_row(columns.map { |column| column.fetch(:label) }, style: Array.new(columns.size, styles[:header]))

        batch_rows.each do |record|
          add_record_row(sheet, record, columns, styles)
        end

        configure_table_sheet(sheet, columns.size, batch_rows.size)
      end
    end

    def add_record_row(sheet, record, columns, styles)
      values = columns.map { |column| normalize_cell(column.fetch(:value).call(record)) }
      row_styles = columns.map { |column| styles.fetch(column.fetch(:style, :body)) }
      sheet.add_row(values, style: row_styles)
    end

    def configure_table_sheet(sheet, column_count, record_count)
      freeze_header(sheet)
      last_column = Axlsx::col_ref(column_count - 1)
      sheet.auto_filter = "A1:#{last_column}#{record_count + 1}"
    end

    def freeze_header(sheet)
      sheet.sheet_view.pane do |pane|
        pane.state = :frozen
        pane.y_split = 1
        pane.top_left_cell = "A2"
        pane.active_pane = :bottom_left
      end
    end

    def build_styles(styles)
      base = { vertical: :center }

      {
        header: styles.add_style(
          bg_color: "366092",
          fg_color: "FFFFFF",
          b: true,
          alignment: base.merge(horizontal: :center, wrap_text: true)
        ),
        label: styles.add_style(b: true, bg_color: "D9E1F2", alignment: base),
        body: styles.add_style(alignment: base),
        amount: styles.add_style(format_code: "#,##0.00", alignment: base.merge(horizontal: :right)),
        unit_cost: styles.add_style(format_code: "#,##0.0000", alignment: base.merge(horizontal: :right)),
        quantity: styles.add_style(format_code: "#,##0", alignment: base.merge(horizontal: :right)),
        date: styles.add_style(format_code: "yyyy-mm-dd", alignment: base)
      }
    end

    def summary_rows
      [
        [translate("summary.financial_from"), from_date, :date],
        [translate("summary.financial_to"), to_date, :date],
        [translate("summary.actual_from"), summary[:period_from], :date],
        [translate("summary.actual_to"), summary[:period_to], :date],
        [translate("summary.in_transit_goods"), summary[:in_transit_goods_cost_cny], :amount],
        [translate("summary.in_transit_quantity"), summary[:in_transit_quantity], :quantity],
        [translate("summary.book_stock_goods"), summary[:book_stock_goods_cost_cny], :amount],
        [translate("summary.book_stock_quantity"), summary[:book_stock_quantity], :quantity],
        [translate("summary.book_stock_customs_tax"), summary[:book_stock_customs_tax_cost_cny], :amount],
        [translate("summary.capital_occupied"), summary[:total_amount_cny], :amount],
        [translate("summary.capital_quantity"), summary[:total_quantity], :quantity],
        [translate("summary.settled_sales"), summary[:sales_revenue_cny], :amount],
        [translate("summary.net_sales_quantity"), summary[:net_sales_quantity], :quantity],
        [translate("summary.sold_goods_cost"), summary[:sold_goods_cost_cny], :amount],
        [translate("summary.sold_customs_tax_cost"), summary[:sold_customs_tax_cost_cny], :amount],
        [translate("summary.settled_net_profit"), summary[:net_profit_cny], :amount],
        [translate("summary.unallocated_total"), summary[:unallocated_total_cny].to_d.abs, :amount],
        [translate("summary.missing_cost"), summary[:missing_cost_quantity], :quantity],
        [translate("summary.missing_freight"), summary[:missing_freight_quantity], :quantity],
        [translate("summary.sku_count"), summary[:sku_count], :quantity],
        [translate("summary.batch_count"), summary[:batch_count], :quantity]
      ]
    end

    def sku_columns
      [
        column("sku", 18) { |row| row[:sku_code] },
        column("product_name", 30) { |row| row[:product_name] },
        column("in_transit_goods", 20, :amount) { |row| row[:in_transit_goods_cost_cny] },
        column("in_transit_quantity", 14, :quantity) { |row| row[:in_transit_quantity] },
        column("book_stock_goods", 20, :amount) { |row| row[:book_stock_goods_cost_cny] },
        column("book_stock_quantity", 14, :quantity) { |row| row[:book_stock_quantity] },
        column("book_stock_customs_tax", 20, :amount) { |row| row[:book_stock_customs_tax_cost_cny] },
        column("settled_net_sales", 16, :quantity) { |row| row[:net_sales_quantity] },
        column("sales_revenue", 18, :amount) { |row| row[:sales_revenue_cny] },
        column("sold_goods_cost", 18, :amount) { |row| row[:sold_goods_cost_cny] },
        column("sold_customs_tax_cost", 18, :amount) { |row| row[:sold_customs_tax_cost_cny] },
        column("net_profit", 18, :amount) { |row| row[:net_profit_cny] },
        column("capital_occupied", 18, :amount) { |row| row[:total_amount_cny] },
        column("capital_quantity", 16, :quantity) { |row| row[:total_quantity] },
        column("batch_count", 12, :quantity) { |row| row[:batch_count] },
        column("missing_cost", 16, :quantity) { |row| row[:missing_cost_quantity] },
        column("missing_freight", 18, :quantity) { |row| row[:missing_freight_quantity] }
      ]
    end

    def batch_columns
      [
        column("sku", 18) { |row| row[:sku_code] },
        column("product_name", 30) { |row| row[:product_name] },
        column("batch", 24) { |row| row[:batch_code].presence || translate("values.unmatched_sold") },
        column("batch_type", 18) { |row| translated_batch_value("batch_types", row[:batch_type]) },
        column("status", 14) { |row| translated_batch_value("batch_statuses", row[:status]) },
        column("cost_date", 14, :date) { |row| row[:cost_date] },
        column("cost_effective_on", 16, :date) { |row| row[:cost_effective_on] },
        column("unit_goods_freight_cost", 22, :unit_cost) { |row| row[:unit_goods_and_freight_cost_cny] },
        column("unit_customs_tax_cost", 22, :unit_cost) { |row| row[:unit_customs_tax_cost_cny] },
        column("in_transit_quantity", 14, :quantity) { |row| row[:in_transit_quantity] },
        column("in_transit_goods", 20, :amount) { |row| row[:in_transit_goods_cost_cny] },
        column("book_stock_quantity", 14, :quantity) { |row| row[:book_stock_quantity] },
        column("book_stock_goods", 20, :amount) { |row| row[:book_stock_goods_cost_cny] },
        column("book_stock_customs_tax", 20, :amount) { |row| row[:book_stock_customs_tax_cost_cny] },
        column("allocated_net_sales", 16, :quantity) { |row| row[:sold_quantity] },
        column("capital_occupied", 18, :amount) { |row| batch_total_amount(row) },
        column("missing_cost_flag", 14) { |row| boolean_label(row[:missing_cost]) },
        column("missing_freight_flag", 14) { |row| boolean_label(row[:missing_freight]) }
      ]
    end

    def column(key, width, style = :body, &value)
      { label: translate("columns.#{key}"), width: width, style: style, value: value }
    end

    def translated_batch_value(group, value)
      return translate("values.unmatched_sold") if value.blank?

      I18n.t("reports.inventory.#{group}.#{value}", default: value.to_s)
    end

    def boolean_label(value)
      translate(value ? "values.yes" : "values.no")
    end

    def batch_total_amount(row)
      %i[in_transit_goods_cost_cny book_stock_goods_cost_cny book_stock_customs_tax_cost_cny]
        .sum { |key| row[key].to_d }
    end

    def normalize_cell(value)
      return value.to_f if value.is_a?(BigDecimal)

      value
    end

    def translate(key)
      I18n.t("reports.capital_distribution.export.#{key}")
    end
  end
end
