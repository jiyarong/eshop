module Ec
  class SkuInventoryOverviewBatchQuery
    RECEIVED_STATUSES = %w[received closed].freeze
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze
    ORDER_ITEM_JOIN = SalesFunnelReports::SkuFunnelAnalysisQuery::ORDER_ITEM_JOIN

    def initialize(skus:)
      @skus = skus.to_a
      @sku_codes = @skus.map { |sku| sku.sku_code.to_s.upcase }.uniq
    end

    def call
      return {} if @sku_codes.empty?

      received = received_quantities
      sold = sales_quantities
      returned = return_quantities
      incoming = incoming_quantities
      platform = platform_quantities

      @sku_codes.index_with do |sku_code|
        book_stock = received.fetch(sku_code, 0) - sold.fetch(sku_code, 0) + returned.fetch(sku_code, 0)
        {
          book_stock:,
          platform_stock: platform.fetch(sku_code, 0),
          incoming_quantity: incoming.fetch(sku_code, 0)
        }
      end
    end

    private

    def received_quantities
      Ec::SkuBatch.where(sku_code: @sku_codes, status: RECEIVED_STATUSES)
        .where.not(batch_type: :physical_stocktake_adjustment)
        .group(:sku_code).sum(:received_quantity).transform_keys(&:to_s).transform_values(&:to_i)
    end

    def incoming_quantities
      Ec::SkuBatch.where(sku_code: @sku_codes, status: INCOMING_STATUSES)
        .where.not(batch_type: :physical_stocktake_adjustment)
        .group(:sku_code).sum(Arel.sql(Ec::SkuBatch::EFFECTIVE_RECEIVED_QUANTITY_SQL))
        .transform_keys(&:to_s).transform_values(&:to_i)
    end

    def sales_quantities
      Ec::OrderItem.deductible_from_book_inventory.joins(ORDER_ITEM_JOIN)
        .where(ec_sku_products: { sku_code: @sku_codes })
        .group("ec_sku_products.sku_code").sum(:quantity)
        .transform_keys(&:to_s).transform_values(&:to_i)
    end

    def return_quantities
      Ec::ReturnItem.restockable_for_book_inventory.joins(:sku_product)
        .where(ec_sku_products: { sku_code: @sku_codes })
        .group("ec_sku_products.sku_code").sum(:quantity)
        .transform_keys(&:to_s).transform_values(&:to_i)
    end

    def platform_quantities
      Ec::SkuInventoryLevel.latest
        .where(sku_code: @sku_codes, fulfillment_type: %w[fbo fbw])
        .group(:sku_code).sum(:quantity).transform_keys(&:to_s).transform_values(&:to_i)
    end

  end
end
