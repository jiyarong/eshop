module GoogleSheets
  class InventoryWithVolSheetService < BaseService
    TAB_NAME = "Inventory With Vol".freeze

    HEADERS_ZH = [
      "SKU", "商品名(中文)", "商品名(俄文)",
      "采购中库存", "采购中库存体积(m³)",
      "账面可用库存", "账面可用库存体积(m³)",
      "平台在途", "平台在途体积(m³)",
      "平台在库", "平台在库体积(m³)",
      "FBS库存", "FBS库存体积(m³)",
      "日均销量", "周转天数", "周转天数(含采购)",
      "长(cm)", "宽(cm)", "高(cm)", "单件体积(L)"
    ].freeze

    HEADERS_RU = [
      "SKU", "Название (кит.)", "Название (рус.)",
      "Закупаемый запас", "Объём закупаемого запаса (м³)",
      "Книжный доступный запас", "Объём книжного доступного запаса (м³)",
      "В поставке", "Объём в поставке (м³)",
      "Остаток платформ", "Объём остатка платформ (м³)",
      "FBS запас", "Объём FBS запаса (м³)",
      "Средние продажи в день", "Оборачиваемость", "Оборачиваемость с закупкой",
      "Длина (см)", "Ширина (см)", "Высота (см)", "Объём единицы (L)"
    ].freeze

    COL_WIDTHS = [120, 180, 180, 90, 120, 90, 120, 90, 120, 90, 120, 90, 120, 100, 100, 130, 80, 80, 80, 90].freeze
    NUMERIC_TYPES = [:text, :text, :text, :integer, :number, :integer, :number, :integer, :number, :integer, :number, :integer, :number, :number, :number, :number, :number, :number, :number, :number].freeze
    EXPORT_TIME_ZONE = ActiveSupport::TimeZone["Asia/Shanghai"]

    def call
      ensure_sheet_exists(TAB_NAME)
      clear_sheet(range: "#{TAB_NAME}!A:ZZ")

      rows = build_rows
      write_to_sheet(range: "#{TAB_NAME}!A1", values: [HEADERS_ZH, HEADERS_RU] + rows)
      apply_styles(rows.size)

      { tab: TAB_NAME, sku_count: rows.size }
    end

    private

    def build_rows
      skus = Ec::Sku.includes(:cost).order(:sku_code).to_a
      metrics_by_sku = Ec::InventoryVelocityMetricsQuery.new(
        sku_codes: skus.map(&:sku_code),
        date_to: Date.current,
        time_zone: EXPORT_TIME_ZONE
      ).call

      skus.map do |sku|
        raw_row = Ec::InventoryPageRowQuery.new(sku).call
        row = Ec::InventoryReportRowMetricsBuilder.call(raw_row, metrics: metrics_by_sku[sku.sku_code] || {})

        [
          row[:sku_code],
          row[:product_name].to_s,
          row[:product_name_ru].to_s,
          row[:incoming_quantity],
          estimated_volume_m3(row[:incoming_quantity], row[:unit_volume_l]),
          row[:book_stock],
          estimated_volume_m3(row[:book_stock], row[:unit_volume_l]),
          row[:platform_inbound_stock],
          estimated_volume_m3(row[:platform_inbound_stock], row[:unit_volume_l]),
          row[:platform_stock],
          estimated_volume_m3(row[:platform_stock], row[:unit_volume_l]),
          row[:available_stock],
          estimated_volume_m3(row[:available_stock], row[:unit_volume_l]),
          row[:daily_sales_velocity],
          row[:turnover_days],
          row[:turnover_days_with_procurement],
          positive_decimal_or_nil(row[:pkg_length_cm]),
          positive_decimal_or_nil(row[:pkg_width_cm]),
          positive_decimal_or_nil(row[:pkg_height_cm]),
          positive_decimal_or_nil(row[:unit_volume_l])
        ]
      end
    end

    def estimated_volume_m3(quantity, unit_volume_l)
      return nil if unit_volume_l.blank?

      unit_volume_l = unit_volume_l.to_d
      return nil unless unit_volume_l.positive?

      quantity.to_d * unit_volume_l / 1000
    end

    def positive_decimal_or_nil(value)
      return nil if value.blank?

      decimal = value.to_d
      decimal.positive? ? decimal : nil
    end

    def apply_styles(row_count)
      @spreadsheet_sheets = nil
      sid = sheet_id(TAB_NAME)
      return unless sid

      data_end = 2 + row_count
      reqs = []
      reqs << req_header_rows(sid, num_rows: 2, num_cols: HEADERS_ZH.size)
      reqs += req_data_rows(sid, start_row: 2, end_row: data_end, col_types: NUMERIC_TYPES)
      reqs << req_freeze_rows(sid, count: 2)
      reqs += req_col_widths(sid, widths: COL_WIDTHS)
      batch_update(reqs)
    end
  end
end
