module Ec
  class InventoryPageDetailQuery
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze
    BOOK_STATUSES = %w[received closed].freeze
    BOOK_BATCH_PAGE_SIZE = 10
    ORDER_STATUS_COLUMNS = %w[pending processing shipping signed].freeze
    PLATFORM_BUCKETS = [
      { key: "ozon_fbo", platform: "ozon", fulfillment_type: "fbo" },
      { key: "ozon_inbound", platform: "ozon", fulfillment_type: "inbound" },
      { key: "wb_fbo", platform: "wb", fulfillment_type: "fbw" },
      { key: "wb_inbound", platform: "wb", fulfillment_type: "inbound" }
    ].freeze
    def initialize(sku, detail_tab:, book_batch_page:, date_to: nil, time_zone: nil)
      @sku = sku
      @detail_tab = detail_tab.presence_in(%w[incoming book platform]) || "incoming"
      @requested_book_batch_page = [book_batch_page.to_i, 1].max
      @date_to = date_to || Time.current.to_date
      @time_zone = time_zone || Time.zone
    end

    def call
      overview = @sku.inventory_overview
      book_batches = book_batches_scope
      pagination = book_batch_pagination(book_batches.count)
      velocity_metrics = inventory_velocity_metrics(overview[:summary])

      {
        sku_code: @sku.sku_code,
        product_name: @sku.product_name,
        product_name_ru: @sku.product_name_ru,
        active_detail_tab: @detail_tab,
        summary: overview[:summary],
        daily_sales_velocity: velocity_metrics[:daily_sales_velocity],
        turnover_days: velocity_metrics[:turnover_days],
        turnover_days_with_procurement: velocity_metrics[:turnover_days_with_procurement],
        incoming_quantity: incoming_batches.sum { |row| row[:purchased_quantity].to_i },
        incoming_batches: incoming_batches,
        book_batches: paginate_book_batches(book_batches, pagination[:page]),
        book_batch_pagination: pagination,
        book_mini_stats: book_mini_stats(overview[:summary]),
        book_sales_distribution: book_sales_distribution(overview[:store_rows]),
        return_distribution: return_distribution(overview[:store_rows]),
        book_formula: book_formula(overview[:summary]),
        platform_mini_stats: platform_mini_stats(overview[:latest_levels]),
        platform_shop_rows: platform_shop_rows(overview[:latest_levels]),
        platform_shop_summary_row: platform_shop_summary_row(overview[:latest_levels]),
        platform_formula: platform_formula(overview[:summary], overview[:latest_levels]),
        platform_warehouse_rows: platform_warehouse_rows(overview[:latest_levels]),
        store_reconciliation_rows: overview[:store_rows],
        platform_breakdown: platform_breakdown(overview[:latest_levels])
      }
    end

    private

    def incoming_batches
      @incoming_batches ||= @sku.batches
        .where(status: INCOMING_STATUSES)
        .order(Arel.sql(incoming_status_order_sql), :expected_arrival_on, :batch_code)
        .map do |batch|
          {
            batch_code: batch.batch_code,
            status: batch.status,
            expected_arrival_on: batch.expected_arrival_on,
            purchased_quantity: batch.purchased_quantity,
            memo: batch.memo
          }
        end
    end

    def procurement_batches_scope
      @sku.batches.where(status: INCOMING_STATUSES, batch_type: :normal)
    end

    def procurement_quantity
      procurement_batches_scope.sum(:purchased_quantity).to_i
    end

    def book_batches_scope
      @sku.batches.where(status: BOOK_STATUSES).order(received_on: :desc, batch_code: :desc)
    end

    def paginate_book_batches(scope, page)
      scope.limit(BOOK_BATCH_PAGE_SIZE).offset((page - 1) * BOOK_BATCH_PAGE_SIZE).map do |batch|
        {
          batch_code: batch.batch_code,
          batch_type: batch.batch_type,
          defect_offset_note: batch.defect_offset_note,
          received_quantity: batch.received_quantity,
          received_on: batch.received_on,
          status: batch.status
        }
      end
    end

    def book_batch_pagination(total_count)
      total_pages = (total_count / BOOK_BATCH_PAGE_SIZE.to_f).ceil
      total_pages = [total_pages, 1].max
      page = [@requested_book_batch_page, total_pages].min

      {
        page: page,
        page_size: BOOK_BATCH_PAGE_SIZE,
        total_count: total_count,
        total_pages: total_pages
      }
    end

    def platform_breakdown(levels)
      levels.sort_by do |level|
        [
          level.platform.to_s,
          level.store_name.to_s,
          level.store_id || 0,
          level.account_id || 0,
          level.fulfillment_type.to_s
        ]
      end.map do |level|
        {
          platform: level.platform,
          fulfillment_type: level.fulfillment_type,
          store_id: level.store_id,
          store_name: level.store_name,
          account_id: level.account_id,
          quantity: level.quantity,
          latest_synced_at: level.synced_at
        }
      end
    end

    def book_mini_stats(summary)
      [
        stat_row("purchase_quantity", summary[:purchase_quantity]),
        stat_row("wb_net_sales", sales_quantity_for("wb")),
        stat_row("ozon_net_sales", sales_quantity_for("ozon"))
      ]
    end

    def book_sales_distribution(store_rows)
      rows = store_rows.select { |row| row[:platform].in?(%w[wb ozon]) }.map do |row|
        {
          store_label: "#{platform_label(row[:platform])} * #{row[:store_name]}",
          counts: ORDER_STATUS_COLUMNS.index_with { |column| row.dig(:order_status_counts, column).to_i }
        }
      end.select { |row| row[:counts].values.sum(&:to_i).positive? }

      summary_row = distribution_summary_row(rows)

      {
        columns: ORDER_STATUS_COLUMNS,
        rows: rows,
        summary_row: summary_row[:counts].values.sum(&:to_i).positive? ? summary_row : nil
      }
    end

    def return_distribution(store_rows)
      rows = store_rows.select { |row| row[:platform].in?(%w[wb ozon]) }.map do |row|
        {
          store_label: "#{platform_label(row[:platform])} * #{row[:store_name]}",
          return_count: row[:return_quantity].to_i
        }
      end.select { |row| row[:return_count].positive? }

      summary_return_count = rows.sum { |row| row[:return_count].to_i }

      {
        rows: rows,
        summary_row: summary_return_count.positive? ? {
          store_label_key: "summary",
          return_count: summary_return_count
        } : nil
      }
    end

    def book_formula(summary)
      items = [
        formula_item("purchase_quantity", summary[:purchase_quantity], "+"),
        formula_item("wb_net_sales", sales_quantity_for("wb"), "-"),
        formula_item("ozon_net_sales", sales_quantity_for("ozon"), "-"),
        formula_item("wb_returns", return_quantity_for("wb"), "+"),
        formula_item("ozon_returns", return_quantity_for("ozon"), "+")
      ]

      adjustment_quantities.each do |type, quantity|
        next if quantity.to_i.zero?

        items << formula_item(
          formula_key_for_adjustment(type),
          quantity.to_i.abs,
          quantity.to_i.negative? ? "-" : "+"
        )
      end

      {
        items: items,
        result: summary[:book_stock].to_i
      }
    end

    def platform_mini_stats(levels)
      PLATFORM_BUCKETS.map do |bucket|
        quantity = levels
          .select { |level| level.platform == bucket[:platform] && level.fulfillment_type == bucket[:fulfillment_type] }
          .sum(&:quantity)

        stat_row(bucket[:key], quantity)
      end
    end

    def platform_shop_rows(levels)
      grouped = levels.group_by { |level| [level.platform.to_s, level.store_name.to_s, level.store_id, level.account_id] }

      grouped.map do |(platform, store_name, _store_id, _account_id), group_levels|
        {
          store_label: "#{platform_label(platform)} * #{store_name}",
          fbo: group_levels.select { |level| level.fulfillment_type.to_s.in?(%w[fbo fbw]) }.sum(&:quantity),
          inbound: group_levels.select { |level| level.fulfillment_type.to_s == "inbound" }.sum(&:quantity),
          fbs: group_levels.select { |level| level.fulfillment_type.to_s == "fbs" }.sum(&:quantity)
        }
      end.sort_by { |row| row[:store_label] }
    end

    def platform_shop_summary_row(levels)
      rows = platform_shop_rows(levels)

      {
        store_label_key: "summary",
        fbo: rows.sum { |row| row[:fbo].to_i },
        inbound: rows.sum { |row| row[:inbound].to_i },
        fbs: rows.sum { |row| row[:fbs].to_i }
      }
    end

    def platform_formula(summary, _levels)
      {
        items: [
          formula_item("book_inventory", summary[:book_stock], "+"),
          formula_item("platform_inventory_total", summary[:fbo_fbw_stock], "-"),
          formula_item("platform_inbound", summary[:platform_inbound_stock], "-")
        ],
        result: summary[:available_stock].to_i,
        description_key: "overseas_available"
      }
    end

    def platform_warehouse_rows(levels)
      levels
        .select { |level| level.fulfillment_type.to_s.in?(%w[fbo fbw]) }
        .flat_map do |level|
          Array(level.warehouse_breakdown).map do |warehouse|
            {
              store_label: "#{platform_label(level.platform)} * #{level.store_name}",
              fulfillment_type: level.fulfillment_type,
              warehouse_name: warehouse_value(warehouse, :warehouse_name),
              cluster_name: warehouse_value(warehouse, :cluster_name),
              quantity: warehouse_value(warehouse, :quantity).to_i,
              promised: warehouse_value(warehouse, :promised),
              reserved: warehouse_value(warehouse, :reserved),
              latest_synced_at: level.synced_at
            }
          end
        end
        .select { |row| row[:warehouse_name].present? && [row[:quantity], row[:promised], row[:reserved]].compact.sum(&:to_i).positive? }
        .sort_by { |row| [row[:store_label].to_s, row[:fulfillment_type].to_s, row[:warehouse_name].to_s] }
    end

    def incoming_status_order_sql
      <<~SQL.squish
        CASE status
          WHEN 'draft' THEN 0
          WHEN 'ordered' THEN 1
          WHEN 'in_transit' THEN 2
          ELSE 3
        END
      SQL
    end

    def stat_row(key, value)
      { key: key, value: value.to_i, unit_key: "quantity", format: :integer }
    end

    def decimal_stat_row(key, value, unit_key: nil)
      { key: key, value: value, unit_key: unit_key, format: :decimal }
    end

    def formula_item(key, value, operator)
      { key: key, value: value.to_i, operator: operator }
    end

    def warehouse_value(row, key)
      row[key] || row[key.to_s]
    end

    def distribution_summary_row(rows)
      counts = ORDER_STATUS_COLUMNS.index_with do |column_key|
        rows.sum { |row| row.dig(:counts, column_key).to_i }
      end

      {
        store_label_key: "summary",
        counts: counts
      }
    end

    def sales_quantity_for(platform)
      @sales_quantity_by_platform ||= @sku.inventory_overview[:store_rows]
        .group_by { |row| row[:platform].to_s }
        .transform_values { |rows| rows.sum { |row| row[:sales_quantity].to_i } }

      @sales_quantity_by_platform[platform].to_i
    end

    def return_quantity_for(platform)
      @return_quantity_by_platform ||= @sku.inventory_overview[:store_rows]
        .group_by { |row| row[:platform].to_s }
        .transform_values { |rows| rows.sum { |row| row[:return_quantity].to_i } }

      @return_quantity_by_platform[platform].to_i
    end

    def adjustment_quantities
      @adjustment_quantities ||= @sku.batches
        .where(status: BOOK_STATUSES)
        .where.not(batch_type: :normal)
        .group(:batch_type)
        .sum(:received_quantity)
        .transform_values(&:to_i)
    end

    def inventory_velocity_metrics(summary)
      @inventory_velocity_metrics ||= begin
        metrics = Ec::InventoryVelocityMetricsQuery.new(
          sku_codes: [@sku.sku_code],
          date_to: @date_to,
          time_zone: @time_zone
        ).call.fetch(@sku.sku_code, {})

        daily_sales_velocity = metrics[:daily_sales_velocity]
        book_stock = summary[:book_stock].to_d
        procurement_stock = procurement_quantity.to_d

        metrics.merge(
          turnover_days: daily_sales_velocity.to_d.positive? ? (book_stock / daily_sales_velocity.to_d) : nil,
          turnover_days_with_procurement: daily_sales_velocity.to_d.positive? ? ((book_stock + procurement_stock) / daily_sales_velocity.to_d) : nil
        )
      end
    end

    def platform_label(platform)
      platform.to_s == "ozon" ? "OZON" : "WB"
    end

    def formula_key_for_adjustment(type)
      case type.to_s
      when "wb_fbw_offset" then "wb_fbw_offset"
      when "untrackable_defective" then "untrackable_defective"
      else "other_adjustment"
      end
    end
  end
end
