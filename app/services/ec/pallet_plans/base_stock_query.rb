module Ec
  module PalletPlans
    # The same own-side book quantity as SkuInventoryOverview, queried for all SKUs at once.
    class BaseStockQuery
      def initialize(sku_codes:, store_id: nil)
        @sku_codes = Array(sku_codes).map { |code| code.to_s.strip.upcase }.reject(&:blank?).uniq
        @store_id = store_id
      end

      def call
        return {} if @sku_codes.empty?

        ledger = Ec::Inventory::BookLedger.call(sku_codes: @sku_codes)
        platform_scope = Ec::SkuInventoryLevel.latest
          .where(sku_code: @sku_codes, fulfillment_type: %w[fbo fbw inbound])
        platform_scope = platform_scope.where(store_id: @store_id) if @store_id.present?
        platform_quantities = platform_scope.group(:sku_code).sum(:quantity)

        @sku_codes.index_with do |sku_code|
          entry = ledger.fetch(sku_code)
          ledger_total = if @store_id.present?
            store_entry = entry.fetch(:by_store, {})[["ozon", @store_id.to_i]]
            entry.fetch(:received_quantity).to_i - store_entry.to_h.fetch(:gross_sales_quantity, 0).to_i +
              store_entry.to_h.fetch(:reversed_quantity, 0).to_i
          else
            entry.fetch(:ledger_total).to_i
          end
          ledger_total - platform_quantities.fetch(sku_code, 0).to_i
        end
      end
    end
  end
end
