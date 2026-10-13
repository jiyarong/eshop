module Ec
  module FulfillmentBusinessStatus
    # Evidence of what happened to a WB order according to the Statistics API. It is the same evidence the order
    # sales distribution uses, because the marketplace status of an order can stay stuck on `waiting`.
    # Per order the strongest evidence wins: return > cancel > sale > order_only.
    class WbStatsEvidence
      PRECEDENCE = %w[return cancel sale order_only].freeze

      def self.for_orders(order_ids)
        order_ids = Array(order_ids).compact.uniq
        return {} if order_ids.empty?

        links = Ec::OrderSourceLink
          .where(order_id: order_ids, source_type: "RawWb::StatsOrder", source_role: "primary")
          .pluck(:order_id, :source_id)
        return {} if links.empty?

        stats_orders = RawWb::StatsOrder.where(id: links.map(&:last)).index_by(&:id)
        srids = stats_orders.values.map(&:srid).compact_blank.uniq
        g_numbers = stats_orders.values.map(&:g_number).compact_blank.uniq
        sales = RawWb::StatsSale.where(is_storno: [ false, nil ])
          .where("srid IN (:srids) OR g_number IN (:g_numbers)", srids: srids, g_numbers: g_numbers).to_a
        sales_by_srid = sales.select { |sale| sale.srid.present? }.group_by { |sale| [ sale.account_id, sale.srid ] }
        sales_by_g_number = sales.select { |sale| sale.g_number.present? }.group_by { |sale| [ sale.account_id, sale.g_number ] }

        links.group_by(&:first).to_h do |order_id, order_links|
          keys = order_links.filter_map do |_order_id, source_id|
            stats_order = stats_orders[source_id]
            next unless stats_order

            matching = []
            matching = sales_by_srid[[ stats_order.account_id, stats_order.srid ]].to_a if stats_order.srid.present?
            if matching.empty? && stats_order.g_number.present?
              matching = sales_by_g_number[[ stats_order.account_id, stats_order.g_number ]].to_a
            end
            evidence_key(stats_order, matching)
          end
          [ order_id, PRECEDENCE.find { |key| keys.include?(key) } ]
        end.compact_blank
      end

      def self.evidence_key(stats_order, sales)
        return "return" if sales.any? { |sale| sale.sale_id.to_s.start_with?("R") }
        return "cancel" if stats_order.is_cancel?
        return "sale" if sales.any? { |sale| !sale.sale_id.to_s.start_with?("R") }

        "order_only"
      end
      private_class_method :evidence_key
    end
  end
end
