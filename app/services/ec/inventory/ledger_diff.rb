module Ec
  module Inventory
    # Release-1 helper: compares the legacy book stock formula with the ledger for the shadow period.
    # Removed together with the legacy scopes once the ledger is the only implementation.
    class LedgerDiff
      def self.call(sku_codes:)
        codes = Array(sku_codes).map { |code| code.to_s.upcase }.uniq
        ledger = Ec::Inventory::BookLedger.call(sku_codes: codes)
        join = Ec::InventoryOrderSalesDistributionQuery::ORDER_ITEM_JOIN
        sold = Ec::OrderItem.deductible_from_book_inventory.joins(join)
          .where(ec_sku_products: { sku_code: codes })
          .group("ec_sku_products.sku_code").sum(:quantity)
        returned = Ec::ReturnItem.restockable_for_book_inventory.joins(:sku_product)
          .where(ec_sku_products: { sku_code: codes })
          .group("ec_sku_products.sku_code").sum(:quantity)

        codes.map do |code|
          entry = ledger.fetch(code)
          legacy = entry[:received_quantity] - sold.fetch(code, 0).to_i + returned.fetch(code, 0).to_i
          {
            sku_code: code,
            legacy: legacy,
            ledger: entry[:ledger_total],
            diff: entry[:ledger_total] - legacy,
            stale_open: entry[:stale_open_order_quantity],
            in_transit: entry[:return_in_transit_quantity],
            at_platform: entry[:return_at_platform_quantity],
            unsellable: entry[:unsellable_quantity]
          }
        end
      end
    end
  end
end
