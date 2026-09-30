module Ec
  class InventoryPageRowQuery
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze

    def initialize(sku, metrics: nil, include_expected_physical_stock: false)
      @sku = sku
      @metrics = metrics || {}
      @include_expected_physical_stock = include_expected_physical_stock
    end

    def call
      overview = @sku.inventory_overview
      summary = overview[:summary]
      cost = @sku.cost
      dimension = @sku.dimension

      row = {
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
        pkg_length_cm: dimension&.inner_length_cm,
        pkg_width_cm: dimension&.inner_width_cm,
        pkg_height_cm: dimension&.inner_height_cm,
        unit_volume_l: unit_volume_l(dimension, cost),
        daily_sales_velocity: @metrics[:daily_sales_velocity],
        turnover_days: @metrics[:turnover_days],
        turnover_days_with_procurement: @metrics[:turnover_days_with_procurement]
      }
      row[:expected_physical_stock] = expected_physical_stock(overview) if @include_expected_physical_stock
      row
    end

    private

    def unit_volume_l(dimension, cost)
      dimensions = [ dimension&.inner_length_cm, dimension&.inner_width_cm, dimension&.inner_height_cm ]
      return dimension.inner_volume_l if dimensions.all?(&:present?)

      cost&.pkg_volume_l
    end

    def incoming_quantity
      procurement_batches.sum(Arel.sql(Ec::SkuBatch::EFFECTIVE_RECEIVED_QUANTITY_SQL)).to_i
    end

    def current_marketing_state
      @current_marketing_state ||= @sku.current_marketing_state
    end

    def expected_physical_stock(overview)
      order_distribution = Ec::InventoryOrderSalesDistributionQuery.new(@sku).call
      Ec::InventoryPhysicalReconciliationQuery.new(
        @sku,
        overview: overview,
        order_distribution: order_distribution
      ).expected_physical_stock
    end

    def procurement_batches
      @sku.batches.where(status: INCOMING_STATUSES, batch_type: :normal)
    end
  end
end
