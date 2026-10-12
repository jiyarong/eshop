module Ec
  class SkuInventoryOverviewBatchQuery
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze

    def initialize(skus:)
      @skus = skus.to_a
      @sku_codes = @skus.map { |sku| sku.sku_code.to_s.upcase }.uniq
    end

    def call
      return {} if @sku_codes.empty?

      ledger = Ec::Inventory::BookLedger.call(sku_codes: @sku_codes)
      incoming = incoming_quantities
      platform = platform_quantities

      @sku_codes.index_with do |sku_code|
        {
          book_stock: ledger.fetch(sku_code)[:ledger_total],
          platform_stock: platform.fetch(sku_code, 0),
          incoming_quantity: incoming.fetch(sku_code, 0)
        }
      end
    end

    private

    def incoming_quantities
      Ec::SkuBatch.where(sku_code: @sku_codes, status: INCOMING_STATUSES)
        .where.not(batch_type: :physical_stocktake_adjustment)
        .group(:sku_code).sum(Arel.sql(Ec::SkuBatch::EFFECTIVE_RECEIVED_QUANTITY_SQL))
        .transform_keys(&:to_s).transform_values(&:to_i)
    end

    def platform_quantities
      Ec::SkuInventoryLevel.latest
        .where(sku_code: @sku_codes, fulfillment_type: %w[fbo fbw])
        .group(:sku_code).sum(:quantity).transform_keys(&:to_s).transform_values(&:to_i)
    end

  end
end
