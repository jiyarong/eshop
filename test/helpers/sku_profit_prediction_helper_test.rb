require "test_helper"

class SkuProfitPredictionHelperTest < ActionView::TestCase
  test "shows ratio inputs as percentages without losing precision and formats amounts to two decimals" do
    assert_equal "7.5", profit_prediction_input_value(0.075.to_d, :commission_rate)
    assert_equal "20", profit_prediction_input_value(0.2.to_d, :import_vat_rate)
    assert_equal "21.69", profit_prediction_input_value(0.2169.to_d, :commission_rate)
    assert_equal "3.1", profit_prediction_input_value(0.031.to_d, :acquiring_rate)
    assert_equal "0", profit_prediction_input_value(0.to_d, :damage_rate)
    assert_equal "265.00", profit_prediction_input_value(265.to_d, :purchase_price_cny)
    assert_nil profit_prediction_input_value(nil, :commission_rate)
  end

  test "labels a funnel pricing scenario with platform, fulfillment and tax regime or market" do
    wb = { "platform" => "wb", "market" => "ru", "delivery_mode" => "fbo", "company_type" => "small" }
    ozon = { "platform" => "ozon", "market" => "by", "delivery_mode" => "fbo", "company_type" => "general" }

    assert_equal "WB / FBW / 小规模", sku_funnel_profit_scenario_label(wb)
    assert_equal "Ozon BY / FBO", sku_funnel_profit_scenario_label(ozon)
    assert_equal I18n.t("reports.sku_detail.funnel_analysis.profit_estimate.uncovered"), sku_funnel_profit_scenario_label(nil)
  end

  test "marks ratio columns, and only those, as percent fields with a unit in their label" do
    assert profit_prediction_percent_field?(:return_rate)
    assert profit_prediction_percent_field?("buyer_price_vat_rate")
    assert_not profit_prediction_percent_field?(:exchange_rate_rub_cny)
    assert_not profit_prediction_percent_field?(:logistics_coeff)
    assert_not profit_prediction_percent_field?(:commission_base_price_rub)
    assert_not profit_prediction_percent_field?(:margin)
  end
end
