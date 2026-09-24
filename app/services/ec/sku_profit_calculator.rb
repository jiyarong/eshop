module Ec
  class SkuProfitCalculator
    DEFAULT_EXCHANGE_RATE_RUB_CNY = BigDecimal("13").freeze

    class << self
      def call(sku:, platform:, parameter_context:, inputs:, effective_on: Date.current)
        normalized_inputs = inputs.to_h.stringify_keys
        normalized_context = parameter_context.to_h.stringify_keys
        fallback_reference_price = normalized_context["market"].to_s.downcase == "by" &&
          normalized_inputs["rf_price_rub"].blank? && normalized_inputs["price_rub"].present?
        normalized_inputs["rf_price_rub"] = normalized_inputs["price_rub"] if fallback_reference_price

        result = ProfitCalculator.call(
          platform: platform,
          parameter_context: parameter_context,
          inputs: initial_inputs(
            sku: sku,
            platform: platform,
            parameter_context: parameter_context,
            effective_on: effective_on
          ).merge(normalized_inputs)
        )
        add_reference_price_warning(result) if fallback_reference_price
        result
      end

      def call_for_context(context, overrides: {})
        parameter_context = context.attributes.slice("market", "delivery_mode", "warehouse_region", "company_type")
        resolved_overrides = overrides.to_h.stringify_keys
        if SkuProfitVersionPriceResolver.belarus_ozon_context?(context)
          resolved_overrides["rf_price_rub"] = SkuProfitVersionPriceResolver.price_for(context)
        end
        result = ProfitCalculator.call(
          platform: context.platform,
          parameter_context: parameter_context,
          inputs: default_inputs(platform: context.platform, parameter_context: parameter_context)
            .merge(context.calculation_inputs)
            .merge(resolved_overrides)
        )
        add_reference_price_warning(result) if SkuProfitVersionPriceResolver.fallback_to_market_price?(context)
        result
      end

      def add_reference_price_warning(result)
        result[:warnings] = Array(result[:warnings]).push("rf_price_fallback_to_market_price").uniq
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

      def wb_default_inputs(context)
        company_type = context.fetch("company_type", "general").to_s.downcase
        delivery_mode = context.fetch("delivery_mode", "fbo").to_s.downcase
        general_company = company_type == "general"

        {
          exchange_rate_rub_cny: DEFAULT_EXCHANGE_RATE_RUB_CNY,
          logistics_coeff: company_type == "small" && delivery_mode == "fbo" ? decimal("1.3") : decimal("1.55"),
          return_rate: decimal("0.1"),
          acquiring_rate: general_company ? decimal("0.015") : decimal("0.031"),
          sales_vat_rate: general_company ? decimal("0.2") : nil,
          tax_rate: general_company ? nil : decimal("0.06"),
          wb_logistics_base_rub: general_company ? decimal("60") : decimal("46"),
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
        {
          exchange_rate_rub_cny: DEFAULT_EXCHANGE_RATE_RUB_CNY,
          return_rate: decimal("0.1"),
          acquiring_rate: decimal("0.02"),
          tax_rate: decimal("0"),
          sales_vat_rate: market == "by" ? decimal("0.2") : nil,
          storage_cny: decimal("0"),
          other_cny: decimal("0"),
          warehouse_operation_rub: decimal("25"),
          cross_docking_cny: decimal("0"),
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
