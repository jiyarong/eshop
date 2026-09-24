require "test_helper"

class SkuProfitPredictionHelperTest < ActionView::TestCase
  test "keeps rate input precision while formatting amounts to two decimals" do
    assert_equal "0.075", profit_prediction_input_value(0.075.to_d, :commission_rate)
    assert_equal "265.00", profit_prediction_input_value(265.to_d, :purchase_price_cny)
  end
end
