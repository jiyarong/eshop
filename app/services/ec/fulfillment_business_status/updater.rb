module Ec
  module FulfillmentBusinessStatus
    # Gathers the inputs of one fulfillment from the database, resolves its two business statuses and writes them
    # (plus the order summary). The only place that touches the database for this feature.
    class Updater
      BUSINESS_ROLLUP = %w[
        needs_review awaiting_assembly awaiting_dispatch in_delivery returned delivered cancelled
      ].freeze
      RETURN_ROLLUP = %w[expected at_platform_side returning_to_seller received_by_seller no_physical_return none].freeze
      WB_DISPATCHED_SUPPLIER_STATUS = "complete".freeze

      def self.call(fulfillment, stats_evidence: :load, write: true)
        new(fulfillment, stats_evidence: stats_evidence).call(write: write)
      end

      def self.for_order(order)
        order.fulfillments.reload.each { |fulfillment| call(fulfillment) }
        rollup_order(order)
      end

      def self.rollup_order(order)
        pairs = Ec::OrderFulfillment.where(order_id: order.id).pluck(:business_status, :return_business_status)
        return if pairs.empty?

        business = BUSINESS_ROLLUP.find { |value| pairs.any? { |pair| pair.first == value } } || "needs_review"
        returns = RETURN_ROLLUP.find { |value| pairs.any? { |pair| pair.last == value } } || "none"
        return if order.business_status == business && order.return_business_status == returns

        order.update_columns(business_status: business, return_business_status: returns)
      end

      def initialize(fulfillment, stats_evidence: :load)
        @fulfillment = fulfillment
        @stats_evidence = stats_evidence
      end

      def call(write: true)
        result = resolve
        persist(result) if write
        result
      end

      private

      attr_reader :fulfillment

      def resolve
        Ec::FulfillmentBusinessStatus.resolve(
          platform: fulfillment.platform,
          status: fulfillment.status,
          source_status: fulfillment.source_status,
          source_substatus: fulfillment.source_substatus,
          stats_evidence: stats_evidence,
          returns: return_inputs,
          dispatched: -> { dispatched? }
        )
      end

      def persist(result)
        unless fulfillment.business_status == result.business_status &&
            fulfillment.return_business_status == result.return_business_status
          fulfillment.update_columns(
            business_status: result.business_status, return_business_status: result.return_business_status
          )
        end
        self.class.rollup_order(fulfillment.order)
      end

      def stats_evidence
        return unless fulfillment.platform == "wb"
        return Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders([ fulfillment.order_id ])[fulfillment.order_id] if @stats_evidence == :load

        @stats_evidence
      end

      # Returns that belong to this fulfillment. Every return attaches through exactly one tier, first hit wins:
      # the fulfillment of the order items its return items point at, else the fulfillment of its order whose
      # external id is the return's posting number, else the order's sole fulfillment.
      def return_inputs
        attached_returns.map do |record|
          {
            id: record.id,
            at: record.requested_at || record.created_at,
            source_status: record.source_status,
            process_status: record.process_status,
            returned_to_seller: record.returned_to_seller_at.present?
          }
        end
      end

      def attached_returns
        order_id = fulfillment.order_id
        through_items = Ec::ReturnItem.where(order_item_id: fulfillment.items.select(:id)).select(:return_id)
        candidates = Ec::Return.where(order_id: order_id).or(Ec::Return.where(id: through_items)).to_a
        return [] if candidates.empty?

        item_fulfillment_ids = Ec::ReturnItem
          .where(return_id: candidates.map(&:id))
          .joins("INNER JOIN ec_order_items ON ec_order_items.id = ec_return_items.order_item_id")
          .where.not(ec_order_items: { fulfillment_id: nil })
          .pluck(:return_id, "ec_order_items.fulfillment_id")
          .group_by(&:first).transform_values { |pairs| pairs.map(&:last).uniq }
        order_fulfillments = Ec::OrderFulfillment.where(order_id: order_id).pluck(:id, :external_fulfillment_id)

        candidates.select do |record|
          linked_ids = item_fulfillment_ids[record.id]
          next linked_ids.include?(fulfillment.id) if linked_ids.present?
          next false unless record.order_id == order_id

          posting_ids = order_fulfillments.select { |_id, external_id| external_id == record.external_posting_number }.map(&:first)
          posting_ids = [ order_fulfillments.first.first ] if posting_ids.empty? && order_fulfillments.one?
          posting_ids.include?(fulfillment.id)
        end
      end

      # Evidence that a cancelled fulfillment already left the warehouse.
      def dispatched?
        case fulfillment.platform
        when "wb" then fulfillment.source_substatus == WB_DISPATCHED_SUPPLIER_STATUS || wb_raw_supplier_complete?
        when "ozon" then ozon_handed_to_delivery?
        else false
        end
      end

      def wb_raw_supplier_complete?
        Ec::OrderSourceLink
          .where(order_id: fulfillment.order_id, source_type: "RawWb::Order", source_role: "primary")
          .joins("INNER JOIN raw_wb_orders ON raw_wb_orders.id = ec_order_source_links.source_id")
          .where(raw_wb_orders: { supplier_status: WB_DISPATCHED_SUPPLIER_STATUS })
          .exists?
      end

      def ozon_handed_to_delivery?
        account_id = fulfillment.store.ozon_raw_account_id
        return false if account_id.blank?

        RawOzon::PostingFbs
          .where(account_id: account_id, posting_number: fulfillment.external_fulfillment_id)
          .where.not(delivering_date: nil)
          .exists?
      end
    end
  end
end
