module Ec
  class PriceAnomalyNotifier
    MIN_ABSOLUTE_CHANGE = 500.0
    MIN_RELATIVE_CHANGE = 0.20
    BATCH_SIZE = 10

    class << self
      def call(actions:, store:)
        candidates = Array(actions).filter_map { |action| anomaly_for(action) }
        candidates.each { |candidate| notify_sku(candidate) }
        notify_batch(candidates, store: store) if candidates.size >= BATCH_SIZE
      rescue StandardError => error
        Rails.logger.error("[PriceAnomalyNotifier] #{error.class}: #{error.message}")
        nil
      end

      private

      def anomaly_for(action)
        fields = action.diff_result.to_h.fetch("fields", {})
        field = %w[marketing_price price].find { |name| fields[name].is_a?(Hash) }
        return unless field

        change = fields.fetch(field)
        before = change["from"].to_f
        after = change["to"].to_f
        return unless before.positive? && after > before

        absolute_change = after - before
        relative_change = absolute_change / before
        return unless absolute_change >= MIN_ABSOLUTE_CHANGE && relative_change >= MIN_RELATIVE_CHANGE

        {
          action: action,
          field: field,
          before: before,
          after: after,
          absolute_change: absolute_change,
          relative_change: relative_change,
          sku_code: action.sku.sku_code,
          store: action.store
        }
      end

      def notify_sku(candidate)
        action = candidate.fetch(:action)
        store = candidate.fetch(:store)
        sku_code = candidate.fetch(:sku_code)
        percent = (candidate.fetch(:relative_change) * 100).round(1)
        title = I18n.t("notifications.price_anomaly.title", sku_code: sku_code)
        body = I18n.t(
          "notifications.price_anomaly.body",
          sku_code: sku_code,
          store_name: store.store_name,
          field: I18n.t("notifications.price_anomaly.fields.#{candidate.fetch(:field)}"),
          before_price: format_price(candidate.fetch(:before)),
          after_price: format_price(candidate.fetch(:after)),
          change_percent: percent
        )

        Ec::SystemNotificationDispatcher.call(
          notification_type: "price_anomaly",
          severity: candidate.fetch(:relative_change) >= 0.30 ? "critical" : "warning",
          title: title,
          body: body,
          target_path: Rails.application.routes.url_helpers.report_sku_path(
            sku_code,
            tab: "operation_actions"
          ),
          occurred_at: action.operated_at,
          sku_code: sku_code,
          store: store,
          source: action,
          metadata: {
            "field" => candidate.fetch(:field),
            "before" => candidate.fetch(:before),
            "after" => candidate.fetch(:after),
            "change_percent" => percent
          },
          fingerprint: "ozon_price_anomaly:#{store.id}:#{sku_code}:#{candidate.fetch(:field)}:#{candidate.fetch(:before)}:#{candidate.fetch(:after)}"
        )
      end

      def notify_batch(candidates, store:)
        sku_codes = candidates.map { |candidate| candidate.fetch(:sku_code) }.uniq
        median_percent = candidates.map { |candidate| candidate.fetch(:relative_change) * 100 }.sort
        median_percent = median_percent[median_percent.length / 2].round(1)
        title = I18n.t("notifications.price_anomaly.batch_title", store_name: store.store_name)
        body = I18n.t(
          "notifications.price_anomaly.batch_body",
          store_name: store.store_name,
          sku_count: sku_codes.size,
          median_change_percent: median_percent
        )

        Ec::SystemNotificationDispatcher.call(
          notification_type: "price_anomaly",
          severity: "critical",
          title: title,
          body: body,
          target_path: Rails.application.routes.url_helpers.reports_sales_funnel_path(
            store_ref: "ozon:#{store.ozon_raw_account_id}"
          ),
          occurred_at: candidates.map { |candidate| candidate.fetch(:action).operated_at }.max,
          store: store,
          metadata: {
            "sku_count" => sku_codes.size,
            "sku_codes" => sku_codes.first(50),
            "median_change_percent" => median_percent
          },
          fingerprint: "ozon_price_batch_anomaly:#{store.id}:#{candidates.map { |candidate| candidate.fetch(:action).id }.sort.join(',')}"
        )
      end

      def format_price(value)
        format("%.2f", value).sub(/\.00\z/, "")
      end
    end
  end
end
