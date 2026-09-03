module Ec
  class SkuInventoryTrendQuery
    DEFAULT_WEEKS = 8
    METRICS = %i[
      book_stock platform_stock turnover_days_with_procurement fbs_stock
      platform_inbound_stock incoming_quantity daily_sales_velocity turnover_days
    ].freeze

    def initialize(sku, to_date:, time_zone:, weeks: DEFAULT_WEEKS, selected_store_key: nil,
      store_from_date: nil, store_to_date: nil)
      @sku = sku
      @to_date = to_date.to_date
      @time_zone = time_zone
      @weeks = [[weeks.to_i, 1].max, 12].min
      @selected_store_key = selected_store_key.to_s
      @store_to_date = (store_to_date || @to_date).to_date
      @store_from_date = (store_from_date || @store_to_date - 27.days).to_date
    end

    def call
      rows = week_ranges.map { |range| week_row(range) }
      dates = week_ranges.first.begin..week_ranges.last.end
      store_options = build_store_options
      selected_store_key = @selected_store_key.presence_in(store_options.map { |option| option[:key] }) || store_options.first&.dig(:key)

      {
        sku_code: @sku.sku_code,
        weeks: rows,
        available_metrics: METRICS.select { |metric| rows.any? { |row| row.dig(:metrics, metric).present? } },
        operation_events: operation_events(dates),
        store_options: store_options,
        selected_store_key: selected_store_key,
        store_from_date: @store_from_date,
        store_to_date: @store_to_date,
        store_days: store_dates.map { |date| store_day_row(date, selected_store_key) },
        store_trends: store_options.map do |option|
          option.merge(days: store_dates.map { |date| store_day_row(date, option[:key]) })
        end
      }
    end

    def operation_events(dates)
      Ec::OperationActionChartEventsQuery.run(
          sku: @sku,
          from_time: at_start_of_day(dates.begin),
          to_time: at_start_of_day(dates.end + 1.day),
          user_time_zone: @time_zone.name
        ).map do |event|
          event.merge(marker_x: week_label(Date.iso8601(event.fetch(:event_date)).beginning_of_week(:monday)))
        end
    end

    private

    def week_ranges
      @week_ranges ||= begin
        last_end = @to_date.end_of_week(:monday)
        first_start = last_end.beginning_of_week(:monday) - (@weeks - 1).weeks
        @weeks.times.map do |index|
          start_date = first_start + index.weeks
          start_date..start_date.end_of_week(:monday)
        end
      end
    end

    def snapshots_by_week
      @snapshots_by_week ||= @sku.snapshots
        .of_type(Ec::InventorySnapshot.snapshot_type)
        .between(week_ranges.first.begin, [week_ranges.last.end, @to_date].min)
        .order(:snapshot_date)
        .to_a
        .group_by { |snapshot| snapshot.snapshot_date.beginning_of_week(:monday) }
    end

    def week_row(range)
      snapshot = snapshots_by_week.fetch(range.begin, []).reverse.find { |candidate| valid_snapshot?(candidate) }
      return { week_start: range.begin, week_end: range.end, snapshot_date: nil, missing: true, metrics: {} } unless snapshot

      {
        week_start: range.begin,
        week_end: range.end,
        snapshot_date: snapshot.snapshot_date,
        is_week_end: snapshot.snapshot_date == range.end,
        missing: false,
        metrics: metrics(snapshot.data)
      }
    end

    def valid_snapshot?(snapshot)
      snapshot.data[:overview].is_a?(Hash)
    end

    def build_store_options
      store_snapshots.flat_map do |snapshot|
        Array(snapshot.data.dig(:distribution, :levels)).filter_map do |raw_level|
          level = raw_level.to_h.with_indifferent_access
          key = store_key(level)
          next unless key

          { key: key, label: "#{level[:platform].to_s.upcase} * #{level[:store_name].presence || "Account##{level[:account_id]}"}" }
        end
      end.uniq { |option| option[:key] }.sort_by { |option| option[:label] }
    end

    def store_dates
      @store_dates ||= (@store_from_date..@store_to_date).to_a
    end

    def store_snapshots
      @store_snapshots ||= @sku.snapshots
        .of_type(Ec::InventorySnapshot.snapshot_type)
        .between(@store_from_date, @store_to_date)
        .order(:snapshot_date)
        .to_a
    end

    def store_snapshots_by_date
      @store_snapshots_by_date ||= store_snapshots.index_by(&:snapshot_date)
    end

    def store_day_row(date, selected_store_key)
      snapshot = store_snapshots_by_date[date]
      return { date: date, missing: true, metrics: {} } unless snapshot && valid_snapshot?(snapshot) && selected_store_key

      levels = Array(snapshot.data.dig(:distribution, :levels)).map { |level| level.to_h.with_indifferent_access }
        .select { |level| store_key(level) == selected_store_key }
      return { date: date, snapshot_date: snapshot.snapshot_date, missing: true, metrics: {} } if levels.empty?

      {
        date: date,
        snapshot_date: snapshot.snapshot_date,
        missing: false,
        metrics: {
          platform_stock: sum_levels(levels, %w[fbo fbw]),
          fbs_stock: sum_levels(levels, %w[fbs]),
          platform_inbound_stock: sum_levels(levels, %w[inbound])
        }
      }
    end

    def store_key(level)
      platform = level[:platform].to_s
      return if platform.blank?

      identity = level[:store_id].present? ? "store:#{level[:store_id]}" : "account:#{level[:account_id]}"
      "#{platform}:#{identity}"
    end

    def metrics(content)
      overview = content.fetch(:overview, {}).with_indifferent_access
      levels = Array(content.dig(:distribution, :levels)).map { |level| level.to_h.with_indifferent_access }
      velocity = decimal(overview[:daily_sales_velocity])
      book_stock = number(overview[:book_stock])
      incoming = number(overview[:incoming_quantity])

      {
        book_stock: book_stock,
        platform_stock: number(overview[:platform_stock]) || sum_levels(levels, %w[fbo fbw]),
        turnover_days_with_procurement: decimal(overview[:turnover_days_with_procurement]) || cover_days(book_stock, incoming, velocity),
        fbs_stock: levels.any? ? sum_levels(levels, %w[fbs]) : nil,
        platform_inbound_stock: number(overview[:platform_inbound_stock]) || sum_levels(levels, %w[inbound]),
        incoming_quantity: incoming,
        daily_sales_velocity: velocity,
        turnover_days: decimal(overview[:turnover_days]) || cover_days(book_stock, 0, velocity)
      }
    end

    def sum_levels(levels, types)
      return nil if levels.empty?

      levels.select { |level| level[:fulfillment_type].to_s.in?(types) }.sum { |level| level[:quantity].to_i }
    end

    def cover_days(stock, extra, velocity)
      return nil unless stock && extra && velocity&.positive?

      (stock.to_d + extra.to_d) / velocity
    end

    def number(value)
      value.nil? ? nil : value.to_i
    end

    def decimal(value)
      value.nil? ? nil : value.to_d
    end

    def at_start_of_day(date)
      @time_zone.local(date.year, date.month, date.day).beginning_of_day
    end

    def week_label(date)
      "#{date.cwyear}-W#{date.cweek.to_s.rjust(2, "0")}"
    end
  end
end
