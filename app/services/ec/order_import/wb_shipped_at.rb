module Ec
  module OrderImport
    # The shipment time of a WB FBS order is the close time of the supply it was handed over in
    # (PATCH /supplies/{id}/deliver). An order that sits in several supplies (re-shipment) keeps the first one.
    #
    # A cancelled order stays in its supply, so the link alone cannot tell a cancellation before the hand-over
    # from one after it. Orders cancelled by the seller or the buyer (supplier_status cancel, wb_status
    # canceled / canceled_by_client) only count as shipped when the statistics cancel_date is later than the
    # supply close time; an earlier or unknown cancel time leaves shipped_at empty. declined_by_client and defect
    # can only happen once WB holds the goods, so they keep the supply close time.
    #
    # Idempotent and re-evaluated on every call: shipped_at is set or cleared as the evidence changes.
    class WbShippedAt
      def self.call(account_id: nil)
        new(account_id: account_id).call
      end

      def initialize(account_id: nil)
        @account_id = account_id
      end

      def call
        ActiveRecord::Base.connection.exec_update(<<~SQL.squish)
          UPDATE ec_order_fulfillments AS fulfillment
          SET shipped_at = shipments.shipped_at,
              updated_at = NOW()
          FROM (
            SELECT first_supply.raw_order_id,
              CASE
                WHEN NOT (raw_orders.supplier_status = 'cancel' OR raw_orders.wb_status IN ('canceled', 'canceled_by_client'))
                  THEN first_supply.closed_at
                WHEN stats_orders.is_cancel AND stats_orders.cancel_date > first_supply.closed_at
                  THEN first_supply.closed_at
              END AS shipped_at
            FROM (
              SELECT supply_orders.order_id AS raw_order_id, MIN(supplies.closed_at) AS closed_at
              FROM raw_wb_supply_orders AS supply_orders
              INNER JOIN raw_wb_supplies AS supplies ON supplies.id = supply_orders.supply_id
              WHERE supplies.closed_at IS NOT NULL#{account_condition}
              GROUP BY supply_orders.order_id
            ) AS first_supply
            INNER JOIN raw_wb_orders AS raw_orders ON raw_orders.id = first_supply.raw_order_id
            LEFT JOIN raw_wb_stats_orders AS stats_orders
              ON stats_orders.account_id = raw_orders.account_id AND stats_orders.srid = raw_orders.srid
          ) AS shipments
          WHERE fulfillment.platform = 'wb'
            AND fulfillment.fulfillment_type = 'fbs'
            AND fulfillment.raw_source_type = 'RawWb::Order'
            AND fulfillment.raw_source_id = shipments.raw_order_id
            AND fulfillment.shipped_at IS DISTINCT FROM shipments.shipped_at
        SQL
      end

      private

      def account_condition
        " AND supplies.account_id = #{@account_id.to_i}" if @account_id
      end
    end
  end
end
