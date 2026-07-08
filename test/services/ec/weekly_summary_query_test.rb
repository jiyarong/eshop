require "test_helper"

class Ec::WeeklySummaryQueryTest < ActiveSupport::TestCase
  RateStub = Struct.new(:rate_cny_rub, :rate_byn_rub)

  test "run returns wsu payload with shared summary totals and comparison payload" do
    query = Ec::WeeklySummaryQuery.new(
      from_date: Date.new(2026, 5, 25),
      to_date: Date.new(2026, 5, 31),
      rate: RateStub.new(BigDecimal("10"), BigDecimal("5"))
    )

    query.define_singleton_method(:collect_rows) do |_from_date, _to_date, _rate|
      [
        [
          { sku: "SKU-WB", platform: "WB", shop: "WB-1", net_sales: 2, revenue: 50, ads: 5, goods_cost: 15, pre_tax: 20, tax: 2.5, after_tax: 17.5 },
          { sku: "SKU-OZ", platform: "Ozon", shop: "OZ-1", net_sales: 2, revenue: 6, ads: 0.6, goods_cost: 2, pre_tax: 1.8, tax: 0.3, after_tax: 1.5 }
        ],
        { wb: -2.5, ozon: -0.4 }
      ]
    end
    query.define_singleton_method(:previous_rows_data) do
      [[
        { sku: "SKU-WB", platform: "WB", shop: "WB-1", net_sales: 1, revenue: 40, ads: 4, goods_cost: 12, pre_tax: 16, tax: 2, after_tax: 14 }
      ], { wb: -1.0, ozon: 0.0 }]
    end

    payload = query.run

    assert_equal "wsu", payload[:report_type]
    assert_equal "2026-05-25", payload.dig(:period, :from_date)
    assert_equal BigDecimal("10"), payload.dig(:meta, :rates, :rate_cny_rub)
    assert_equal 56, payload.dig(:summary, :total_sales_revenue)
    assert_equal 19.0, payload.dig(:summary, :total_after_tax)
    assert_equal(-2.9, payload.dig(:summary, :unallocated_total))
    assert_equal "SKU-WB", payload.dig(:rows, 0, :sku)
    assert_equal "2026-05-18", payload.dig(:comparison, :period, :from_date)
    assert_equal "2026-05-24", payload.dig(:comparison, :period, :to_date)
    assert_equal 100.0, payload.dig(:comparison, :rows, "SKU-WB|WB|WB-1", :net_sales, :delta_pct)
    assert_equal "positive", payload.dig(:comparison, :rows, "SKU-WB|WB|WB-1", :revenue, :semantic)
    assert_equal "negative", payload.dig(:comparison, :rows, "SKU-WB|WB|WB-1", :ads, :semantic)
    assert_not payload[:rows].first.key?(:previous_net_sales)
    assert_not payload[:rows].first.key?(:sales_change_pct)
  end
end
