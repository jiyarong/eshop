module Ec
  module ProfitCalculators
    class Ozon < Base
      REQUIRED = %w[purchase_price_cny price_rub exchange_rate_rub_cny outbound_logistics_rub return_logistics_rub warehouse_operation_rub commission_rate].freeze
      def call
        required = REQUIRED.dup
        required << "rf_price_rub" if market == "by"
        errors = validation_errors(required: required, dimensions: %w[length_cm width_cm height_cm])
        errors << "unsupported_market" unless market.in?(%w[ru by])
        errors << "unsupported_delivery_mode" unless @context.fetch("delivery_mode", "").to_s.downcase == "fbo"
        if numeric?("return_amortization_factor_override") && decimal("return_amortization_factor_override").negative?
          errors << "return_amortization_factor_override_must_be_non_negative"
        end
        return ProfitCalculator.error(errors.first).merge(errors: errors) if errors.any?
        exchange = decimal("exchange_rate_rub_cny")
        revenue = decimal("price_rub") / exchange
        rf_revenue = (market == "by" ? decimal("rf_price_rub") : decimal("price_rub")) / exchange
        purchase = decimal("purchase_price_cny")
        volume = if %w[length_cm width_cm height_cm].all? { |key| numeric?(key) }
          decimal("length_cm") * decimal("width_cm") * decimal("height_cm") / 1000
        end
        billed_volume = volume&.ceil
        duty = purchase * value_or_default("duty_rate", "0.1")
        import_vat = (purchase + duty) * value_or_default("import_vat_rate", "0.2")
        goods = purchase + value_or_default("freight_cny", "0") + value_or_default("customs_misc_cny", "0")
        return_rate = value_or_default("return_rate", "0.1")
        return_amortization_factor = if present?("return_amortization_factor_override")
          decimal("return_amortization_factor_override")
        else
          return_rate / (1 - return_rate)
        end
        warehouse_rate = value_or_default("ozon_warehouse_rate", "0.25")
        return_amortized = (decimal("outbound_logistics_rub") + decimal("return_logistics_rub")) * return_amortization_factor
        warehouse = decimal("warehouse_operation_rub")
        warehouse_surcharge = warehouse * 2 * warehouse_rate
        logistics_rub = decimal("outbound_logistics_rub") + return_amortized + warehouse + warehouse_surcharge
        sales_tax = if market == "by"
          revenue * value_or_default("sales_vat_rate", "0.2") / (1 + value_or_default("sales_vat_rate", "0.2")) - import_vat
        else
          revenue * value_or_default("tax_rate", "0")
        end
        import_vat_cost = market == "by" ? import_vat : import_vat * value_or_default("ozon_import_vat_cost_rate", "0")
        breakdown = {
          goods: goods,
          import_vat: import_vat_cost,
          duty: duty,
          logistics: (logistics_rub - return_amortized) / exchange,
          returns: return_amortized / exchange,
          storage: value_or_default("storage_cny", "0"),
          commission: revenue * decimal("commission_rate"),
          acquiring: rf_revenue * value_or_default("acquiring_rate", "0.02"),
          advertising: rf_revenue * value_or_default("advertising_rate", "0") + value_or_default("advertising_fixed_rub", "0") / exchange,
          tax: sales_tax,
          other: (market == "ru" ? value_or_default("cross_docking_cny", "0") : 0.to_d) + value_or_default("other_cny", "0")
        }
        warnings = optional_warnings("advertising_rate", "other_cny")
        result(revenue: revenue, breakdown: breakdown, warnings: warnings,
          intermediate: { import_vat_cny: import_vat, volume_l: volume, billed_volume_l: billed_volume,
            return_rate: return_rate,
            return_amortization_factor: return_amortization_factor,
            return_amortized_rub: return_amortized,
            warehouse_surcharge_rub: warehouse_surcharge, platform_logistics_rub: logistics_rub,
            platform_logistics_cny: logistics_rub / exchange, rf_revenue_cny: rf_revenue })
      end
      private
      def market = @context.fetch("market", "ru").to_s.downcase
      def value_or_default(key, default) = present?(key) ? decimal(key) : default.to_d
    end
  end
end
