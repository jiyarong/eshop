require "test_helper"

class Ec::SkuProfitCalculatorTest < ActiveSupport::TestCase
  setup do
    @sku = Ec::Sku.create!(sku_code: "CALC-#{SecureRandom.hex(5).upcase}", product_name: "Calculator test", is_active: true)
    Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      effective_on: Date.new(2026, 1, 1),
      purchase_price_cny: 210,
      freight_to_by_cny: 22.5,
      customs_misc_cny: 2.81,
      customs_duty_rate: 0.1,
      import_vat_rate: 0.2,
      pkg_length_cm: 77,
      pkg_width_cm: 17,
      pkg_height_cm: 7
    )
    Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      effective_on: Date.new(2026, 7, 1),
      purchase_price_cny: 999
    )
  end

  teardown do
    cost_ids = Ec::SkuCost.where(sku_code: @sku&.sku_code).pluck(:id)
    dimension_ids = Ec::SkuDimension.where(sku_code: @sku&.sku_code).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuCost", record_id: cost_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuDimension", record_id: dimension_ids).delete_all
    Ec::SkuCost.where(id: cost_ids).delete_all
    Ec::SkuDimension.where(id: dimension_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku&.id).delete_all
    Ec::Sku.where(id: @sku&.id).delete_all
  end

  test "call can calculate without a controller and uses cost effective on the requested date" do
    result = Ec::SkuProfitCalculator.call(
      sku: @sku,
      platform: "wb",
      parameter_context: { market: "ru", delivery_mode: "fbo", company_type: "small" },
      effective_on: Date.new(2026, 3, 1),
      inputs: {
        price_rub: 7_000,
        exchange_rate_rub_cny: 13,
        logistics_coeff: 1.25,
        fbo_delivery_cny: 10,
        return_rate: 0.18,
        storage_cny: 0,
        acquiring_rate: 0.031,
        advertising_rate: 0.175,
        damage_rate: 0,
        misc_cny: 2,
        commission_rate: 0.175,
        tax_rate: 0.06,
        other_cny: 0
      }
    )

    assert_empty result[:errors].to_a
    assert_in_delta 572.9846716697936, result[:total_cost_cny], 0.000001
    assert_in_delta(-34.52313320825516, result[:profit_cny], 0.000001)
  end

  test "provides persisted defaults for each standard scenario" do
    wb_general = Ec::SkuProfitCalculator.default_inputs(
      platform: "wb",
      parameter_context: { market: "ru", delivery_mode: "fbo", company_type: "general" }
    )
    wb_small_fbo = Ec::SkuProfitCalculator.default_inputs(
      platform: "wb",
      parameter_context: { market: "ru", delivery_mode: "fbo", company_type: "small" }
    )
    wb_small_fbs = Ec::SkuProfitCalculator.default_inputs(
      platform: "wb",
      parameter_context: { market: "ru", delivery_mode: "fbs", company_type: "small" }
    )
    ozon_ru = Ec::SkuProfitCalculator.default_inputs(
      platform: "ozon",
      parameter_context: { market: "ru", delivery_mode: "fbo", company_type: "general" }
    )
    ozon_by = Ec::SkuProfitCalculator.default_inputs(
      platform: "ozon",
      parameter_context: { market: "by", delivery_mode: "fbo", company_type: "general" }
    )

    assert_equal 13.to_d, wb_general.fetch("exchange_rate_rub_cny")
    assert_equal 0.1.to_d, wb_general.fetch("return_rate")
    assert_equal 1.55.to_d, wb_general.fetch("logistics_coeff")
    assert_equal 0.015.to_d, wb_general.fetch("acquiring_rate")
    assert_equal 60.to_d, wb_general.fetch("wb_logistics_base_rub")
    assert_equal 50.to_d, wb_general.fetch("wb_fixed_return_base_rub")
    assert_equal 0.2.to_d, wb_general.fetch("sales_vat_rate")
    assert_equal 2.to_d, wb_general.fetch("misc_cny")

    assert_equal 1.3.to_d, wb_small_fbo.fetch("logistics_coeff")
    assert_equal 1.55.to_d, wb_small_fbs.fetch("logistics_coeff")
    assert_equal 0.1.to_d, wb_small_fbo.fetch("return_rate")
    assert_equal 0.031.to_d, wb_small_fbo.fetch("acquiring_rate")
    assert_equal 46.to_d, wb_small_fbo.fetch("wb_logistics_base_rub")
    assert_equal 0.06.to_d, wb_small_fbo.fetch("tax_rate")

    assert_equal 13.to_d, ozon_ru.fetch("exchange_rate_rub_cny")
    assert_equal 0.1.to_d, ozon_ru.fetch("return_rate")
    assert_equal 0.02.to_d, ozon_ru.fetch("acquiring_rate")
    assert_equal 25.to_d, ozon_ru.fetch("warehouse_operation_rub")
    assert_equal 0.25.to_d, ozon_ru.fetch("ozon_warehouse_rate")
    assert_equal 0.to_d, ozon_ru.fetch("cross_docking_cny")
    assert_equal 0.2.to_d, ozon_by.fetch("sales_vat_rate")
  end

  test "call applies WB scenario defaults without a controller" do
    result = Ec::SkuProfitCalculator.call(
      sku: @sku,
      platform: "wb",
      parameter_context: { market: "ru", delivery_mode: "fbo", company_type: "small" },
      effective_on: Date.new(2026, 3, 1),
      inputs: { price_rub: 7_000, commission_rate: 0.175 }
    )

    assert_empty result[:errors].to_a
    assert_in_delta 7_000.to_d / 13, result[:revenue_cny], 0.000001
    assert_in_delta 172, result.dig(:intermediate, :base_logistics_rub), 0.000001
    assert result.dig(:cost_breakdown, :returns).positive?
    assert result.dig(:cost_breakdown, :acquiring).positive?
    assert result.dig(:cost_breakdown, :tax).positive?
  end

  test "pure calculator rejects Ozon FBS even when called directly" do
    result = Ec::ProfitCalculator.call(
      platform: "ozon",
      parameter_context: { market: "ru", delivery_mode: "fbs" },
      inputs: {}
    )

    assert_includes result[:errors], "unsupported_delivery_mode"
  end

  test "saved context calculates entirely from its typed row inputs" do
    version = @sku.profit_versions.create!(name: "Typed row", status: "draft", effective_from: Date.new(2026, 3, 1))
    context = version.contexts.create!(
      platform: "wb", market: "ru", delivery_mode: "fbo", company_type: "small",
      purchase_price_cny: 210, freight_cny: 22.5, customs_misc_cny: 2.81,
      duty_rate: 0.1, import_vat_rate: 0.2,
      length_cm: 77, width_cm: 17, height_cm: 7,
      price_rub: 7_000, exchange_rate_rub_cny: 13,
      logistics_coeff: 1.25, return_rate: 0.18, commission_rate: 0.175,
      fbo_delivery_cny: 10, acquiring_rate: 0.031, advertising_rate: 0.175,
      storage_cny: 0, damage_rate: 0, misc_cny: 2, tax_rate: 0.06, other_cny: 0
    )

    @sku.costs.update_all(purchase_price_cny: 999)
    Ec::SkuDimension.where(sku_code: @sku.sku_code).update_all(inner_length_cm: 1, inner_width_cm: 1, inner_height_cm: 1)
    result = Ec::SkuProfitCalculator.call_for_context(context)

    assert_empty result[:errors].to_a
    assert_in_delta 572.9846716697936, result[:total_cost_cny], 0.000001
    assert_in_delta(-34.52313320825516, result[:profit_cny], 0.000001)
  ensure
    context_id = context&.id
    version_id = version&.id
    context&.delete
    version&.delete
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersionContext", record_id: context_id).delete_all if context_id
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: version_id).delete_all if version_id
  end

  test "resolves Ozon Belarus fee base from the Russian scenario price" do
    version = @sku.profit_versions.build(name: "Ozon market prices", status: "draft", effective_from: Date.new(2026, 3, 1))
    version.contexts.build(
      platform: "ozon", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
      price_rub: 10_800
    )
    belarus = version.contexts.build(
      platform: "ozon", market: "by", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
      purchase_price_cny: 270, freight_cny: 22.5, customs_misc_cny: 2.81,
      duty_rate: 0.1, import_vat_rate: 0.2,
      price_rub: 10_200, exchange_rate_rub_cny: 13,
      outbound_logistics_rub: 245, return_logistics_rub: 245,
      warehouse_operation_rub: 25, commission_rate: 0.075,
      return_rate: 0.1, acquiring_rate: 0.02, advertising_rate: 0.05,
      sales_vat_rate: 0.2
    )

    Ec::SkuProfitVersionPriceResolver.apply!(version)
    result = Ec::SkuProfitCalculator.call_for_context(belarus)

    assert_empty result[:errors].to_a
    assert_in_delta 10_800.to_d / 13, result.dig(:intermediate, :rf_revenue_cny), 0.000001
    assert_equal 10_800.to_d, belarus.rf_price_rub
  end

  test "falls back to the current Ozon Belarus price when the Russian scenario is empty" do
    version = @sku.profit_versions.build(name: "Ozon Belarus fallback", status: "draft", effective_from: Date.new(2026, 3, 1))
    version.contexts.build(
      platform: "ozon", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general"
    )
    belarus = version.contexts.build(
      platform: "ozon", market: "by", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
      purchase_price_cny: 270, price_rub: 8_910.96, exchange_rate_rub_cny: 13,
      outbound_logistics_rub: 245, return_logistics_rub: 245,
      warehouse_operation_rub: 25, commission_rate: 0.075
    )

    result = Ec::SkuProfitCalculator.call_for_context(belarus)

    assert_empty result[:errors].to_a
    assert_includes result[:warnings], "rf_price_fallback_to_market_price"
    assert_equal belarus.price_rub, Ec::SkuProfitVersionPriceResolver.price_for(belarus)
  end
end
