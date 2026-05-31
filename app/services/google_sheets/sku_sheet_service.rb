module GoogleSheets
  class SkuSheetService < BaseService
    TAB_NAME = 'SKU'.freeze

    HEADERS_ZH = ['SKU编码', '商品名(中文)', '商品名(俄文)', '是否上架'].freeze
    HEADERS_RU = ['Код SKU',  'Название (кит.)', 'Название (рус.)', 'Активен'].freeze

    COL_WIDTHS = [110, 180, 220, 80].freeze

    def call
      ensure_sheet_exists(TAB_NAME)
      clear_sheet(range: "#{TAB_NAME}!A:ZZ")
      write_data
    end

    private

    def write_data
      skus = Ec::Sku.order(:sku_code).all

      data_rows = skus.map do |sku|
        [sku.sku_code, sku.product_name.to_s, sku.product_name_ru.to_s,
         sku.is_active ? '是' : '否']
      end

      write_to_sheet(range: "#{TAB_NAME}!A1",
                     values: [HEADERS_ZH, HEADERS_RU] + data_rows)

      apply_styles(skus.size)
      { tab: TAB_NAME, skus: skus.size }
    end

    def apply_styles(sku_count)
      @spreadsheet_sheets = nil
      sid = sheet_id(TAB_NAME)
      return unless sid

      num_cols = COL_WIDTHS.size
      data_end = 2 + sku_count

      reqs = []
      reqs << req_header_rows(sid, num_rows: 2, num_cols: num_cols)
      reqs += req_data_rows(sid, start_row: 2, end_row: data_end,
                            col_types: [:text, :text, :text, :text])
      reqs << req_freeze_rows(sid, count: 2)
      reqs += req_col_widths(sid, widths: COL_WIDTHS)

      batch_update(reqs)
    end
  end
end
