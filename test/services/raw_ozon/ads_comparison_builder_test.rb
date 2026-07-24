require "test_helper"

class RawOzonAdsComparisonBuilderTest < ActiveSupport::TestCase
  test "builds metric direction with advertising cost semantics" do
    comparison = RawOzon::Ads::ComparisonBuilder.new.summary(
      { spend: 120, ad_revenue: 300 }, { spend: 100, ad_revenue: 200 },
      metrics: %i[spend ad_revenue]
    )

    assert_equal BigDecimal("20"), comparison.dig(:spend, :delta_pct)
    assert_equal "negative", comparison.dig(:spend, :semantic)
    assert_equal BigDecimal("50"), comparison.dig(:ad_revenue, :delta_pct)
    assert_equal "positive", comparison.dig(:ad_revenue, :semantic)
  end

  test "returns unavailable comparison when the previous row is absent" do
    rows = RawOzon::Ads::ComparisonBuilder.new.rows(
      [{ id: "new", clicks: 10 }], [], key_builder: ->(row) { row[:id] }, metrics: %i[clicks]
    )

    assert_equal "none", rows.dig("new", :clicks, :trend)
    assert_nil rows.dig("new", :clicks, :delta_pct)
  end
end
