module Ec
  module ChartEvents
    class SkuLifecycleEventChartProvider
      def self.call(sku:, from_time:, to_time:, user_time_zone:, level:, store: nil, sku_product: nil)
        level = level.to_sym
        return [] unless %i[sku listing].include?(level)
        return [] if level == :listing && store.blank?

        time_zone = ActiveSupport::TimeZone[user_time_zone.to_s] || ActiveSupport::TimeZone[User::DEFAULT_TIME_ZONE]
        scope = sku.lifecycle_events.includes(:sku_product)
          .where(occurred_at: from_time...to_time).chronological
        scope = scope.where(sku_product_id: sku_product.id) if sku_product

        scope.filter_map do |event|
          event_store_id = event.sku_product&.store_id || event.content.to_h.with_indifferent_access[:store_id]
          listing_visible = event_store_id.present?
          next if level == :listing && event_store_id.to_i != store.id
          next if level == :listing && !listing_visible

          occurred_at = event.occurred_at.in_time_zone(time_zone)
          chart_levels = listing_visible ? %w[sku listing] : %w[sku]
          {
            key: "sku_lifecycle_event:#{event.id}",
            source_type: "sku_lifecycle_event",
            event_type: event.event_type,
            event_type_label: label_for(event.event_type, event.content),
            title: label_for(event.event_type, event.content),
            occurred_at: occurred_at.iso8601,
            event_date: occurred_at.to_date.iso8601,
            chart_levels: chart_levels,
            sku_id: event.sku_id,
            store_id: event_store_id,
            sku_product_id: event.sku_product_id,
            context_label: event.sku_product&.product_name,
            source_label: I18n.t("reports.sku_detail.profit_analysis.events.system"),
            summary: [],
            details: event.content
          }
        end
      end

      def self.label_for(event_type, content = {})
        values = content.to_h.with_indifferent_access
        I18n.t(
          "reports.sku_detail.lifecycle.events.#{event_type}.title",
          default: event_type.to_s.humanize,
          grade: values[:grade],
          amount: values[:threshold_cny]
        )
      end
    end
  end
end
