module Ec
  class SkuPeriodRoiQuery
    ROI_FORMULA = "adjusted_operating_net_profit_cny / cost_base_cny".freeze

    def initialize(sku_code:, from_date:, to_date:, time_zone:)
      @sku_code = sku_code
      @from_date = from_date
      @to_date = to_date
      @time_zone = normalize_time_zone(time_zone)
    end

    def call
      sku = Ec::Sku.find_by!(sku_code: @sku_code)
      breakdown = Ec::SkuPeriodProfitBreakdown.new(
        sku: sku,
        from_date: @from_date,
        to_date: @to_date,
        time_zone: @time_zone
      ).call

      unit_goods_cost_cny = sku.cost&.goods_cost_cny
      unit_volume_l = sku.cost&.pkg_volume_l
      total_bucket = build_bucket(breakdown.fetch(:total), unit_goods_cost_cny, unit_volume_l)
      wb_bucket = build_bucket(breakdown.dig(:platforms, :wb), unit_goods_cost_cny, unit_volume_l)
      ozon_bucket = build_bucket(breakdown.dig(:platforms, :ozon), unit_goods_cost_cny, unit_volume_l)
      missing_cost = total_bucket.fetch(:missing_cost)
      missing_volume = missing_cost ? false : total_bucket.fetch(:missing_volume)
      invalid_date_range = total_bucket.fetch(:invalid_date_range)

      {
        sku_code: sku.sku_code,
        from_date: @from_date,
        to_date: @to_date,
        days_count: days_count,
        unit_goods_cost_cny: unit_goods_cost_cny,
        unit_volume_l: unit_volume_l,
        roi_formula: ROI_FORMULA,
        total: total_bucket.fetch(:payload),
        platforms: {
          wb: wb_bucket.fetch(:payload),
          ozon: ozon_bucket.fetch(:payload)
        },
        missing_cost: missing_cost,
        missing_volume: missing_volume,
        invalid_date_range: invalid_date_range,
        calculable: total_bucket.fetch(:calculable)
      }
    end

    private

    def days_count
      (@to_date - @from_date).to_i + 1
    end

    def build_bucket(bucket, unit_goods_cost_cny, unit_volume_l)
      bucket = bucket.symbolize_keys
      roi_result = projected_roi_result(
        bucket,
        unit_goods_cost_cny: unit_goods_cost_cny,
        unit_volume_l: unit_volume_l
      )

      missing_cost = roi_result.fetch(:missing_cost)
      missing_volume = roi_result.fetch(:missing_volume)
      invalid_date_range = roi_result.fetch(:invalid_date_range)
      non_positive_net_sales = roi_result.fetch(:non_positive_net_sales)

      {
        payload: {
          sales_quantity: bucket.fetch(:sales_quantity),
          return_quantity: bucket.fetch(:return_quantity),
          net_sales_quantity: bucket.fetch(:net_sales_quantity),
          average_daily_net_sales: roi_result.fetch(:average_daily_net_sales),
          projected_stock_qty_180d: roi_result.fetch(:projected_stock_qty_180d),
          average_inventory_qty: roi_result.fetch(:average_inventory_qty),
          projected_months_to_clear: roi_result.fetch(:projected_months_to_clear),
          projected_unit_profit_cny: roi_result.fetch(:projected_unit_profit_cny),
          projected_operating_net_profit_cny: roi_result.fetch(:projected_operating_net_profit_cny),
          predicted_storage_cost_cny: roi_result.fetch(:predicted_storage_cost_cny),
          predicted_interest_cost_cny: roi_result.fetch(:predicted_interest_cost_cny),
          cost_base_cny: roi_result.fetch(:cost_base_cny),
          operating_net_profit_cny: bucket.fetch(:operating_net_profit_cny),
          adjusted_operating_net_profit_cny: roi_result.fetch(:adjusted_operating_net_profit_cny),
          roi: roi_result.fetch(:roi)
        },
        missing_cost: missing_cost,
        missing_volume: missing_volume,
        invalid_date_range: invalid_date_range,
        non_positive_net_sales: non_positive_net_sales,
        calculable: roi_result.fetch(:calculable)
      }
    end

    def normalize_time_zone(value)
      value.is_a?(ActiveSupport::TimeZone) ? value : ActiveSupport::TimeZone[value]
    end

    def projected_roi_result(bucket, unit_goods_cost_cny:, unit_volume_l:)
      Ec::ProjectedStockRoiCalculator.call(
        net_sales_quantity: bucket.fetch(:net_sales_quantity),
        operating_profit_cny: bucket.fetch(:operating_net_profit_cny),
        days_count: days_count,
        unit_goods_cost_cny: unit_goods_cost_cny,
        unit_volume_l: unit_volume_l
      )
    end
  end
end
