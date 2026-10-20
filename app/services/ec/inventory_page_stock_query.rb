module Ec
  class InventoryPageStockQuery
    def initialize(sku_codes:)
      @sku_codes = Array(sku_codes).map { |code| code.to_s.upcase }.uniq
    end

    def call
      return {} if @sku_codes.empty?

      ledger = Ec::Inventory::BookLedger.call(sku_codes: @sku_codes)
      incoming = Ec::SkuBatch
        .where(sku_code: @sku_codes, status: Ec::InventoryPageRowQuery::INCOMING_STATUSES, batch_type: :normal)
        .group(:sku_code).sum(Arel.sql(Ec::SkuBatch::EFFECTIVE_RECEIVED_QUANTITY_SQL))
      platform = Ec::SkuInventoryLevel.latest
        .where(sku_code: @sku_codes, fulfillment_type: %w[fbo fbw inbound])
        .group(:sku_code, :fulfillment_type).sum(:quantity)

      @sku_codes.index_with do |sku_code|
        inbound = platform.fetch([ sku_code, "inbound" ], 0).to_i
        sellable = platform.fetch([ sku_code, "fbo" ], 0).to_i + platform.fetch([ sku_code, "fbw" ], 0).to_i
        composed = Ec::Inventory::BookLedger.compose(
          ledger.fetch(sku_code), platform_sellable: sellable, platform_inbound: inbound
        )

        {
          summary: {
            received_quantity: composed[:received_quantity],
            book_stock: composed[:ledger_total],
            platform_inbound_stock: inbound,
            fbo_fbw_stock: sellable,
            available_stock: composed[:own_side]
          },
          incoming_quantity: incoming.fetch(sku_code, 0).to_i
        }
      end
    end
  end
end
