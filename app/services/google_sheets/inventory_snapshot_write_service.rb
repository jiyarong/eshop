module GoogleSheets
  class InventorySnapshotWriteService < BaseService
    TAB_NAME = "Inventory".freeze

    STORES = [
      { name: "Nevastal",    platform: "ozon", account_id: 1, type: "FBO" },
      { name: "Nevastal2",   platform: "ozon", account_id: 3, type: "FBO" },
      { name: "Domos",       platform: "ozon", account_id: 4, type: "FBO" },
      { name: "Nanokit",     platform: "ozon", account_id: 5, type: "FBO" },
      { name: "WorldChoice", platform: "wb",   account_id: 3, type: "FBW" },
      { name: "TaxiLink",    platform: "wb",   account_id: 2, type: "FBW" },
    ].freeze

    # 中文 / 俄文 子列标签
    STORE_SUB_ZH = %w[库存 送仓 售出 FBS].freeze
    STORE_SUB_RU = ["Остаток", "Поставки", "Продажи", "FBS"].freeze

    SUMMARY_ZH = ["总送仓",       "总库存",          "总售出",          "FBS总计"   ].freeze
    SUMMARY_RU = ["Итого пост.", "Итого остатков", "Итого продаж",  "Итого FBS" ].freeze

    MANUAL_ZH  = ["总入库"      ].freeze
    MANUAL_RU  = ["Всего принято"].freeze

    DERIVED_ZH = ["白俄仓推算",       "总可售"              ].freeze
    DERIVED_RU = ["Остаток BY (расч.)", "Доступно к продаже"].freeze

    META_ZH    = ["同步时间"   ].freeze
    META_RU    = ["Обновлено"].freeze

    # 固定列：Article / 中文名 / 俄文名
    FIXED_COLS  = 3
    STORE_BLOCK = STORE_SUB_ZH.size   # 4
    SUMMARY_START = FIXED_COLS + STORES.size * STORE_BLOCK
    MANUAL_START  = SUMMARY_START + SUMMARY_ZH.size
    DERIVED_START = MANUAL_START  + MANUAL_ZH.size
    META_START    = DERIVED_START + DERIVED_ZH.size
    TOTAL_COLS    = META_START    + META_ZH.size

    # 表头行数（English group / 中文 / Русский），数据从第4行开始
    HEADER_ROWS = 3

    # total_received 列索引（0-based），供 import service 使用
    TOTAL_RECEIVED_COL = MANUAL_START

    def call
      ensure_sheet_exists(TAB_NAME)
      clear_sheet(range: "#{TAB_NAME}!A:ZZ")

      snapshots = load_snapshots
      totals    = load_totals
      skus      = load_skus

      rows = build_rows(snapshots, totals, skus)
      write_to_sheet(range: "#{TAB_NAME}!A1", values: header_rows + rows)
      apply_styles(rows.size)

      { tab: TAB_NAME, rows: rows.size }
    end

    private

    def load_snapshots
      Ec::InventorySnapshot.all.each_with_object({}) do |s, h|
        h[[s.sku_code, s.platform, s.account_id]] = s
      end
    end

    def load_totals
      Ec::InventoryTotal.all.index_by(&:sku_code)
    end

    def load_skus
      Ec::Sku.all.index_by(&:sku_code)
    end

    def all_sku_codes(totals, skus)
      all = (totals.keys + skus.keys).uniq
      matched, unmatched = all.partition { |code| skus.key?(code) }
      matched.sort + unmatched.sort
    end

    def build_rows(snapshots, totals, skus)
      all_sku_codes(totals, skus).each_with_index.map do |sku_code, idx|
        row_n = idx + HEADER_ROWS + 1  # Sheet 行号（1-indexed）
        total = totals[sku_code]
        sku   = skus[sku_code]
        row   = [sku_code, sku&.product_name.to_s, sku&.product_name_ru.to_s]

        STORES.each do |store|
          snap = snapshots[[sku_code, store[:platform], store[:account_id]]]
          row += [snap&.stock.to_i, snap&.supply.to_i, snap&.sold.to_i, snap&.fbs.to_i]
        end

        row += [
          total&.total_supply.to_i,
          total&.total_stock.to_i,
          total&.total_sold.to_i,
          total&.total_fbs.to_i,
        ]

        row << total&.total_received.to_i

        # 派生列：Sheets 公式
        received_col = col_letter(TOTAL_RECEIVED_COL)
        supply_col   = col_letter(SUMMARY_START)
        fbs_col      = col_letter(SUMMARY_START + 3)
        blr_col      = col_letter(DERIVED_START)
        stock_col    = col_letter(SUMMARY_START + 1)

        row << "=#{received_col}#{row_n}-#{supply_col}#{row_n}-#{fbs_col}#{row_n}"
        row << "=#{blr_col}#{row_n}+#{stock_col}#{row_n}"

        row << total&.synced_at&.strftime("%Y-%m-%d %H:%M")

        row
      end
    end

    # 0-indexed 列号 → A1 列字母
    def col_letter(idx)
      result = ""
      loop do
        result = ("A".ord + idx % 26).chr + result
        idx    = idx / 26 - 1
        break if idx < 0
      end
      result
    end

    def header_rows
      # 第1行：英文分组标题
      h1 = ["Article", "Name", nil]
      STORES.each { |s| h1 += [s[:name], nil, nil, nil] }
      h1 += ["Summary", nil, nil, nil]
      h1 += ["Manual"]
      h1 += ["Auto", nil]
      h1 += ["Meta"]

      # 第2行：中文列标签
      h2 = [nil, "产品名(中)", "产品名(俄)"]
      STORES.each { |s| h2 += STORE_SUB_ZH.map { |c| "#{s[:type]}#{c}" } }
      h2 += SUMMARY_ZH
      h2 += MANUAL_ZH
      h2 += DERIVED_ZH
      h2 += META_ZH

      # 第3行：俄文列标签
      h3 = [nil, "Название (кит.)", "Название (рус.)"]
      STORES.each { |s| h3 += STORE_SUB_RU.map { |c| "#{s[:type]} #{c}" } }
      h3 += SUMMARY_RU
      h3 += MANUAL_RU
      h3 += DERIVED_RU
      h3 += META_RU

      [h1, h2, h3]
    end

    def apply_styles(data_row_count)
      @spreadsheet_sheets = nil
      sid = sheet_id(TAB_NAME)
      return unless sid

      total_rows = HEADER_ROWS + data_row_count
      reqs       = []

      # 冻结前3行 + 前3列
      reqs << req_freeze_rows(sid, count: HEADER_ROWS)
      reqs << {
        update_sheet_properties: {
          properties: { sheet_id: sid,
                        grid_properties: { frozen_column_count: FIXED_COLS } },
          fields: "gridProperties.frozenColumnCount",
        }
      }

      # 表头样式（3行）
      reqs << req_header_rows(sid, num_rows: HEADER_ROWS, num_cols: TOTAL_COLS)

      # 数据区域 border + 数字格式
      col_types = ([:text] * FIXED_COLS) +
                  ([:integer] * (STORES.size * STORE_BLOCK)) +
                  ([:integer] * SUMMARY_ZH.size) +
                  ([:integer] * MANUAL_ZH.size) +
                  ([:integer] * DERIVED_ZH.size) +
                  [:text]
      reqs += req_data_rows(sid, start_row: HEADER_ROWS, end_row: total_rows, col_types: col_types)

      # 手填列（总入库）黄底
      reqs << {
        repeat_cell: {
          range: grid(sid, 0, total_rows, TOTAL_RECEIVED_COL, TOTAL_RECEIVED_COL + 1),
          cell: { user_entered_format: { background_color: COLOR_UA_BG } },
          fields: "userEnteredFormat.backgroundColor",
        }
      }

      # 派生列灰底（公式只读）
      color_readonly = { red: 0.878, green: 0.878, blue: 0.878 }
      reqs << {
        repeat_cell: {
          range: grid(sid, 0, total_rows, DERIVED_START, DERIVED_START + DERIVED_ZH.size),
          cell: { user_entered_format: { background_color: color_readonly } },
          fields: "userEnteredFormat.backgroundColor",
        }
      }

      # 列宽：Article=100, 中文名=150, 俄文名=180, 数据列=55, 汇总=65, 手填=75, 派生=80, 时间=130
      widths = [100, 150, 180] +
               ([55] * (STORES.size * STORE_BLOCK)) +
               ([65] * SUMMARY_ZH.size) +
               ([75] * MANUAL_ZH.size) +
               ([80] * DERIVED_ZH.size) +
               [130]
      reqs += req_col_widths(sid, widths: widths)

      # 合并第1行分组标题（Name 跨2列，各 store 跨4列，Summary 跨4列，Auto 跨2列）
      [
        [1,            2],                                               # Name 列 B-C
        *STORES.each_with_index.map { |_, i| [FIXED_COLS + i * STORE_BLOCK, STORE_BLOCK] },
        [SUMMARY_START,  SUMMARY_ZH.size],
        [DERIVED_START,  DERIVED_ZH.size],
      ].each do |start_col, size|
        next unless size > 1
        reqs << {
          merge_cells: {
            range: grid(sid, 0, 1, start_col, start_col + size),
            merge_type: "MERGE_ALL",
          }
        }
      end

      batch_update(reqs)
    end
  end
end
