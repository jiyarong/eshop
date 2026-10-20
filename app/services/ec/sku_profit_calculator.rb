module Ec
  class SkuProfitCalculator
    DEFAULT_EXCHANGE_RATE_RUB_CNY = BigDecimal("13").freeze

    class << self
      def call(sku:, platform:, parameter_context:, inputs:, effective_on: Date.current)
        normalized_inputs = inputs.to_h.stringify_keys
        ProfitCalculator.call(
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
        parameter_context = context.attributes.slice("market", "delivery_mode", "warehouse_region", "company_type")
        ProfitCalculator.call(
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

      def wb_default_inputs(context)
        company_type = context.fetch("company_type", "general").to_s.downcase
        delivery_mode = context.fetch("delivery_mode", "fbo").to_s.downcase
        belarus = context.fetch("market", "ru").to_s.downcase == "by"
        general_company = company_type == "general"

        {
          exchange_rate_rub_cny: DEFAULT_EXCHANGE_RATE_RUB_CNY,
          buyer_price_vat_rate: decimal("0.2"),
          logistics_coeff: company_type == "small" && delivery_mode == "fbo" ? decimal("1.3") : decimal("1.55"),
          # Belarus-local sales: a third of the outbound parcels are cancelled or refused and come
          # back (measured on the ledger, Jul-Sep 2026), so the placeholder is well above Russia's;
          # "get actual data" replaces it per SKU.
          return_rate: decimal(belarus ? "0.3" : "0.1"),
          # Acquiring is 1.9% on Belarus sales, 3.0-3.4% on exports to Russia.
          acquiring_rate: if belarus then decimal("0.019")
                          else general_company ? decimal("0.015") : decimal("0.031")
                          end,
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
