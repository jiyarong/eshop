require "test_helper"

class Ec::ProfitCalculatorTest < ActiveSupport::TestCase
  TOLERANCE = 0.000001

  test "reconciles WB row 2 from the baseline sheet" do
    result = calculate_wb(
      purchase_price_cny: 210, freight_cny: 22.5, customs_misc_cny: 2.81,
      length_cm: 77, width_cm: 17, height_cm: 7,
      price_rub: 7_000, exchange_rate_rub_cny: 13, logistics_coeff: 1.25,
      fbo_delivery_cny: 10, return_rate: 0.18, storage_cny: 0,
      acquiring_rate: 0.031, advertising_rate: 0.175, damage_rate: 0,
      misc_cny: 2, commission_rate: 0.175, tax_rate: 0.06, other_cny: 0
    )

    assert_reconciles result,
      revenue: 538.4615384615385,
      total_cost: 572.9846716697936,
      profit: -34.52313320825516,
      margin: -0.06411439024390244
    assert_in_delta 9.163, result.dig(:intermediate, :volume_l), TOLERANCE
    assert_equal 10, result.dig(:intermediate, :billed_volume_l)
    assert_in_delta 172, result.dig(:intermediate, :base_logistics_rub), TOLERANCE
    assert_in_delta 21, result.dig(:cost_breakdown, :duty), TOLERANCE
    assert_in_delta 46.2, result.dig(:cost_breakdown, :import_vat), TOLERANCE
  end

  test "reconciles WB row 3 with its own return and advertising rates" do
    result = calculate_wb(
      purchase_price_cny: 270, freight_cny: 22.5, customs_misc_cny: 2.81,
      length_cm: 85, width_cm: 52, height_cm: 5,
      price_rub: 14_700, exchange_rate_rub_cny: 13, logistics_coeff: 1.55,
      fbo_delivery_cny: 0, return_rate: 0.25, storage_cny: 0,
      acquiring_rate: 0.031, advertising_rate: 0.05, damage_rate: 0,
      misc_cny: 2, commission_rate: 0.235, tax_rate: 0.06, other_cny: 0
    )

    assert_reconciles result,
      revenue: 1_130.7692307692307,
      total_cost: 866.4382051282051,
      profit: 264.33102564102564,
      margin: 0.23376213151927438
  end

  test "reconciles WB general company row 3 from the VAT baseline sheet" do
    result = calculate_wb(
      company_type: "general",
      purchase_price_cny: 270, freight_cny: 22.5, customs_misc_cny: 2.81,
      length_cm: 85, width_cm: 52, height_cm: 5,
      price_rub: 15_000, exchange_rate_rub_cny: 13,
      logistics_coeff: 1.55, fbo_delivery_cny: 0,
      return_rate: 0.18, storage_cny: 0,
      acquiring_rate: 0.031, advertising_rate: 0, damage_rate: 0,
      misc_cny: 2, commission_rate: 0.218, sales_vat_rate: 0.2, other_cny: 0
    )

    assert_reconciles result,
      revenue: 1_153.8461538461538,
      total_cost: 858.278105065666,
      profit: 295.5680487804878,
      margin: 0.2561589756097561
    assert_in_delta 60, result.dig(:intermediate, :base_logistics_fee_rub), TOLERANCE
    assert_in_delta 368, result.dig(:intermediate, :base_logistics_rub), TOLERANCE
    assert_in_delta 0.8442776735459662, result.dig(:intermediate, :fixed_return_cny), TOLERANCE
    assert_in_delta 132.9076923076923, result.dig(:cost_breakdown, :tax), TOLERANCE
  end

  test "reconciles Ozon Russia row 2 from the baseline sheet" do
    result = calculate_ozon(
      market: "ru", price_rub: 10_800, purchase_price_cny: 270,
      freight_cny: 22.5, customs_misc_cny: 2.81, exchange_rate_rub_cny: 13,
      length_cm: 85, width_cm: 52, height_cm: 5,
      outbound_logistics_rub: 245, return_logistics_rub: 245,
      warehouse_operation_rub: 25, cross_docking_cny: 61,
      return_rate: 0.2,
      commission_rate: 0.075, acquiring_rate: 0.02,
      advertising_rate: 0.05, other_cny: 0
    )

    assert_reconciles result,
      revenue: 830.7692307692307,
      total_cost: 534.9253846153847,
      profit: 295.843846153846,
      margin: 0.3561083333333332
    assert_in_delta 0.25, result.dig(:intermediate, :return_amortization_factor), TOLERANCE
    assert_in_delta 22.1, result.dig(:intermediate, :volume_l), TOLERANCE
    assert_equal 23, result.dig(:intermediate, :billed_volume_l)
    assert_in_delta 122.5, result.dig(:intermediate, :return_amortized_rub), TOLERANCE
    assert_in_delta 405, result.dig(:intermediate, :platform_logistics_rub), TOLERANCE
  end

  test "reconciles Ozon Belarus row 2 from the baseline sheet" do
    result = calculate_ozon(
      market: "by", price_rub: 10_200, rf_price_rub: 10_800,
      purchase_price_cny: 270, freight_cny: 22.5, customs_misc_cny: 2.81,
      exchange_rate_rub_cny: 13, outbound_logistics_rub: 245,
      return_logistics_rub: 245, warehouse_operation_rub: 25,
      return_rate: 0.2,
      commission_rate: 0.075, acquiring_rate: 0.02,
      advertising_rate: 0.05, other_cny: 0
    )

    assert_reconciles result,
      revenue: 784.6153846153846,
      total_cost: 601.233076923077,
      profit: 183.38230769230768,
      margin: 0.23372254901960784
  end

  test "includes Ozon storage cost for both market scenarios" do
    inputs = {
      price_rub: 10_800, rf_price_rub: 10_800, purchase_price_cny: 270,
      exchange_rate_rub_cny: 13, outbound_logistics_rub: 245,
      return_logistics_rub: 245, warehouse_operation_rub: 25,
      commission_rate: 0.075
    }

    %w[ru by].each do |market|
      without_storage = calculate_ozon(market:, **inputs, storage_cny: 0)
      with_storage = calculate_ozon(market:, **inputs, storage_cny: 12)

      assert_empty with_storage[:errors].to_a
      assert_in_delta 12, with_storage.dig(:cost_breakdown, :storage), TOLERANCE
      assert_in_delta 12, with_storage[:total_cost_cny] - without_storage[:total_cost_cny], TOLERANCE
    end
  end

  test "reconciles Ozon legacy ninth allocation formula" do
    result = calculate_ozon(
      market: "ru", price_rub: 5_800, purchase_price_cny: 420,
      freight_cny: 25, customs_misc_cny: 3, exchange_rate_rub_cny: 12.5,
      outbound_logistics_rub: 635.94, return_logistics_rub: 635.94,
      warehouse_operation_rub: 25, return_rate: 0.1,
      ozon_warehouse_rate: 1.to_d / 9, cross_docking_cny: 8.80909090909091,
      commission_rate: 0.075, acquiring_rate: 0.02,
      advertising_rate: 0, other_cny: 0
    )

    assert_empty result[:errors].to_a
    assert_in_delta 1.to_d / 9, result.dig(:intermediate, :return_amortization_factor), TOLERANCE
    assert_in_delta 141.32, result.dig(:intermediate, :return_amortized_rub), TOLERANCE
    assert_in_delta 807.815555555556, result.dig(:intermediate, :platform_logistics_rub), TOLERANCE
  end

  test "supports Ozon fixed advertising and non-deductible import VAT" do
    result = calculate_ozon(
      market: "ru", price_rub: 299, purchase_price_cny: 8.57,
      freight_cny: 0.26, customs_misc_cny: 0.03, exchange_rate_rub_cny: 12.5,
      outbound_logistics_rub: 27.45, return_logistics_rub: 27.45,
      warehouse_operation_rub: 25, return_rate: 0.1,
      ozon_warehouse_rate: 1.to_d / 9, ozon_import_vat_cost_rate: 1,
      commission_rate: 0.2, acquiring_rate: 0.02, advertising_rate: 0.1,
      advertising_fixed_rub: 6.9, tax_rate: 0.06, other_cny: 0
    )

    assert_empty result[:errors].to_a
    assert_in_delta 1.8854, result.dig(:cost_breakdown, :import_vat), TOLERANCE
    assert_in_delta 2.944, result.dig(:cost_breakdown, :advertising), TOLERANCE
    assert_in_delta 1.4352, result.dig(:cost_breakdown, :tax), TOLERANCE
  end

  test "Ozon derives return amortization from an arbitrary true return rate" do
    result = calculate_ozon(
      market: "ru", price_rub: 1_000, purchase_price_cny: 100,
      exchange_rate_rub_cny: 10, outbound_logistics_rub: 200,
      return_logistics_rub: 100, warehouse_operation_rub: 25,
      return_rate: 0.137, commission_rate: 0.1
    )

    expected_factor = 0.137.to_d / (1 - 0.137.to_d)
    assert_empty result[:errors].to_a
    assert_in_delta expected_factor, result.dig(:intermediate, :return_amortization_factor), TOLERANCE
    assert_in_delta 300 * expected_factor, result.dig(:intermediate, :return_amortized_rub), TOLERANCE
  end

  test "Ozon supports an explicit return amortization factor override" do
    result = calculate_ozon(
      market: "ru", price_rub: 1_000, purchase_price_cny: 100,
      exchange_rate_rub_cny: 10, outbound_logistics_rub: 200,
      return_logistics_rub: 100, warehouse_operation_rub: 25,
      return_rate: 0.1, return_amortization_factor_override: 0.4,
      commission_rate: 0.1
    )

    assert_empty result[:errors].to_a
    assert_in_delta 0.4, result.dig(:intermediate, :return_amortization_factor), TOLERANCE
    assert_in_delta 120, result.dig(:intermediate, :return_amortized_rub), TOLERANCE
  end

  test "Ozon defaults a missing true return rate to ten percent" do
    common_inputs = {
      market: "ru", price_rub: 1_000, purchase_price_cny: 100,
      exchange_rate_rub_cny: 10, outbound_logistics_rub: 200,
      return_logistics_rub: 100, warehouse_operation_rub: 25,
      commission_rate: 0.1
    }

    defaulted = calculate_ozon(**common_inputs)
    explicit = calculate_ozon(**common_inputs, return_rate: 0.1)

    assert_empty defaulted[:errors].to_a
    assert_in_delta 0.1, defaulted.dig(:intermediate, :return_rate), TOLERANCE
    assert_in_delta explicit.dig(:intermediate, :return_amortized_rub), defaulted.dig(:intermediate, :return_amortized_rub), TOLERANCE
    assert_in_delta explicit[:profit_cny], defaulted[:profit_cny], TOLERANCE
  end

  test "Ozon rejects an impossible true return rate before dividing" do
    result = calculate_ozon(
      market: "ru", price_rub: 1_000, purchase_price_cny: 100,
      exchange_rate_rub_cny: 10, outbound_logistics_rub: 200,
      return_logistics_rub: 100, warehouse_operation_rub: 25,
      return_rate: 1, commission_rate: 0.1
    )

    assert_includes result[:errors], "return_rate_must_be_less_than_one"
  end

  test "returns structured validation errors" do
    result = calculate_wb(
      purchase_price_cny: 1, price_rub: 1, exchange_rate_rub_cny: 0,
      length_cm: -1, width_cm: 1, height_cm: 1, logistics_coeff: 1,
      return_rate: 1, commission_rate: 0.1
    )

    assert_includes result[:errors], "exchange_rate_must_be_positive"
    assert_includes result[:errors], "length_cm_must_be_non_negative"
    assert_includes result[:errors], "return_rate_must_be_less_than_one"
  end

  test "rejects spreadsheet error values" do
    result = calculate_ozon(
      market: "ru", price_rub: "#REF!", purchase_price_cny: 270,
      exchange_rate_rub_cny: 13, outbound_logistics_rub: 245,
      return_logistics_rub: 245, warehouse_operation_rub: 25,
      commission_rate: 0.075
    )

    assert_includes result[:errors], "invalid_price_rub"
  end

  test "missing optional costs produce warnings instead of exceptions" do
    result = calculate_wb(
      purchase_price_cny: 210, length_cm: 77, width_cm: 17, height_cm: 7,
      price_rub: 7_000, exchange_rate_rub_cny: 13, logistics_coeff: 1.25,
      return_rate: 0.18, commission_rate: 0.175
    )

    assert_nil result[:errors]
    assert_includes result[:warnings], "acquiring_rate_not_included"
    assert_includes result[:warnings], "advertising_rate_not_included"
    assert result[:total_cost_cny].positive?
  end

  test "defaults a missing WB return rate to ten percent" do
    common_inputs = {
      purchase_price_cny: 100,
      length_cm: 10,
      width_cm: 10,
      height_cm: 10,
      price_rub: 1_000,
      exchange_rate_rub_cny: 10,
      logistics_coeff: 1,
      commission_rate: 0.1
    }

    defaulted = calculate_wb(**common_inputs)
    explicit = calculate_wb(**common_inputs, return_rate: 0.1)

    assert_empty defaulted[:errors].to_a
    assert_in_delta explicit.dig(:cost_breakdown, :returns), defaulted.dig(:cost_breakdown, :returns), TOLERANCE
    assert_in_delta explicit[:total_cost_cny], defaulted[:total_cost_cny], TOLERANCE
    assert_in_delta explicit[:profit_cny], defaulted[:profit_cny], TOLERANCE
  end

  private

  def calculate_wb(inputs)
    company_type = inputs.delete(:company_type) || "small"
    Ec::ProfitCalculator.call(
      platform: :wb,
      parameter_context: { delivery_mode: "fbo", market: "ru", company_type: company_type },
      inputs: inputs
    )
  end

  def calculate_ozon(market:, **inputs)
    Ec::ProfitCalculator.call(platform: :ozon, parameter_context: { delivery_mode: "fbo", market: market }, inputs: inputs)
  end

  def assert_reconciles(result, revenue:, total_cost:, profit:, margin:)
    assert_empty result[:errors].to_a
    assert_in_delta revenue, result[:revenue_cny], TOLERANCE
    assert_in_delta total_cost, result[:total_cost_cny], TOLERANCE
    assert_in_delta profit, result[:profit_cny], TOLERANCE
    assert_in_delta margin, result[:margin], TOLERANCE
    assert_equal "excel_baseline_v4", result[:formula_version]
  end
end
