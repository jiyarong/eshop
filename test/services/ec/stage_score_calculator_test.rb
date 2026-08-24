require "test_helper"

class Ec::StageScoreCalculatorTest < ActiveSupport::TestCase
  test "calculates healthy growth from valid weeks and ignores censored weeks" do
    result = calculate([
      week(10, 100, 50), week(12, 130, 60), week(14, 160, 70),
      week(16, 190, 80), week(18, 220, 90), week(20, 250, 100),
      week(0, -10_000, -500, status: "censored_week")
    ])

    assert_equal "GRW", result["diagnosed_stage"]
    assert_equal 6, result["effective_weeks"]
    assert_operator result["g"], :>=, 35
    assert_operator result["q"], :>=, 55
    assert_operator result["c"], :>=, 45
  end

  test "returns no stage when inventory filtering leaves too few standard weeks" do
    result = calculate([ week(10, 100, 50), week(11, 110, 55), week(0, 0, nil, status: "inventory_unknown") ])

    assert_nil result["diagnosed_stage"]
    assert_equal "insufficient_effective_weeks", result["reason"]
    assert_equal 2, result["effective_weeks"]
  end

  test "returns CLR only with sales decline inventory pressure and deterioration" do
    rows = [ 50, 40, 30, 20, 4, 3 ].map.with_index { |sales, index| week(sales, 500 - index * 50, 100 - index * 10) }
    result = calculate(rows, clearance: {
      turnover_days: 200,
      profit_or_ad_deterioration: true,
      sustained_recovery: false
    })

    assert_equal "CLR", result["diagnosed_stage"]
    assert_equal "clearance_recommendation", result.dig("recommended_event", "event_type")
    assert_equal "red", result.dig("recommended_event", "severity")
  end

  private

  def calculate(rows, clearance: {})
    Ec::StageScoreCalculator.call(observations: rows, window_type: "standard", clearance: clearance)
  end

  def week(net_sales, after_tax, annual_return, status: "valid")
    {
      status: status,
      net_sales: net_sales,
      after_tax: after_tax,
      annualized_return_pct: annual_return,
      average_profit_per_order: net_sales.to_f.zero? ? nil : after_tax.to_f / net_sales,
      ad_ratio_pct: 10,
      margin_pct: after_tax.to_f.positive? ? 10 : -10
    }
  end
end
