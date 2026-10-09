module Ec
  module OrderImport
    # One-off, local-only backfill (no WB API calls) that moves existing WB order items
    # to the platform-neutral price meaning used by Ec::OrderImport::Wb#price_attributes:
    #   unit_price            commission base (Statistics priceWithDisc, RUB)
    #   buyer_paid_unit_price buyer paid price (Statistics finishedPrice, RUB)
    # Items without a Statistics order used to carry the marketplace order's buyer-side
    # price in unit_price; that value is not a commission base, so it is cleared
    # (the original stays in raw_wb_orders and item_payload).
    #
    # Safe by default: it only counts what would change. Pass dry_run: false to write.
    class WbPriceBackfill
      MATCHED = <<~SQL.squish.freeze
        ec_orders o
        JOIN ec_stores st ON st.id = o.store_id
        JOIN raw_wb_stats_orders s ON s.account_id = st.wb_raw_account_id AND s.srid = o.external_order_id
        WHERE i.order_id = o.id AND i.platform = 'wb' AND o.platform = 'wb'
          AND (i.unit_price IS DISTINCT FROM CASE WHEN s.price_with_disc > 0 THEN s.price_with_disc END
            OR i.currency_code IS DISTINCT FROM CASE WHEN s.price_with_disc > 0 THEN 'RUB' END
            OR i.buyer_paid_unit_price IS DISTINCT FROM CASE WHEN s.finished_price > 0 THEN s.finished_price END
            OR i.buyer_currency_code IS DISTINCT FROM CASE WHEN s.finished_price > 0 THEN 'RUB' END
            OR i.buyer_paid_synced_at IS DISTINCT FROM CASE WHEN s.finished_price > 0 THEN s.synced_at END)
      SQL

      UNMATCHED = <<~SQL.squish.freeze
        ec_orders o
        JOIN ec_stores st ON st.id = o.store_id
        WHERE i.order_id = o.id AND i.platform = 'wb' AND o.platform = 'wb'
          AND (i.unit_price IS NOT NULL OR i.currency_code IS NOT NULL)
          AND NOT EXISTS (
            SELECT 1 FROM raw_wb_stats_orders s
            WHERE s.account_id = st.wb_raw_account_id AND s.srid = o.external_order_id
          )
      SQL

      def self.call(dry_run: true, clear_unmatched: true)
        new(dry_run:, clear_unmatched:).call
      end

      def initialize(dry_run:, clear_unmatched:)
        @dry_run = dry_run
        @clear_unmatched = clear_unmatched
      end

      def call
        Ec::OrderItem.transaction do
          { updated: update_matched, cleared: @clear_unmatched ? clear_unmatched : 0 }
        end
      end

      private

      def update_matched
        return count("SELECT COUNT(*) FROM ec_order_items i, #{MATCHED}") if @dry_run

        execute(<<~SQL.squish)
          UPDATE ec_order_items i SET
            unit_price = CASE WHEN s.price_with_disc > 0 THEN s.price_with_disc END,
            currency_code = CASE WHEN s.price_with_disc > 0 THEN 'RUB' END,
            buyer_paid_unit_price = CASE WHEN s.finished_price > 0 THEN s.finished_price END,
            buyer_currency_code = CASE WHEN s.finished_price > 0 THEN 'RUB' END,
            buyer_paid_synced_at = CASE WHEN s.finished_price > 0 THEN s.synced_at END,
            updated_at = NOW()
          FROM #{MATCHED}
        SQL
      end

      def clear_unmatched
        return count("SELECT COUNT(*) FROM ec_order_items i, #{UNMATCHED}") if @dry_run

        execute("UPDATE ec_order_items i SET unit_price = NULL, currency_code = NULL, updated_at = NOW() FROM #{UNMATCHED}")
      end

      def count(sql) = Ec::OrderItem.connection.select_value(sql).to_i
      def execute(sql) = Ec::OrderItem.connection.exec_update(sql)
    end
  end
end
