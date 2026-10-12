module Ec
  module Inventory
    # Raw platform orders that never reached ec_orders. A non-zero value means sales are missing from the ledger.
    class OrderCompleteness
      def self.call
        {
          wb_marketplace_orders_without_order: RawWb::Order
            .where.not(id: Ec::OrderSourceLink.where(source_type: "RawWb::Order").select(:source_id)).count,
          # Same definition as the WB backfill (srid or g_number not covered by a marketplace order, store mapped).
          wb_stats_orders_without_order: Ec::OrderImport::Wb.new.import_unlinked_stats_only_orders(dry_run: true),
          ozon_postings_without_fulfillment: ozon_postings_without_fulfillment(RawOzon::PostingFbs) +
            ozon_postings_without_fulfillment(RawOzon::PostingFbo)
        }
      end

      # Order items whose platform product is not bound to any internal SKU. Reported next to the completeness
      # counts but deliberately not part of them: these orders exist, they just are not attributable yet.
      def self.unattributed_summary(limit: 10)
        rows = Ec::Inventory::BookLedger.unattributed
        {
          quantity: rows.sum { |row| row[:quantity] },
          products: rows.size,
          top: rows.first(limit)
        }
      end

      def self.ozon_postings_without_fulfillment(model)
        model.where(
          "NOT EXISTS (SELECT 1 FROM ec_order_fulfillments f " \
          "WHERE f.platform = 'ozon' AND f.external_fulfillment_id = #{model.table_name}.posting_number)"
        ).count
      end
      private_class_method :ozon_postings_without_fulfillment
    end
  end
end
