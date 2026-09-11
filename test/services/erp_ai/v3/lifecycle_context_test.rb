require "test_helper"

class ErpAI::V3::LifecycleContextTest < ActiveSupport::TestCase
  test "wraps lifecycle summary and chronological key events" do
    sku = Struct.new(:sku_code).new("LIFE-V3")
    record_class = Struct.new(:source_type, :source_id, :source_key, :sku_product_id)
    first_record = record_class.new("Ec::OrderItem", 11, "first_sale:11", 30)
    second_record = record_class.new("Ec::SkuMarketingState", 12, "marketing_state:12", nil)
    query = Class.new do
      class << self
        attr_accessor :result
      end

      def self.new(*)
        payload = result
        Object.new.tap do |instance|
          instance.define_singleton_method(:call) { payload }
        end
      end
    end
    first_time = Time.zone.parse("2026-07-01 10:00")
    second_time = Time.zone.parse("2026-07-08 10:00")
    query.result = {
      summary: {
        first_sale_at: first_time,
        lifecycle_days: 41,
        current_grade: "A",
        current_stage: "grw",
        net_sales: 12,
        revenue: BigDecimal("320.50"),
        net_profit: BigDecimal("80.25"),
        daily_sales_velocity: BigDecimal("2.4"),
        forecast_explanation: { windows: [] },
        inventory_cover_days: BigDecimal("10.5"),
        stockout_adjusted_daily_sales: BigDecimal("3.1"),
        stockout_adjusted_inventory_cover_days: BigDecimal("8.13"),
        strict_forecast: { forecast_daily_sales: BigDecimal("3.1") }
      },
      sold: true,
      data_started_on: Date.new(2026, 7, 1),
      events: [
        {
          record: first_record,
          id: 1,
          event_type: "first_sale",
          occurred_at: first_time,
          content: { platform: "ozon", quantity: 1 }.with_indifferent_access,
          duration_days: nil,
          details: []
        },
        {
          record: second_record,
          id: 2,
          event_type: "marketing_state_changed",
          occurred_at: second_time,
          content: { to_grade: "A", to_stage: "grw" }.with_indifferent_access,
          duration_days: nil,
          details: []
        }
      ]
    }

    result = ErpAI::V3::LifecycleContext.new(
      sku: sku,
      today: Date.new(2026, 8, 10),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      query: query
    ).call

    summary = result.fetch(:summary)
    assert_equal ErpAI::V3::LifecycleContext::SUMMARY_FIELDS, summary.fetch(:fields)
    assert_equal 41, summary.dig(:values, :lifecycle_days)
    assert_equal BigDecimal("2.4"), summary.dig(:values, :daily_sales_velocity)
    assert_not summary.key?(:forecast_explanation)
    assert_not summary.key?(:strict_forecast)

    key_events = result.fetch(:key_events)
    assert_equal true, key_events.fetch(:sold)
    assert_equal "2026-07-01", key_events.fetch(:data_started_on)
    assert_equal %w[first_sale marketing_state_changed], key_events.fetch(:events).map { |event| event.fetch(:event_type) }
    assert_equal "2026-07-01", key_events.fetch(:events).first.fetch(:occurred_on)
    assert_equal "Ec::OrderItem", key_events.fetch(:events).first.fetch(:source_type)
    assert_equal({ platform: "ozon", quantity: 1 }.with_indifferent_access, key_events.fetch(:events).first.fetch(:content))
  end
end
