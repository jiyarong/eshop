module Ec
  class InventoryReportRowMetricsBuilder
    def self.call(raw_row, metrics:, cache_updated_at: nil)
      new(raw_row, metrics: metrics, cache_updated_at: cache_updated_at).call
    end

    def initialize(raw_row, metrics:, cache_updated_at:)
      @raw_row = raw_row
      @metrics = metrics || {}
      @cache_updated_at = cache_updated_at
    end

    def call
      daily_sales_velocity = metrics[:daily_sales_velocity]
      book_stock = raw_row[:book_stock].to_d
      procurement_stock = raw_row[:incoming_quantity].to_d
      turnover_days = daily_sales_velocity.to_d.positive? ? (book_stock / daily_sales_velocity.to_d) : nil
      turnover_days_with_procurement = daily_sales_velocity.to_d.positive? ? ((book_stock + procurement_stock) / daily_sales_velocity.to_d) : nil

      raw_row.merge(
        daily_sales_velocity: daily_sales_velocity,
        turnover_days: turnover_days,
        turnover_days_with_procurement: turnover_days_with_procurement,
        cache_updated_at: cache_updated_at
      )
    end

    private

    attr_reader :raw_row, :metrics, :cache_updated_at
  end
end
