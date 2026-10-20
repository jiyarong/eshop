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
        commission_base_price_rub: 7_000,
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
    assert_equal 0.2.to_d, wb_general.fetch("buyer_price_vat_rate")
    assert_equal 2.to_d, wb_general.fetch("misc_cny")

    assert_equal 1.3.to_d, wb_small_fbo.fetch("logistics_coeff")
    assert_equal 1.55.to_d, wb_small_fbs.fetch("logistics_coeff")
    assert_equal 0.1.to_d, wb_small_fbo.fetch("return_rate")
    assert_equal 0.031.to_d, wb_small_fbo.fetch("acquiring_rate")
    assert_equal 46.to_d, wb_small_fbo.fetch("wb_logistics_base_rub")
    assert_equal 0.06.to_d, wb_small_fbo.fetch("tax_rate")
    assert_equal 0.2.to_d, wb_small_fbo.fetch("buyer_price_vat_rate")

    assert_equal 13.to_d, ozon_ru.fetch("exchange_rate_rub_cny")
    assert_equal 0.1.to_d, ozon_ru.fetch("return_rate")
    assert_equal 0.02.to_d, ozon_ru.fetch("acquiring_rate")
    assert_equal 25.to_d, ozon_ru.fetch("warehouse_operation_rub")
    assert_equal 0.25.to_d, ozon_ru.fetch("ozon_warehouse_rate")
    assert_equal 0.to_d, ozon_ru.fetch("cross_docking_cny")
    assert_equal 0.22.to_d, ozon_ru.fetch("buyer_price_vat_rate")
    assert_equal 0.2.to_d, ozon_by.fetch("sales_vat_rate")
    assert_equal 0.2.to_d, ozon_by.fetch("buyer_price_vat_rate")
  end

  test "call applies WB scenario defaults without a controller" do
    result = Ec::SkuProfitCalculator.call(
      sku: @sku,
      platform: "wb",
      parameter_context: { market: "ru", delivery_mode: "fbo", company_type: "small" },
      effective_on: Date.new(2026, 3, 1),
      inputs: { commission_base_price_rub: 7_000, commission_rate: 0.175 }
    )

    assert_empty result[:errors].to_a
    assert_in_delta 7_000.to_d / 13, result[:revenue_cny], 0.000001
    assert_in_delta 172, result.dig(:intermediate, :base_logistics_rub), 0.000001
    assert result.dig(:cost_breakdown, :returns).positive?
    assert result.dig(:cost_breakdown, :acquiring).positive?
    assert result.dig(:cost_breakdown, :tax).positive?
  end

  test "pure calculator rejects a delivery mode Ozon does not have" do
    result = Ec::ProfitCalculator.call(
      platform: "ozon",
      parameter_context: { market: "ru", delivery_mode: "rfbs" },
      inputs: {}
    )

    assert_includes result[:errors], "unsupported_delivery_mode"
  end

  test "Ozon FBS needs no warehouse operation fee and charges a handover fee instead" do
    inputs = {
      purchase_price_cny: 100, commission_base_price_rub: 2600, exchange_rate_rub_cny: 13, commission_rate: 0.4,
      length_cm: 20, width_cm: 20, height_cm: 10, outbound_logistics_rub: 260, return_logistics_rub: 130,
      return_rate: 0.1, acquiring_rate: 0, advertising_rate: 0
    }
    fbs = Ec::ProfitCalculator.call(platform: "ozon", parameter_context: { market: "ru", delivery_mode: "fbs" }, inputs: inputs.merge(fbs_handover_rub: 30))
    fbo = Ec::ProfitCalculator.call(platform: "ozon", parameter_context: { market: "ru", delivery_mode: "fbo" }, inputs: inputs.merge(warehouse_operation_rub: 25))

    assert_empty fbs[:errors].to_a
    # (outbound 260 + handover 30) / 13 as platform logistics; returns amortised as in FBO.
    assert_in_delta (260 + 30) / 13.0, fbs.dig(:cost_breakdown, :logistics), 1e-9
    assert_in_delta (260 + 130) * (0.1 / 0.9) / 13.0, fbs.dig(:cost_breakdown, :returns), 1e-9
    assert_in_delta 30, fbs.dig(:intermediate, :fbs_handover_rub), 1e-9
    assert_in_delta 0, fbs.dig(:intermediate, :warehouse_surcharge_rub), 1e-9
    assert_in_delta (260 + 25 + 25 * 0.5) / 13.0, fbo.dig(:cost_breakdown, :logistics), 1e-9
  end

  test "Ozon FBS ignores cross-docking and uses a default handover fee of 30 when none is given" do
    inputs = {
      purchase_price_cny: 100, commission_base_price_rub: 2600, exchange_rate_rub_cny: 13, commission_rate: 0.4,
      length_cm: 20, width_cm: 20, height_cm: 10, outbound_logistics_rub: 260, return_logistics_rub: 130,
      cross_docking_cny: 50, warehouse_operation_rub: 99
    }
    result = Ec::ProfitCalculator.call(platform: "ozon", parameter_context: { market: "ru", delivery_mode: "fbs" }, inputs: inputs)

    assert_empty result[:errors].to_a
    assert_in_delta 30, result.dig(:intermediate, :fbs_handover_rub), 1e-9
    assert_in_delta 0, result.dig(:cost_breakdown, :other), 1e-9
    assert_in_delta (260 + 30) / 13.0, result.dig(:cost_breakdown, :logistics), 1e-9
  end

  test "Ozon FBS still asks for the route prices but not for a warehouse fee" do
    result = Ec::ProfitCalculator.call(platform: "ozon", parameter_context: { market: "by", delivery_mode: "fbs" }, inputs: { purchase_price_cny: 10 })

    assert_includes result[:errors], "missing_outbound_logistics_rub"
    assert_includes result[:errors], "missing_return_logistics_rub"
    assert_not_includes result[:errors], "missing_warehouse_operation_rub"
  end

  test "Ozon FBS defaults carry the handover fee and drop the FBO warehouse inputs" do
    fbs = Ec::SkuProfitCalculator.default_inputs(platform: "ozon", parameter_context: { market: "by", delivery_mode: "fbs", company_type: "general" })

    assert_equal 30.to_d, fbs.fetch("fbs_handover_rub")
    assert_not fbs.key?("warehouse_operation_rub")
    assert_not fbs.key?("cross_docking_cny")
    assert_equal 0.2.to_d, fbs.fetch("sales_vat_rate")
  end

  test "WB Belarus scenarios default to the Belarus acquiring rate" do
    %w[general small].each do |company_type|
      %w[fbo fbs].each do |mode|
        by = Ec::SkuProfitCalculator.default_inputs(platform: "wb", parameter_context: { market: "by", delivery_mode: mode, company_type: company_type })
        ru = Ec::SkuProfitCalculator.default_inputs(platform: "wb", parameter_context: { market: "ru", delivery_mode: mode, company_type: company_type })

        assert_equal 0.019.to_d, by.fetch("acquiring_rate"), "#{company_type}/#{mode}"
        assert_equal ru.fetch("return_rate"), by.fetch("return_rate"), "the return rate is measured, not guessed per market"
        # Tax regime and logistics inputs follow the company type and mode, not the market.
        assert_equal ru.fetch("logistics_coeff"), by.fetch("logistics_coeff")
        assert_equal ru.slice("tax_rate", "sales_vat_rate"), by.slice("tax_rate", "sales_vat_rate")
      end
    end
  end

  test "saved context calculates entirely from its typed row inputs" do
    version = @sku.profit_versions.create!(name: "Typed row", status: "draft", effective_from: Date.new(2026, 3, 1))
    context = version.contexts.create!(
      platform: "wb", market: "ru", delivery_mode: "fbo", company_type: "small",
      purchase_price_cny: 210, freight_cny: 22.5, customs_misc_cny: 2.81,
      duty_rate: 0.1, import_vat_rate: 0.2,
      length_cm: 77, width_cm: 17, height_cm: 7,
      commission_base_price_rub: 7_000, exchange_rate_rub_cny: 13,
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

  test "keeps the Ozon Belarus commission base independent from the Russian scenario price" do
    version = @sku.profit_versions.build(name: "Ozon market prices", status: "draft", effective_from: Date.new(2026, 3, 1))
    version.contexts.build(
      platform: "ozon", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
      commission_base_price_rub: 10_800
    )
    belarus = version.contexts.build(
      platform: "ozon", market: "by", delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
      purchase_price_cny: 270, freight_cny: 22.5, customs_misc_cny: 2.81,
      duty_rate: 0.1, import_vat_rate: 0.2,
      buyer_paid_price_rub: 10_200, commission_base_price_rub: 12_500, exchange_rate_rub_cny: 13, logistics_mode: "actual",
      outbound_logistics_rub: 245, return_logistics_rub: 245,
      warehouse_operation_rub: 25, commission_rate: 0.075,
      return_rate: 0.1, acquiring_rate: 0.02, advertising_rate: 0.05,
      sales_vat_rate: 0.2
    )

    result = Ec::SkuProfitCalculator.call_for_context(belarus)

    assert_empty result[:errors].to_a
    assert_in_delta 12_500.to_d / 13, result.dig(:intermediate, :commission_base_cny), 0.000001
    assert_equal 12_500.to_d, belarus.commission_base_price_rub
    assert_in_delta 12_500.to_d * 0.925 - 10_200.to_d / 1.2, result.dig(:intermediate, :platform_subsidy_rub), 0.000001
  end

  test "requires the Ozon commission base price in both markets" do
    version = @sku.profit_versions.build(name: "Ozon price validation", status: "draft", effective_from: Date.new(2026, 3, 1))

    %w[ru by].each do |market|
      context = version.contexts.build(
        platform: "ozon", market:, delivery_mode: "fbo", warehouse_region: "main", company_type: "general",
        purchase_price_cny: 270, buyer_paid_price_rub: 8_910.96, exchange_rate_rub_cny: 13,
        outbound_logistics_rub: 245, return_logistics_rub: 245,
        warehouse_operation_rub: 25, commission_rate: 0.075
      )

      result = Ec::SkuProfitCalculator.call_for_context(context)

      assert_includes result[:errors], "missing_commission_base_price_rub"
    end
  end

  WB_LOGISTICS_INPUTS = {
    "purchase_price_cny" => 100, "commission_base_price_rub" => 4_000, "exchange_rate_rub_cny" => 13, "commission_rate" => 0.2,
    "length_cm" => 20, "width_cm" => 20, "height_cm" => 10, "return_rate" => 0.1
  }.freeze

  test "a WB scenario on the formula ignores real freight figures and says what the other mode would give" do
    typed = WB_LOGISTICS_INPUTS.merge("outbound_logistics_rub" => 500, "return_logistics_rub" => 120)
    context = { "market" => "ru", "delivery_mode" => "fbo", "warehouse_region" => "main", "company_type" => "general" }

    formula = Ec::SkuProfitCalculator.call(sku: @sku, platform: "wb", parameter_context: context.merge("logistics_mode" => "formula"), inputs: typed)
    actual = Ec::SkuProfitCalculator.call(sku: @sku, platform: "wb", parameter_context: context.merge("logistics_mode" => "actual"), inputs: typed)
    blank = Ec::SkuProfitCalculator.call(sku: @sku, platform: "wb", parameter_context: context.merge("logistics_mode" => "formula"), inputs: WB_LOGISTICS_INPUTS)

    assert_empty formula[:errors].to_a
    assert_equal "coefficient", formula.dig(:intermediate, :logistics_source)
    assert_equal "actual", actual.dig(:intermediate, :logistics_source)
    assert_equal blank[:profit_cny], formula[:profit_cny], "typed figures do not matter on the formula"
    assert_not_equal formula[:profit_cny], actual[:profit_cny]

    # volume 4 L -> billed 4 L: 60 + 3 x 14 = 102 RUB, x 1.55 coefficient = 158.1 RUB; the return is the flat 50
    assert_equal 158.1.to_d, formula.dig(:logistics, :formula, :outbound_rub)
    assert_equal 50.to_d, formula.dig(:logistics, :formula, :return_rub)
    assert_equal 158.1.to_d, actual.dig(:logistics, :formula, :outbound_rub), "the formula's figure is shown in actual mode too"

    assert_equal "formula", formula.dig(:logistics, :mode)
    assert_equal "actual", formula.dig(:logistics, :alternative, :mode)
    assert_equal actual[:profit_cny], formula.dig(:logistics, :alternative, :profit_cny)
    assert_in_delta actual[:profit_cny] - formula[:profit_cny], formula.dig(:logistics, :alternative, :profit_difference_cny), 1e-9
    assert_in_delta formula[:profit_cny] - actual[:profit_cny], actual.dig(:logistics, :alternative, :profit_difference_cny), 1e-9
  end

  test "without real figures there is no other mode to compare with only when the formula cannot be worked out" do
    context = { "market" => "ru", "delivery_mode" => "fbo", "warehouse_region" => "main", "company_type" => "general", "logistics_mode" => "formula" }

    result = Ec::SkuProfitCalculator.call(sku: @sku, platform: "wb", parameter_context: context, inputs: WB_LOGISTICS_INPUTS)

    assert_equal "actual", result.dig(:logistics, :alternative, :mode)
    assert_in_delta 0, result.dig(:logistics, :alternative, :profit_difference_cny), 1e-9, "no typed figures: both modes use the formula"
  end

  test "a saved context calculates in its own mode" do
    version = @sku.profit_versions.build(name: "Mode", status: "draft", effective_from: Date.new(2026, 3, 1))
    inputs = { purchase_price_cny: 100, commission_base_price_rub: 4_000, exchange_rate_rub_cny: 13, commission_rate: 0.2,
               length_cm: 20, width_cm: 20, height_cm: 10, return_rate: 0.1, outbound_logistics_rub: 500, return_logistics_rub: 120 }
    formula = version.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "general", logistics_mode: "formula", **inputs)
    actual = version.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbs", warehouse_region: "main", company_type: "general", logistics_mode: "actual", **inputs)

    formula_result = Ec::SkuProfitCalculator.call_for_context(formula)
    actual_result = Ec::SkuProfitCalculator.call_for_context(actual)

    assert_equal "coefficient", formula_result.dig(:intermediate, :logistics_source)
    assert_equal "actual", actual_result.dig(:intermediate, :logistics_source)
    assert_equal 500.to_d, actual_result.dig(:intermediate, :outbound_logistics_rub)
  end

  test "a context only accepts the two logistics modes" do
    version = @sku.profit_versions.build(name: "Mode", status: "draft", effective_from: Date.new(2026, 3, 1))
    assert version.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo", logistics_mode: "formula").valid?
    context = version.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbs", logistics_mode: "guess")
    assert_not context.valid?
    assert context.errors.of_kind?(:logistics_mode, :inclusion)
    assert_equal "formula", Ec::SkuProfitVersionContext.new.logistics_mode, "new scenarios start on the fixed formula"
  end
end
