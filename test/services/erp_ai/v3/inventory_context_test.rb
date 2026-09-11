require "test_helper"

class ErpAI::V3::InventoryContextTest < ActiveSupport::TestCase
  test "wraps current inventory fields using the drawer inventory detail payload" do
    sku = Struct.new(:sku_code) do
      def inventory_levels
        Ec::SkuInventoryLevel.none
      end
    end.new("INV-V3")
    query = Class.new do
      def self.new(*)
        Object.new.tap do |instance|
          instance.define_singleton_method(:call) do
            {
              summary: {
                book_stock: 24,
                fbo_fbw_stock: 6,
                available_stock: 14
              },
              incoming_quantity: 5,
              daily_sales_velocity: BigDecimal("3.2"),
              turnover_days: BigDecimal("7.5"),
              turnover_days_with_procurement: BigDecimal("9.06"),
              fbs_stock: 8,
              forecast_explanation: { windows: [] },
              strict_forecast: {
                forecast_daily_sales: BigDecimal("2.4"),
                cover_days: BigDecimal("10.0"),
                calculation: { path: "weighted_recent_sales" }
              },
              platform_breakdown: [
                {
                  fulfillment_type: "fbs",
                  quantity: 8,
                  metadata: { "raw_fbs_quantity" => 11 },
                  latest_synced_at: Time.zone.parse("2026-08-09 10:00")
                }
              ]
            }
          end
        end
      end
    end
    trend_query = Class.new do
      class << self
        attr_accessor :calls
      end
      self.calls = []

      def self.new(sku, to_date:, time_zone:)
        calls << { sku: sku, to_date: to_date, time_zone: time_zone }
        Object.new.tap do |instance|
          instance.define_singleton_method(:call) do
            {
              sku_code: sku.sku_code,
              weeks: [
                {
                  week_start: Date.new(2026, 8, 3),
                  week_end: Date.new(2026, 8, 9),
                  snapshot_date: Date.new(2026, 8, 9),
                  is_week_end: true,
                  missing: false,
                  metrics: {
                    book_stock: 24,
                    platform_stock: 6,
                    fbs_stock: 8,
                    daily_sales_velocity: BigDecimal("3.2")
                  }
                }
              ],
              available_metrics: %i[book_stock platform_stock fbs_stock daily_sales_velocity],
              operation_events: [{ event_date: "2026-08-09", event_type: "manual_note" }],
              store_from_date: Date.new(2026, 7, 14),
              store_to_date: Date.new(2026, 8, 10),
              selected_store_key: "ozon:store:20",
              store_options: [{ key: "ozon:store:20", label: "OZON * Store" }],
              store_trends: [
                {
                  key: "ozon:store:20",
                  label: "OZON * Store",
                  days: [
                    {
                      date: Date.new(2026, 8, 9),
                      snapshot_date: Date.new(2026, 8, 9),
                      missing: false,
                      metrics: { platform_stock: 6, fbs_stock: 8, platform_inbound_stock: 2 }
                    }
                  ]
                }
              ]
            }
          end
        end
      end
    end
    time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]

    result = ErpAI::V3::InventoryContext.new(
      sku: sku,
      today: Date.new(2026, 8, 10),
      time_zone: time_zone,
      detail_query: query,
      trend_query: trend_query
    ).call

    current = result.fetch(:current_inventory_info)
    assert_equal ErpAI::V3::InventoryContext::CURRENT_INVENTORY_FIELDS, current.fetch(:fields)
    assert_equal(
      {
        incoming_quantity: 5,
        book_stock: 24,
        platform_stock: 6,
        fbs_total_stock: 14,
        daily_sales_velocity: BigDecimal("3.2"),
        turnover_days: BigDecimal("7.5"),
        turnover_days_with_procurement: BigDecimal("9.06"),
        platform_fbs_stock: 8,
        platform_reported_fbs_stock: 11,
        strict_forecast_daily_sales: BigDecimal("2.4"),
        strict_forecast_cover_days: BigDecimal("10.0")
      },
      current.fetch(:values)
    )
    assert_equal({ windows: [] }, current.fetch(:forecast_explanation))
    assert_equal "weighted_recent_sales", current.dig(:strict_forecast, :calculation, :path)
    assert_equal Time.zone.parse("2026-08-09 10:00"), current.fetch(:data_through)

    assert_equal [{ sku: sku, to_date: Date.new(2026, 8, 10), time_zone: time_zone }], trend_query.calls
    history = result.fetch(:history_inventory_info)
    total_trend = history.fetch(:sku_inventory_trend)
    assert_equal Ec::SkuInventoryTrendQuery::METRICS, total_trend.fetch(:metrics)
    assert_equal %i[book_stock platform_stock fbs_stock daily_sales_velocity], total_trend.fetch(:available_metrics)
    assert_equal Date.new(2026, 8, 9).iso8601, total_trend.fetch(:weeks).sole.fetch(:snapshot_date)
    assert_equal BigDecimal("3.2"), total_trend.fetch(:weeks).sole.dig(:values, :daily_sales_velocity)
    assert total_trend.fetch(:weeks).sole.fetch(:values).key?(:turnover_days_with_procurement)
    assert_not total_trend.key?(:operation_events)

    store_trend = history.fetch(:store_listing_inventory_trend)
    assert_equal %i[platform_stock fbs_stock platform_inbound_stock], store_trend.fetch(:metrics)
    assert_equal "2026-07-14", store_trend.fetch(:from_date)
    assert_equal "2026-08-10", store_trend.fetch(:to_date)
    assert_equal "ozon:store:20", store_trend.fetch(:selected_store_key)
    assert_equal [{ key: "ozon:store:20", label: "OZON * Store" }], store_trend.fetch(:store_options)
    listing = store_trend.fetch(:store_listings).sole
    assert_equal "ozon:store:20", listing.fetch(:store_key)
    assert_equal "OZON * Store", listing.fetch(:store_label)
    assert_equal 8, listing.fetch(:days).sole.dig(:values, :fbs_stock)
    assert listing.fetch(:days).sole.fetch(:values).key?(:platform_inbound_stock)
  end
end
