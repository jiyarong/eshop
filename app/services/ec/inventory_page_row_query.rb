module Ec
  class InventoryPageRowQuery
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze

    def initialize(sku, metrics: nil)
      @sku = sku
      @metrics = metrics || {}
    end

    def call
      summary = @sku.inventory_overview[:summary]

      {
        sku_code: @sku.sku_code,
        product_name: @sku.product_name,
        product_name_ru: @sku.product_name_ru,
        incoming_quantity: incoming_quantity,
        book_stock: summary[:book_stock],
        platform_stock: summary[:platform_stock],
        available_stock: summary[:available_stock],
        daily_sales_velocity: @metrics[:daily_sales_velocity],
        turnover_days: @metrics[:turnover_days]
      }
    end

    private

    def incoming_quantity
      @sku.batches.where(status: INCOMING_STATUSES).sum(:purchased_quantity).to_i
    end
  end
end
