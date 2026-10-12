module Ec
  class InventoryTurnoverMetricsQuery
    def initialize(sku_codes:, date_to:, time_zone:)
      @sku_codes = Array(sku_codes).map(&:to_s).map(&:upcase).uniq
      @date_to = date_to
      @time_zone = time_zone
    end

    def call
      return {} if @sku_codes.empty?

      velocity_metrics = Ec::InventoryVelocityMetricsQuery.new(
        sku_codes: @sku_codes,
        date_to: @date_to,
        time_zone: @time_zone
      ).call

      ledger = Ec::Inventory::BookLedger.call(sku_codes: @sku_codes, as_of: cutoff_time)
      procurement_quantities = procurement_quantities_by_sku

      @sku_codes.index_with do |sku_code|
        daily_sales_velocity = velocity_metrics.dig(sku_code, :daily_sales_velocity)
        book_stock = ledger.fetch(sku_code)[:ledger_total]
        procurement_stock = procurement_quantities.fetch(sku_code, 0)

        {
          book_stock: book_stock,
          procurement_stock: procurement_stock,
          daily_sales_velocity: daily_sales_velocity,
          forecast_explanation: velocity_metrics.dig(sku_code, :forecast_explanation),
          turnover_days: daily_sales_velocity.to_d.positive? ? (book_stock.to_d / daily_sales_velocity.to_d) : nil,
          turnover_days_with_procurement: daily_sales_velocity.to_d.positive? ? ((book_stock + procurement_stock).to_d / daily_sales_velocity.to_d) : nil
        }
      end
    end

    private

    def procurement_quantities_by_sku
      Ec::SkuBatch
        .where(sku_code: @sku_codes, status: %w[draft ordered in_transit], batch_type: :normal)
        .where(
          "ec_sku_batches.purchase_date <= :date OR " \
          "(ec_sku_batches.purchase_date IS NULL AND ec_sku_batches.created_at <= :cutoff)",
          date: @date_to,
          cutoff: cutoff_time
        )
        .group(:sku_code)
        .sum(Arel.sql(Ec::SkuBatch::EFFECTIVE_RECEIVED_QUANTITY_SQL))
        .transform_keys(&:to_s)
        .transform_values(&:to_i)
    end

    def cutoff_time
      @cutoff_time ||= @time_zone.local(@date_to.year, @date_to.month, @date_to.day).end_of_day
    end
  end
end
