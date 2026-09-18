require "test_helper"

class ErpAI::V3::BaseContextTest < ActiveSupport::TestCase
  test "returns the last twelve completed weekly net sales values from profit aggregation" do
    sku_products = Object.new
    sku_products.define_singleton_method(:order) { |_field| [] }
    sku = Struct.new(:master_sku, :master_sku_id, :current_marketing_state, :sku_products).new(
      nil, nil, nil, sku_products
    )
    query = Class.new do
      class << self
        attr_accessor :periods
      end

      def self.run(sku:, periods:)
        self.periods = periods
        periods.map.with_index do |period, index|
          period.merge(sku_row: { net_sales: index + 10 })
        end
      end
    end

    result = ErpAI::V3::BaseContext.new(
      sku: sku,
      period_to: Date.new(2026, 8, 9),
      profit_query: query
    ).call

    assert_equal(
      {
        "2026-05-18" => 10,
        "2026-05-25" => 11,
        "2026-06-01" => 12,
        "2026-06-08" => 13,
        "2026-06-15" => 14,
        "2026-06-22" => 15,
        "2026-06-29" => 16,
        "2026-07-06" => 17,
        "2026-07-13" => 18,
        "2026-07-20" => 19,
        "2026-07-27" => 20,
        "2026-08-03" => 21
      },
      result.fetch(:sales_amount_last_3_months)
    )
    assert_equal Date.new(2026, 5, 18), query.periods.first.fetch(:from_date)
    assert_equal Date.new(2026, 8, 9), query.periods.last.fetch(:to_date)
  end

  test "fills a missing profit aggregation week with zero" do
    sku_products = Object.new
    sku_products.define_singleton_method(:order) { |_field| [] }
    sku = Struct.new(:master_sku, :master_sku_id, :current_marketing_state, :sku_products).new(
      nil, nil, nil, sku_products
    )
    query = Class.new do
      def self.run(sku:, periods:)
        periods.first(11).map { |period| period.merge(sku_row: { net_sales: 3 }) }
      end
    end

    result = ErpAI::V3::BaseContext.new(
      sku: sku,
      period_to: Date.new(2026, 8, 9),
      profit_query: query
    ).call

    assert_equal 3, result.dig(:sales_amount_last_3_months, "2026-07-27")
    assert_equal 0, result.dig(:sales_amount_last_3_months, "2026-08-03")
  end
end
