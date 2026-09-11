require "test_helper"

class ErpAI::V3::ProfitContextTest < ActiveSupport::TestCase
  test "wraps the sku drawer profit analysis into overview and store listing sections" do
    sku = Struct.new(:sku_code).new("PROFIT-V3")
    query = Class.new do
      def self.run(sku:, from_date:, to_date:)
        {
          periods: [
            {
              key: "P-1",
              from_date: Date.new(2026, 7, 27),
              to_date: Date.new(2026, 8, 2),
              sku_row: { net_sales: 3, revenue: BigDecimal("120.50"), after_tax: BigDecimal("20.25") },
              store_rows: []
            },
            {
              key: "P0",
              from_date: from_date,
              to_date: to_date,
              sku_row: { net_sales: 5, revenue: BigDecimal("200.00"), after_tax: BigDecimal("40.00") },
              store_rows: []
            }
          ],
          store_groups: [
            {
              store_ref: "ozon:10",
              store_id: 20,
              sku_product_id: 30,
              platform: "Ozon",
              shop: "Ozon Store",
              listing_label: "Ozon Listing",
              rows_by_period: {
                "P-1" => { net_sales: 1, revenue: BigDecimal("50.00") },
                "P0" => { net_sales: 4, revenue: BigDecimal("180.00"), annualized_net_profit_cny: BigDecimal("3200.00") }
              }
            }
          ]
        }
      end
    end

    result = ErpAI::V3::ProfitContext.new(
      sku: sku,
      period_from: Date.new(2026, 8, 3),
      period_to: Date.new(2026, 8, 9),
      query: query
    ).call

    overview = result.fetch(:sku_profit_overview_per_week)
    assert_includes overview.fetch(:metrics), :net_sales
    assert_includes overview.fetch(:metrics), :annualized_net_profit_cny
    assert_equal %w[P-1 P0], overview.fetch(:periods).map { |period| period.fetch(:period_key) }
    assert_equal BigDecimal("200.00"), overview.fetch(:periods).last.dig(:values, :revenue)
    assert overview.fetch(:periods).last.fetch(:values).key?(:commission_fee)

    listing_section = result.fetch(:sku_profit_store_listing_perweek)
    assert_equal %w[P-1 P0], listing_section.fetch(:periods).map { |period| period.fetch(:period_key) }
    listing = listing_section.fetch(:store_listings).sole
    assert_equal "ozon:10", listing.fetch(:store_ref)
    assert_equal 20, listing.fetch(:store_id)
    assert_equal 30, listing.fetch(:sku_product_id)
    assert_equal "Ozon Listing", listing.fetch(:listing_label)
    assert_equal BigDecimal("3200.00"), listing.fetch(:rows_per_week).last.dig(:values, :annualized_net_profit_cny)
    assert listing.fetch(:rows_per_week).last.fetch(:values).key?(:commission_fee)
  end
end
