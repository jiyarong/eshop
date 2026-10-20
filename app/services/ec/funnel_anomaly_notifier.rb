module Ec
  class FunnelAnomalyNotifier
    MIN_BASELINE_ORDERS = 3
    MIN_VIEWS = 20
    ORDER_DROP = 0.60
    VIEW_DROP = 0.60

    class << self
      def call(observations:, store:, as_of:)
        candidates = Array(observations).filter_map { |observation| anomaly_for(observation) }
        candidates.each { |candidate| notify_sku(candidate, store: store, as_of: as_of) }
        notify_batch(candidates, store: store, as_of: as_of) if candidates.size >= 10
      rescue StandardError => error
        Rails.logger.error("[FunnelAnomalyNotifier] #{error.class}: #{error.message}")
        nil
      end

      private

      def anomaly_for(observation)
        current = observation.fetch(:current).stringify_keys
        baseline = observation.fetch(:baseline).stringify_keys
        current_views = current["views"].to_f
        baseline_views = baseline["views"].to_f
        current_orders = current["orders"].to_f
        baseline_orders = baseline["orders"].to_f
        return unless current_views >= MIN_VIEWS

        order_drop = baseline_orders.positive? ? (baseline_orders - current_orders) / baseline_orders : 0
        view_drop = baseline_views.positive? ? (baseline_views - current_views) / baseline_views : 0
        return unless (baseline_orders >= MIN_BASELINE_ORDERS && order_drop >= ORDER_DROP) || view_drop >= VIEW_DROP

        {
          sku_code: observation.fetch(:sku_code),
          current_views: current_views,
          baseline_views: baseline_views,
          current_orders: current_orders,
          baseline_orders: baseline_orders,
          order_drop_percent: (order_drop * 100).round(1),
          view_drop_percent: (view_drop * 100).round(1)
        }
      end

      def notify_sku(candidate, store:, as_of:)
        sku_code = candidate.fetch(:sku_code)
        from_date = (as_of - 2.days).iso8601
        to_date = as_of.iso8601
        title = I18n.t("notifications.funnel_anomaly.title", sku_code: sku_code)
        body = I18n.t(
          "notifications.funnel_anomaly.body",
          sku_code: sku_code,
          store_name: store.store_name,
          from_date: from_date,
          to_date: to_date,
          current_views: candidate.fetch(:current_views).round,
          baseline_views: candidate.fetch(:baseline_views).round,
          current_orders: candidate.fetch(:current_orders).round,
          baseline_orders: candidate.fetch(:baseline_orders).round,
          order_drop_percent: candidate.fetch(:order_drop_percent),
          view_drop_percent: candidate.fetch(:view_drop_percent)
        )

        Ec::SystemNotificationDispatcher.call(
          notification_type: "funnel_anomaly",
          severity: "critical",
          title: title,
          body: body,
          target_path: Rails.application.routes.url_helpers.report_sku_path(sku_code, tab: "sales_funnel"),
          occurred_at: as_of.end_of_day,
          sku_code: sku_code,
          store: store,
          metadata: candidate.merge(from_date: from_date, to_date: to_date),
          fingerprint: "ozon_funnel_anomaly:#{store.id}:#{sku_code}:#{as_of}"
        )
      end

      def notify_batch(candidates, store:, as_of:)
        sku_codes = candidates.map { |candidate| candidate.fetch(:sku_code) }.uniq
        from_date = (as_of - 2.days).iso8601
        to_date = as_of.iso8601
        title = I18n.t("notifications.funnel_anomaly.batch_title", store_name: store.store_name)
        body = I18n.t("notifications.funnel_anomaly.batch_body", store_name: store.store_name, sku_count: sku_codes.size,
          from_date: from_date, to_date: to_date)

        Ec::SystemNotificationDispatcher.call(
          notification_type: "funnel_anomaly",
          severity: "critical",
          title: title,
          body: body,
          target_path: Rails.application.routes.url_helpers.reports_sales_funnel_path(
            store_ref: "ozon:#{store.ozon_raw_account_id}",
            from_date: from_date,
            to_date: to_date
          ),
          occurred_at: as_of.end_of_day,
          store: store,
          metadata: { "sku_count" => sku_codes.size, "sku_codes" => sku_codes.first(50), "from_date" => from_date, "to_date" => to_date },
          fingerprint: "ozon_funnel_batch_anomaly:#{store.id}:#{as_of}:#{sku_codes.sort.join(',')}"
        )
      end
    end
  end
end
