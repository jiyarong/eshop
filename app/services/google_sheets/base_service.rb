require "google/apis/sheets_v4"
require "googleauth"

module GoogleSheets
  class BaseService
    SPREADSHEET_ID = "1JbhVK4adukKD2b2KnAHHbruCsB9Y9G7xixFkVqMTrpg".freeze
    CREDENTIALS_PATH = Rails.root.join("config", "ecommerce-sheets-495606-2f1153f07139.json").freeze
    SCOPE = Google::Apis::SheetsV4::AUTH_SPREADSHEETS

    # ── 统一色板（与 gen_xlsx.py 一致）─────────────────────────────────────
    COLOR_HDR_BG    = { red: 0.212, green: 0.376, blue: 0.573 }.freeze  # #366092
    COLOR_HDR_FG    = { red: 1.0,   green: 1.0,   blue: 1.0   }.freeze  # white
    COLOR_SECTION   = { red: 0.851, green: 0.882, blue: 0.949 }.freeze  # #D9E1F2
    COLOR_UA_BG     = { red: 1.0,   green: 0.851, blue: 0.4   }.freeze  # #FFD966
    COLOR_TOTAL_BG  = { red: 1.0,   green: 0.753, blue: 0.0   }.freeze  # #FFC000
    COLOR_COL_GREEN = { red: 0.851, green: 0.918, blue: 0.827 }.freeze  # #D9EAD3
    COLOR_COL_ORANGE= { red: 0.988, green: 0.898, blue: 0.804 }.freeze  # #FCE5CD

    FMT_NUMBER  = '#,##0.00'
    FMT_INTEGER = '#,##0'
    FMT_PERCENT = '0.0'

    def initialize
      @service = Google::Apis::SheetsV4::SheetsService.new
      @service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(CREDENTIALS_PATH),
        scope: SCOPE
      )
    end

    private

    def write_to_sheet(range:, values:)
      body = Google::Apis::SheetsV4::ValueRange.new(values: values)
      with_sheets_retry do
        @service.update_spreadsheet_value(SPREADSHEET_ID, range, body, value_input_option: "USER_ENTERED")
      end
    end

    def clear_sheet(range:)
      with_sheets_retry { @service.clear_values(SPREADSHEET_ID, range) }
    end

    def spreadsheet_sheets
      @spreadsheet_sheets ||= @service.get_spreadsheet(SPREADSHEET_ID).sheets
    end

    def sheet_id(title)
      spreadsheet_sheets.find { |s| s.properties.title == title }&.properties&.sheet_id
    end

    def ensure_sheet_exists(title)
      return if spreadsheet_sheets.any? { |s| s.properties.title == title }

      req = Google::Apis::SheetsV4::Request.new(
        add_sheet: Google::Apis::SheetsV4::AddSheetRequest.new(
          properties: Google::Apis::SheetsV4::SheetProperties.new(title:)
        )
      )
      batch_update([req])
      @spreadsheet_sheets = nil
    rescue Google::Apis::ClientError => e
      body = e.respond_to?(:body) ? e.body.to_s : e.message
      raise unless body.include?('already exists') || body.include?('alreadyExists')
      @spreadsheet_sheets = nil
    end

    def delete_sheets_with_prefix(prefix)
      matching = spreadsheet_sheets.select { |s| s.properties.title.start_with?(prefix) }
      return if matching.empty?

      reqs = matching.map do |s|
        Google::Apis::SheetsV4::Request.new(
          delete_sheet: Google::Apis::SheetsV4::DeleteSheetRequest.new(
            sheet_id: s.properties.sheet_id
          )
        )
      end
      batch_update(reqs)
      @spreadsheet_sheets = nil
    end

    def delete_sheet_if_exists(title)
      sid = sheet_id(title)
      return unless sid

      req = Google::Apis::SheetsV4::Request.new(
        delete_sheet: Google::Apis::SheetsV4::DeleteSheetRequest.new(sheet_id: sid)
      )
      batch_update([req])
      @spreadsheet_sheets = nil
    end

    def batch_update(requests)
      body = Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(requests:)
      with_sheets_retry { @service.batch_update_spreadsheet(SPREADSHEET_ID, body) }
    end

    def with_sheets_retry(max_retries: 5)
      retries = 0
      begin
        yield
      rescue Google::Apis::RateLimitError
        retries += 1
        raise if retries > max_retries
        wait = 20 * retries
        Rails.logger.warn "[GoogleSheets] Write quota exceeded, waiting #{wait}s (retry #{retries}/#{max_retries})"
        sleep wait
        retry
      end
    end

    # ════════════════════════════════════════════════════════════════════════
    # 样式构建工具（返回 request hash，由子类汇总后统一 batch_update）
    # ════════════════════════════════════════════════════════════════════════

    # 表头行：蓝底白字加粗居中自动换行
    def req_header_rows(sid, num_rows:, num_cols:, start_row: 0)
      {
        repeat_cell: {
          range: grid(sid, start_row, start_row + num_rows, 0, num_cols),
          cell: { user_entered_format: {
            background_color:   COLOR_HDR_BG,
            text_format:        { bold: true, font_size: 10,
                                  foreground_color: COLOR_HDR_FG,
                                  font_family: 'Calibri' },
            horizontal_alignment: 'CENTER',
            vertical_alignment:   'MIDDLE',
            wrap_strategy:        'WRAP',
          }},
          fields: 'userEnteredFormat(backgroundColor,textFormat,horizontalAlignment,verticalAlignment,wrapStrategy)',
        }
      }
    end

    # 数据区域：细灰框线 + 右对齐数字 / 左对齐文本（按列类型区分）
    # col_types: array of :text / :number / :integer / :percent，长度 = num_cols
    def req_data_rows(sid, start_row:, end_row:, col_types:)
      reqs = []
      num_cols = col_types.size

      # 整体加细边框
      reqs << {
        update_borders: {
          range: grid(sid, start_row, end_row, 0, num_cols),
          top:    thin_border, bottom: thin_border,
          left:   thin_border, right:  thin_border,
          inner_horizontal: thin_border, inner_vertical: thin_border,
        }
      }

      # 按列类型批量设置数字格式 + 对齐
      col_types.each_with_index do |type, ci|
        next if type == :text
        fmt, align = case type
          when :number  then [FMT_NUMBER,  'RIGHT']
          when :integer then [FMT_INTEGER, 'RIGHT']
          when :percent then [FMT_PERCENT, 'RIGHT']
          end
        reqs << {
          repeat_cell: {
            range: grid(sid, start_row, end_row, ci, ci + 1),
            cell: { user_entered_format: {
              number_format:        { type: 'NUMBER', pattern: fmt },
              horizontal_alignment: align,
            }},
            fields: 'userEnteredFormat(numberFormat,horizontalAlignment)',
          }
        }
      end

      reqs
    end

    # 单行特殊背景（:section → 浅黄，:total → 金色加粗）
    def req_special_row(sid, row_index:, style:, num_cols:)
      bg, bold = case style
        when :section then [COLOR_UA_BG,    false]
        when :total   then [COLOR_TOTAL_BG, true]
        when :sub     then [COLOR_SECTION,  true]
        end
      {
        repeat_cell: {
          range: grid(sid, row_index, row_index + 1, 0, num_cols),
          cell: { user_entered_format: {
            background_color: bg,
            text_format: { bold: bold, font_size: 10 },
          }},
          fields: 'userEnteredFormat(backgroundColor,textFormat)',
        }
      }
    end

    # 冻结行
    def req_freeze_rows(sid, count:)
      {
        update_sheet_properties: {
          properties: { sheet_id: sid,
                        grid_properties: { frozen_row_count: count } },
          fields: 'gridProperties.frozenRowCount',
        }
      }
    end

    # 列宽（像素）
    def req_col_widths(sid, widths:)
      widths.each_with_index.map do |px, i|
        {
          update_dimension_properties: {
            range: { sheet_id: sid, dimension: 'COLUMNS',
                     start_index: i, end_index: i + 1 },
            properties: { pixel_size: px },
            fields: 'pixelSize',
          }
        }
      end
    end

    # 整列背景色（用于 CostSheetWriteService 的绿/橙列分区）
    def req_col_bg(sid, start_col:, end_col:, color:)
      {
        repeat_cell: {
          range: grid(sid, 0, 10_000, start_col, end_col),
          cell: { user_entered_format: {
            background_color: color,
          }},
          fields: 'userEnteredFormat.backgroundColor',
        }
      }
    end

    def req_clear_format(sid, num_rows: 1000, num_cols: 30)
      {
        repeat_cell: {
          range: grid(sid, 0, num_rows, 0, num_cols),
          cell: { user_entered_format: {} },
          fields: 'userEnteredFormat',
        }
      }
    end

    # ── 内部工具 ─────────────────────────────────────────────────────────────

    def grid(sid, r0, r1, c0, c1)
      { sheet_id: sid, start_row_index: r0, end_row_index: r1,
        start_column_index: c0, end_column_index: c1 }
    end

    def thin_border
      { style: 'SOLID', width: 1,
        color: { red: 0.749, green: 0.749, blue: 0.749 } }
    end
  end
end
