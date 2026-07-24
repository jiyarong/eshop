module Ec
  class InventoryPageRowQuery
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze

    def initialize(sku, metrics: nil)
      @sku = sku
      @metrics = metrics || {}
    end

    def call
      summary = @sku.inventory_overview[:summary]
      cost = @sku.cost

      {
        sku_code: @sku.sku_code,
        product_name: @sku.product_name,
        product_name_ru: @sku.product_name_ru,
        marketing_grade: current_marketing_state&.grade,
        marketing_stage: current_marketing_state&.stage,
        incoming_quantity: incoming_quantity,
        book_stock: summary[:book_stock],
        platform_inbound_stock: summary[:platform_inbound_stock],
        platform_stock: summary[:fbo_fbw_stock],
        available_stock: summary[:available_stock],
        pkg_length_cm: cost&.pkg_length_cm,
        pkg_width_cm: cost&.pkg_width_cm,
        pkg_height_cm: cost&.pkg_height_cm,
        unit_volume_l: cost&.pkg_volume_l,
        daily_sales_velocity: @metrics[:daily_sales_velocity],
        turnover_days: @metrics[:turnover_days],
        turnover_days_with_procurement: @metrics[:turnover_days_with_procurement]
      }
    end

    private

    def incoming_quantity
      procurement_batches.sum(Arel.sql(Ec::SkuBatch::EFFECTIVE_RECEIVED_QUANTITY_SQL)).to_i
    end

    def current_marketing_state
      @current_marketing_state ||= @sku.current_marketing_state
    end

    def procurement_batches
      @sku.batches.where(status: INCOMING_STATUSES, batch_type: :normal)
    end
  end
end
