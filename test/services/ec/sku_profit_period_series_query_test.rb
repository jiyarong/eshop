require "test_helper"

class Ec::SkuProfitPeriodSeriesQueryTest < ActiveSupport::TestCase
  setup do
    @sku_code = "SPPS-#{SecureRandom.hex(4).upcase}"
    @sku = Ec::Sku.create!(sku_code: @sku_code, product_name: "Test #{@sku_code}")
    @week_start = Date.new(2026, 5, 25)
    Ec::WeeklyRate.find_or_create_by!(week_start: @week_start) do |rate|
      rate.rate_cny_rub = 10
      rate.rate_byn_rub = 5
    end
  end

  teardown do
    Ec::Sku.where(id: @sku.id).delete_all
  end

  test "call decorates sku_row and store_rows with the same profit metrics shown on the profit overview" do
    sku_code = @sku_code
    query = Ec::SkuProfitPeriodSeriesQuery.new(
      sku: @sku,
      periods: [{ key: "P0", from_date: @week_start, to_date: @week_start.end_of_week(:monday) }]
    )
    query.define_singleton_method(:collect_rows) do |_from_date, _to_date, _rate|
      [
        [{ sku: sku_code, platform: "WB", shop: "WB-1", net_sales: 5, revenue: 100, ads: 10, goods_cost: 30, pre_tax: 40, tax: 5, after_tax: 35 }],
        { wb: 0, ozon: 0 }
      ]
    end

    period = query.call.first
    sku_row = period[:sku_row]
    store_row = period[:store_rows].first

    assert_equal 20.0, sku_row[:average_price]
    assert_equal 30.0, sku_row[:cost_ratio_pct]
    assert_in_delta 35.0, sku_row[:profit_margin_pct].to_f, 0.1

    assert_equal 20.0, store_row[:average_price]
    assert_equal 30.0, store_row[:cost_ratio_pct]
    assert_equal 10.0, store_row[:ad_ratio_pct]
    assert_in_delta(
      35.0, store_row[:profit_margin_pct].to_f, 0.1,
      "店铺维度利润率应和总览一致（历史 bug：decorate_store_row 之前只写了 margin_pct，没写 profit_margin_pct，导致明细表利润率列一直显示 -）"
    )
  end
end
