module Ec
  class SkuProfitCalculator
    DEFAULT_EXCHANGE_RATE_RUB_CNY = BigDecimal("13").freeze

    class << self
      # parameter_context may carry "logistics_mode" ("formula" / "actual", see Ec::LogisticsFormula); the
      # result then has a `logistics` entry with the mode, what the formula says and what the other mode
      # would give, so the page can show the two side by side.
      def call(sku:, platform:, parameter_context:, inputs:, effective_on: Date.current)
        normalized_inputs = inputs.to_h.stringify_keys
        calculate(
          platform: platform,
          parameter_context: parameter_context,
          inputs: initial_inputs(
            sku: sku,
            platform: platform,
            parameter_context: parameter_context,
            effective_on: effective_on
          ).merge(normalized_inputs)
        )
      end

      def call_for_context(context, overrides: {})
        parameter_context = context.attributes.slice("market", "delivery_mode", "warehouse_region", "company_type", "logistics_mode")
        calculate(
          platform: context.platform,
          parameter_context: parameter_context,
          inputs: default_inputs(platform: context.platform, parameter_context: parameter_context)
            .merge(context.calculation_inputs)
            .merge(overrides.to_h.stringify_keys)
        )
      end

      def initial_inputs(sku:, platform:, parameter_context:, effective_on: Date.current)
        default_inputs(platform: platform, parameter_context: parameter_context)
          .merge(base_inputs(sku, effective_on: effective_on))
      end

      def default_inputs(platform:, parameter_context:)
        context = parameter_context.to_h.stringify_keys
        case platform.to_s.downcase
        when "wb" then wb_default_inputs(context)
        when "ozon" then ozon_default_inputs(context)
        else {}
        end
      end

      def base_inputs(sku, effective_on: Date.current)
        cost = sku.cost_on(effective_on)
        dimension = sku.dimension
        {
          purchase_price_cny: cost&.purchase_price_cny,
          freight_cny: cost&.freight_to_by_cny,
          customs_misc_cny: cost&.customs_misc_cny,
          duty_rate: cost&.customs_duty_rate,
          import_vat_rate: cost&.import_vat_rate,
          length_cm: dimension&.inner_length_cm,
          width_cm: dimension&.inner_width_cm,
          height_cm: dimension&.inner_height_cm
        }.compact.stringify_keys
      end

      private

      def calculate(platform:, parameter_context:, inputs:)
        mode = LogisticsFormula.mode_for(parameter_context)
        other = mode == "formula" ? "actual" : "formula"
        result = calculate_in_mode(platform, parameter_context, inputs, mode)
        alternative = calculate_in_mode(platform, parameter_context, inputs, other)
        formula = mode == "formula" ? result : alternative
        result.merge(
          logistics: {
            mode: mode,
            formula: formula_figures(platform, formula, inputs),
            alternative: alternative_summary(other, alternative, result)
          }
        )
      end

      def calculate_in_mode(platform, parameter_context, inputs, mode)
        adjusted, info = LogisticsFormula.apply(platform: platform, mode: mode, parameter_context: parameter_context, inputs: inputs)
        ProfitCalculator.call(platform: platform, parameter_context: parameter_context, inputs: adjusted).merge(logistics_info: info)
      end

      # The figures the fixed formula gives: for WB the base rate x coefficient and the flat return, for Ozon the
      # route average. nil entries when the formula cannot be worked out (no volume, no tariff).
      def formula_figures(platform, result, inputs)
        info = result.fetch(:logistics_info)
        return info.slice(:outbound_rub, :return_rub, :source, :route_count, :route_basis) unless platform.to_s.downcase == "wb"
        return { outbound_rub: nil, return_rub: nil, source: nil } if result[:errors].present?

        intermediate = result.fetch(:intermediate)
        coefficient = BigDecimal(inputs["logistics_coeff"].to_s, exception: false)
        {
          outbound_rub: coefficient && (intermediate.fetch(:base_logistics_rub) * coefficient).round(2),
          return_rub: BigDecimal((inputs["wb_fixed_return_base_rub"].presence || "50").to_s),
          source: "wb_coefficient"
        }
      end

      def alternative_summary(mode, alternative, current)
        return if alternative[:errors].present? || current[:errors].present?

        {
          mode: mode,
          profit_cny: alternative[:profit_cny], margin: alternative[:margin], total_cost_cny: alternative[:total_cost_cny],
          logistics_cny: alternative.dig(:cost_breakdown, :logistics), returns_cny: alternative.dig(:cost_breakdown, :returns),
          profit_difference_cny: alternative[:profit_cny] - current[:profit_cny]
        }
      end

      def wb_default_inputs(context)
        company_type = context.fetch("company_type", "general").to_s.downcase
        belarus = context.fetch("market", "ru").to_s.downcase == "by"
        general_company = company_type == "general"

        {
          exchange_rate_rub_cny: DEFAULT_EXCHANGE_RATE_RUB_CNY,
          buyer_price_vat_rate: decimal("0.2"),
          # WB's coefficient is the warehouse tier (1.0 ... 2.0), not a tax-regime or market property. Measured on the
          # outbound legs of Jul-Oct 2026, FBS sits on 1.45-1.55 (95% at or below 1.55) and FBW anywhere from 1.0 to 2.0
          # (about 80% at or below 1.55): 1.55 is the high end that covers most parcels, so a fixed-formula profit is
          # never the optimistic one. 1.55 is also the official 71.3 / 21.7 tier of the base 46 / 14.
          logistics_coeff: decimal("1.55"),
          return_rate: decimal("0.1"),
          # Acquiring is 1.8-1.9% on sales to Belarusian buyers, 3.2-3.4% on sales to Russian ones
          # (Jul-Sep 2026, by the buyer's country in the statistics orders).
          acquiring_rate: if belarus then decimal("0.019")
                          else general_company ? decimal("0.015") : decimal("0.031")
                          end,
          sales_vat_rate: general_company ? decimal("0.2") : nil,
          tax_rate: general_company ? nil : decimal("0.06"),
          # WB charges the same tariff whatever the tax regime: 46 for the first litre, 14 for each further one (x the
          # warehouse coefficient). The sheet's 60 for a general company has no official or measured counterpart.
          wb_logistics_base_rub: decimal("46"),
          wb_logistics_liter_rub: decimal("14"),
          wb_fixed_return_base_rub: decimal("50"),
          fbo_delivery_cny: decimal("0"),
          storage_cny: decimal("0"),
          damage_rate: decimal("0"),
          misc_cny: decimal("2"),
          other_cny: decimal("0")
        }.compact.stringify_keys
      end

      def ozon_default_inputs(context)
        market = context.fetch("market", "ru").to_s.downcase
        fbs = context.fetch("delivery_mode", "fbo").to_s.downcase == "fbs"
        {
          exchange_rate_rub_cny: DEFAULT_EXCHANGE_RATE_RUB_CNY,
          # VAT embedded in what the buyer pays: Russian buyers 22%, Belarusian buyers 20%.
          buyer_price_vat_rate: decimal(market == "ru" ? "0.22" : "0.2"),
          return_rate: decimal("0.1"),
          acquiring_rate: decimal("0.02"),
          tax_rate: decimal("0"),
          sales_vat_rate: market == "by" ? decimal("0.2") : nil,
          storage_cny: decimal("0"),
          other_cny: decimal("0"),
          warehouse_operation_rub: fbs ? nil : decimal("25"),
          fbs_handover_rub: fbs ? decimal("30") : nil,
          cross_docking_cny: fbs ? nil : decimal("0"),
          ozon_warehouse_rate: decimal("0.25"),
          ozon_import_vat_cost_rate: decimal("0"),
          advertising_fixed_rub: decimal("0")
        }.compact.stringify_keys
      end

      def decimal(value)
        BigDecimal(value)
      end
    end
  end
end
