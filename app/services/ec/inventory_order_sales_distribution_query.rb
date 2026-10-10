module Ec
  class InventoryOrderSalesDistributionQuery
    ORDER_ITEM_JOIN = SalesFunnelReports::SkuFunnelAnalysisQuery::ORDER_ITEM_JOIN
    STATUS_ORDER = %w[
      awaiting_preparation preparing handover_pending platform_received platform_preparing
      awaiting_dispatch carrier_accepted in_transit pickup_ready delivery_postponed
      sold_confirmed delivered_confirmed returned_confirmed returned_to_platform_warehouse
      cancelled_confirmed cancelled_by_wb cancelled_by_customer declined_by_customer
      cancelled_defect carrier_cancelled processing_unconfirmed pending_unconfirmed
      outcome_unknown status_needs_review
    ].freeze
    WB_STATUS_KEYS = {
      "sorted" => "platform_received",
      "ready_for_pickup" => "pickup_ready",
      "sold" => "sold_confirmed",
      "canceled" => "cancelled_by_wb",
      "cancelled" => "cancelled_by_wb",
      "canceled_by_client" => "cancelled_by_customer",
      "declined_by_client" => "declined_by_customer",
      "defect" => "cancelled_defect",
      "postponed_delivery" => "delivery_postponed",
      "accepted_by_carrier" => "carrier_accepted",
      "sent_to_carrier" => "in_transit",
      "canceled_by_carrier" => "carrier_cancelled",
      "returned" => "returned_confirmed"
    }.freeze
    OZON_STATUS_KEYS = {
      "delivered" => "delivered_confirmed",
      "cancelled" => "cancelled_confirmed"
    }.freeze
    OZON_SUBSTATUS_KEYS = {
      "posting_transferred_to_courier_service" => "carrier_accepted",
      "posting_in_carriage" => "in_transit",
      "posting_on_way_to_city" => "in_transit",
      "posting_in_pickup_point" => "pickup_ready",
      "posting_returned_to_warehouse" => "returned_to_platform_warehouse",
      "posting_received" => "delivered_confirmed",
      "posting_delivered" => "delivered_confirmed",
      "posting_canceled" => "cancelled_confirmed"
    }.freeze
    EVIDENCE_STATUS_KEYS = {
      "wb_stats_sale" => "sold_confirmed",
      "wb_stats_return" => "returned_confirmed",
      "wb_stats_cancel" => "cancelled_confirmed"
    }.freeze
    EVIDENCE_EXPECTED_ORDER_STATUSES = {
      "wb_stats_sale" => "delivered",
      "wb_stats_return" => "returned",
      "wb_stats_cancel" => "cancelled"
    }.freeze
    STOCKTAKE_STATUS_KEYS = %w[awaiting_preparation preparing handover_pending].freeze

    def initialize(sku)
      @sku = sku
    end

    def call
      order_rows = order_quantities
      evidence_by_order_id = wb_evidence_by_order_id(order_rows.filter_map { |row| row[1] if row[0].to_s == "wb" })
      grouped_rows = Hash.new(0)

      order_rows.each do |platform, order_id, store_id, store_name, fulfillment_type, order_status,
        fulfillment_status, source_status, source_substatus, quantity|
        type = fulfillment_type_for(platform, fulfillment_type)
        evidence_key = evidence_by_order_id[order_id]
        status_key = status_key(
          platform.to_s, type, order_status, fulfillment_status, source_status, source_substatus, evidence_key
        )
        displayed_evidence_key = displayed_evidence_key(platform.to_s, type, evidence_key)
        needs_status_repair = status_repair_needed?(order_status, evidence_key)
        source_status_label = platform_status_label(platform.to_s, source_status, source_substatus)
        key = [
          platform.to_s, store_id, store_name.to_s, type, status_key, displayed_evidence_key,
          source_status_label, source_status.to_s, source_substatus.to_s, needs_status_repair
        ]
        grouped_rows[key] += quantity.to_i
      end

      rows = grouped_rows.filter_map do |key, quantity|
        next if quantity.zero?

        platform, _store_id, store_name, fulfillment_type, status_key, evidence_key,
          source_status_label, source_status, source_substatus, needs_status_repair = key
        {
          store_label: I18n.t("reports.inventory.drawer.sales_distribution.store_label",
            platform: I18n.t("reports.inventory.drawer.sales_distribution.platforms.#{platform}"), store: store_name),
          platform: platform,
          store_name: store_name,
          fulfillment_type: fulfillment_type,
          status_key: status_key,
          evidence_label: evidence_label(evidence_key),
          source_status_label: source_status_label,
          source_status_codes: [source_status, source_substatus].compact_blank.join(" / "),
          needs_status_repair: needs_status_repair,
          stocktake_relevant: fulfillment_type == "fbs" && status_key.in?(STOCKTAKE_STATUS_KEYS),
          quantity: quantity
        }
      end

      rows.sort_by! do |row|
        [
          row[:platform], row[:store_name], row[:fulfillment_type],
          STATUS_ORDER.index(row[:status_key]) || STATUS_ORDER.length,
          row[:needs_status_repair] ? 0 : 1, row[:source_status_codes]
        ]
      end

      {
        rows: rows,
        summary_row: rows.any? ? { store_label_key: "summary", quantity: rows.sum { |row| row[:quantity] } } : nil
      }
    end

    def source_status_label(platform, source_status, source_substatus)
      platform_status_label(platform.to_s, source_status, source_substatus)
    end

    private

    def order_quantities
      Ec::OrderItem
        .deductible_from_book_inventory
        .joins(:store)
        .joins(ORDER_ITEM_JOIN)
        .where(ec_sku_products: { sku_code: @sku.sku_code })
        .group(
          "ec_order_items.platform", "ec_orders.id", "ec_order_items.store_id", "ec_stores.store_name",
          "ec_order_fulfillments.fulfillment_type", "ec_orders.order_status", "ec_order_fulfillments.status",
          "ec_order_fulfillments.source_status", "ec_order_fulfillments.source_substatus"
        )
        .pluck(
          "ec_order_items.platform", "ec_orders.id", "ec_order_items.store_id", "ec_stores.store_name",
          "ec_order_fulfillments.fulfillment_type", "ec_orders.order_status", "ec_order_fulfillments.status",
          "ec_order_fulfillments.source_status", "ec_order_fulfillments.source_substatus",
          Arel.sql("SUM(ec_order_items.quantity)")
        )
    end

    def wb_evidence_by_order_id(order_ids)
      return {} if order_ids.empty?

      links = Ec::OrderSourceLink
        .where(order_id: order_ids, source_type: "RawWb::StatsOrder", source_role: "primary")
        .pluck(:order_id, :source_id)
      stats_orders = RawWb::StatsOrder.where(id: links.map(&:last)).index_by(&:id)
      sales = relevant_stats_sales(stats_orders.values)
      sales_by_srid = sales.group_by { |sale| [sale.account_id, sale.srid] }
      sales_by_g_number = sales.group_by { |sale| [sale.account_id, sale.g_number] }

      links.group_by(&:first).to_h do |order_id, order_links|
        evidence_keys = order_links.filter_map do |_linked_order_id, source_id|
          stats_order = stats_orders[source_id]
          next unless stats_order

          matching_sales = sales_by_srid[[stats_order.account_id, stats_order.srid]].to_a
          matching_sales = sales_by_g_number[[stats_order.account_id, stats_order.g_number]].to_a if matching_sales.empty?
          stats_evidence_key(stats_order, matching_sales)
        end
        [order_id, strongest_evidence_key(evidence_keys)]
      end
    end

    def relevant_stats_sales(stats_orders)
      return [] if stats_orders.empty?

      base_scope = RawWb::StatsSale
        .where(account_id: stats_orders.map(&:account_id).uniq, is_storno: [false, nil])
      srids = stats_orders.map(&:srid).compact_blank.uniq
      g_numbers = stats_orders.map(&:g_number).compact_blank.uniq
      scopes = []
      scopes << base_scope.where(srid: srids) if srids.any?
      scopes << base_scope.where(g_number: g_numbers) if g_numbers.any?
      return [] if scopes.empty?

      scopes.reduce { |combined, scope| combined.or(scope) }.to_a
    end

    def stats_evidence_key(stats_order, sales)
      return "wb_stats_return" if sales.any? { |sale| sale.sale_id.to_s.start_with?("R") }
      return "wb_stats_cancel" if stats_order.is_cancel?
      return "wb_stats_sale" if sales.any? { |sale| !sale.sale_id.to_s.start_with?("R") }

      "wb_stats_order_only"
    end

    def strongest_evidence_key(keys)
      %w[wb_stats_return wb_stats_cancel wb_stats_sale wb_stats_order_only].find { |key| keys.include?(key) }
    end

    def fulfillment_type_for(platform, type)
      return "fbw" if platform.to_s == "wb" && type.to_s == "fbo"

      type.to_s.presence_in(Ec::OrderFulfillment::FULFILLMENT_TYPES.values) || "unknown"
    end

    def status_key(platform, fulfillment_type, order_status, fulfillment_status, source_status, source_substatus, evidence_key)
      return EVIDENCE_STATUS_KEYS[evidence_key] if EVIDENCE_STATUS_KEYS.key?(evidence_key)
      return "returned_confirmed" if order_status == "returned"
      return platform == "wb" ? "sold_confirmed" : "delivered_confirmed" if order_status == "delivered"
      return "cancelled_confirmed" if order_status == "cancelled"

      if platform == "wb"
        return "outcome_unknown" if fulfillment_type == "fbw"

        return wb_fbs_status_key(source_status, source_substatus, order_status, fulfillment_status)
      end

      return ozon_status_key(fulfillment_type, source_status, source_substatus, order_status, fulfillment_status) if platform == "ozon"

      generic_status_key(order_status, fulfillment_status)
    end

    def wb_fbs_status_key(source_status, source_substatus, order_status, fulfillment_status)
      return WB_STATUS_KEYS[source_status] if WB_STATUS_KEYS.key?(source_status)
      if source_status == "waiting"
        return "handover_pending" if source_substatus == "complete"
        return "preparing" if source_substatus == "confirm"
        return "awaiting_preparation" if source_substatus == "new"
      end
      return "cancelled_confirmed" if source_substatus.in?(%w[cancel cancelled cancel_carrier])

      generic_status_key(order_status, fulfillment_status)
    end

    def ozon_status_key(fulfillment_type, source_status, source_substatus, order_status, fulfillment_status)
      return OZON_SUBSTATUS_KEYS[source_substatus] if OZON_SUBSTATUS_KEYS.key?(source_substatus)
      return OZON_STATUS_KEYS[source_status] if OZON_STATUS_KEYS.key?(source_status)
      if source_status == "awaiting_packaging"
        return fulfillment_type == "fbo" ? "platform_preparing" : "awaiting_preparation"
      end
      if source_status.in?(%w[awaiting_deliver awaiting_delivery])
        return fulfillment_type == "fbo" ? "awaiting_dispatch" : "handover_pending"
      end
      return "in_transit" if source_status.in?(%w[delivering driver_pickup sent_by_seller])

      generic_status_key(order_status, fulfillment_status)
    end

    def generic_status_key(order_status, fulfillment_status)
      return "in_transit" if order_status == "shipped" || fulfillment_status == "shipped"
      return "processing_unconfirmed" if order_status == "processing"
      return "pending_unconfirmed" if order_status == "pending"

      "status_needs_review"
    end

    def displayed_evidence_key(platform, fulfillment_type, evidence_key)
      return unless platform == "wb"
      return evidence_key if fulfillment_type == "fbw"
      return evidence_key if EVIDENCE_STATUS_KEYS.key?(evidence_key)

      nil
    end

    def status_repair_needed?(order_status, evidence_key)
      expected_status = EVIDENCE_EXPECTED_ORDER_STATUSES[evidence_key]
      expected_status.present? && order_status != expected_status
    end

    def evidence_label(evidence_key)
      return if evidence_key.blank?

      I18n.t("reports.inventory.drawer.sales_distribution.evidence.#{evidence_key}")
    end

    def platform_status_label(platform, source_status, source_substatus)
      return if source_status.blank? && source_substatus.blank?

      status_label = translated_status(platform, "status", source_status)
      substatus_label = translated_status(platform, "substatus", source_substatus)
      key = if status_label.present? && substatus_label.present?
        "#{platform}_both"
      elsif status_label.present?
        "#{platform}_status_only"
      else
        "#{platform}_substatus_only"
      end
      I18n.t("reports.inventory.drawer.sales_distribution.source_formats.#{key}",
        status: status_label, substatus: substatus_label)
    end

    def translated_status(platform, type, value)
      return if value.blank?

      I18n.t(
        "reports.inventory.drawer.sales_distribution.raw_statuses.#{platform}.#{type}.#{value}",
        default: I18n.t("reports.inventory.drawer.sales_distribution.unknown_status", code: value)
      )
    end
  end
end
