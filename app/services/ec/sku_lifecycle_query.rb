module Ec
  class SkuLifecycleQuery
    DEFAULT_VISIBLE_EVENT_COUNT = 7

    def initialize(sku, user_today:, time_zone:, visible_event_count: DEFAULT_VISIBLE_EVENT_COUNT)
      @sku = sku
      @user_today = user_today.to_date
      @time_zone = time_zone
      @visible_event_count = [ visible_event_count.to_i, 3 ].max
    end

    def call
      events = @sku.lifecycle_events.includes(:sku_product).chronological.to_a
      first_sale = events.find { |event| event.event_type == "first_sale" }
      {
        summary: build_summary(first_sale),
        events: decorate_events(events),
        timeline_nodes: timeline_nodes(events, first_sale),
        marketing_state_changes: marketing_state_changes(events),
        data_started_on: data_started_on(first_sale),
        sold: first_sale.present?
      }
    end

    private

    def build_summary(first_sale)
      current_state = @sku.current_marketing_state
      inventory = Ec::InventoryTurnoverMetricsQuery.new(
        sku_codes: [ @sku.sku_code ], date_to: @user_today, time_zone: @time_zone
      ).call.fetch(@sku.sku_code, {})
      cumulative = cumulative_metrics(first_sale)
      {
        first_sale_at: first_sale&.occurred_at,
        lifecycle_days: first_sale ? (@user_today - first_sale.occurred_at.in_time_zone(@time_zone).to_date).to_i + 1 : nil,
        current_grade: current_state&.grade,
        current_stage: current_state&.stage,
        net_sales: cumulative[:net_sales],
        revenue: cumulative[:revenue],
        net_profit: cumulative[:net_profit],
        daily_sales_velocity: inventory[:daily_sales_velocity],
        inventory_cover_days: inventory[:turnover_days]
      }
    end

    def cumulative_metrics(first_sale)
      return { net_sales: 0, revenue: nil, net_profit: nil } unless first_sale

      from_date = first_sale.occurred_at.in_time_zone(@time_zone).to_date
      sales = Ec::SkuDailySalesQuery.new(
        sku_codes: [ @sku.sku_code ], from_date:, to_date: @user_today, time_zone: @time_zone
      ).call.values.sum
      profit = cumulative_profit(from_date)
      { net_sales: sales, revenue: profit[:revenue], net_profit: profit[:net_profit] }
    end

    def cumulative_profit(from_date)
      from_monday = from_date.beginning_of_week(:monday)
      to_sunday = @user_today.beginning_of_week(:monday) - 1.day
      return { revenue: nil, net_profit: nil } if to_sunday < from_monday

      report = Ec::WeeklySummaryDeepQuery.run(from_date: from_monday, to_date: to_sunday, sku_codes: [ @sku.sku_code ])
      row = report.fetch(:rows, []).find { |item| (item[:sku] || item["sku"]).to_s == @sku.sku_code }
      {
        revenue: row && (row[:revenue] || row["revenue"]),
        net_profit: row && (row[:after_tax] || row["after_tax"] || row[:net_profit] || row["net_profit"])
      }
    rescue RuntimeError
      { revenue: nil, net_profit: nil }
    end

    def decorate_events(events)
      recoveries = events.select { |event| event.event_type == "stock_recovered" }
        .index_by { |event| event.content["stockout_source_key"] }
      events.map do |event|
        content = event.content.with_indifferent_access
        duration_days = if event.event_type.in?(%w[platform_stockout all_platform_stockout])
          recovered = recoveries[event.source_key]
          end_date = recovered ? Date.iso8601(recovered.content.fetch("recovered_on")) : @user_today
          (end_date - event.occurred_at.in_time_zone(@time_zone).to_date).to_i + (recovered ? 0 : 1)
        end
        { record: event, id: event.id, event_type: event.event_type, occurred_at: event.occurred_at,
          content:, duration_days:, details: event_details(event, content) }
      end
    end

    def event_details(event, content)
      return [] unless event.event_type == "platform_stockout" ||
        (event.event_type == "stock_recovered" && content[:scope] == "platform_store")

      [ { platform: content[:platform], store_id: content[:store_id], store_name: content[:store_name],
          quantity: content[:quantity] } ]
    end

    def timeline_nodes(events, first_sale)
      primary = events.select { |event| primary_timeline_event?(event) }
      anchor = first_sale
      remainder = primary.reject { |event| event == anchor }
      slots = @visible_event_count - 2 # first-sale anchor and current node
      visible = remainder.last(slots)
      hidden = remainder.first(remainder.size - visible.size)
      nodes = []
      nodes << (anchor ? event_node(anchor) : { kind: :unsold })
      nodes << { kind: :collapsed, count: hidden.size, events: hidden } if hidden.any?
      nodes.concat(visible.map { |event| event_node(event) })
      nodes << { kind: :current, occurred_at: @time_zone.local(@user_today.year, @user_today.month, @user_today.day) }
      nodes
    end

    def primary_timeline_event?(event)
      return false if event.event_type == "platform_stockout"
      return event.content["scope"] == "all_platform" if event.event_type == "stock_recovered"

      true
    end

    def event_node(event)
      { kind: :event, event:, event_type: event.event_type, occurred_at: event.occurred_at,
        content: event.content.with_indifferent_access }
    end

    def marketing_state_changes(events)
      changes = events.select { |event| event.event_type == "marketing_state_changed" }
      metrics = marketing_week_metrics(changes)
      users = User.where(id: changes.filter_map { |event| event.content["changed_by_id"] }.uniq).index_by(&:id)
      changes.reverse.map do |event|
        week = previous_complete_week(event.occurred_at)
        content = event.content.with_indifferent_access
        { event:, content:, changed_by: users[content[:changed_by_id].to_i], metrics: metrics[week], week: }
      end
    end

    def marketing_week_metrics(changes)
      changes.map { |event| previous_complete_week(event.occurred_at) }.uniq.index_with do |week|
        report = Ec::WeeklySummaryDeepQuery.run(from_date: week.begin, to_date: week.end, sku_codes: [ @sku.sku_code ])
        row = report.fetch(:rows, []).find { |item| (item[:sku] || item["sku"]).to_s == @sku.sku_code } || {}
        inventory = snapshot_metrics_on(week.end)
        {
          sales: row[:net_sales] || row["net_sales"], revenue: row[:revenue] || row["revenue"],
          profit: row[:after_tax] || row["after_tax"], margin: row[:margin_pct] || row["margin_pct"],
          daily_sales_velocity: inventory[:daily_sales_velocity], inventory_cover_days: inventory[:inventory_cover_days]
        }
      rescue RuntimeError
        {}
      end
    end

    def snapshot_metrics_on(date)
      content = @sku.snapshots.of_type("inventory").find_by(snapshot_date: date)&.data
      return {} unless content

      { daily_sales_velocity: content.dig(:overview, :daily_sales_velocity),
        inventory_cover_days: content.dig(:overview, :turnover_days) }
    end

    def previous_complete_week(time)
      date = time.in_time_zone(@time_zone).to_date
      monday = date.beginning_of_week(:monday) - 1.week
      monday..monday.end_of_week(:monday)
    end

    def data_started_on(first_sale)
      dates = [ first_sale&.occurred_at&.in_time_zone(@time_zone)&.to_date,
        @sku.snapshots.of_type("inventory").minimum(:snapshot_date) ].compact
      dates.max
    end
  end
end
