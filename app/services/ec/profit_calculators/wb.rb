module Ec
  module ProfitCalculators
    class Wb < Base
      COMPANY_TYPES = %w[general small].freeze
      REQUIRED = %w[purchase_price_cny price_rub exchange_rate_rub_cny length_cm width_cm height_cm logistics_coeff commission_rate].freeze

      def call
        errors = validation_errors(required: REQUIRED, dimensions: %w[length_cm width_cm height_cm])
        errors << "unsupported_delivery_mode" unless @context.fetch("delivery_mode", "").to_s.downcase.in?(%w[fbo fbs])
        errors << "unsupported_company_type" unless company_type.in?(COMPANY_TYPES)
        return ProfitCalculator.error(errors.first).merge(errors: errors) if errors.any?

        purchase = decimal("purchase_price_cny")
        duty = purchase * value_or_default("duty_rate", "0.1")
        import_vat = (purchase + duty) * value_or_default("import_vat_rate", "0.2")
        goods = purchase + value_or_default("freight_cny", "0") + value_or_default("customs_misc_cny", "0")
        volume = decimal("length_cm") * decimal("width_cm") * decimal("height_cm") / 1000
        billed_volume = volume.ceil
        base_logistics_fee_rub = value_or_default("wb_logistics_base_rub", general_company? ? "60" : "46")
        logistics_liter_fee_rub = value_or_default("wb_logistics_liter_rub", "14")
        base_logistics_rub = base_logistics_fee_rub + (billed_volume - 1) * logistics_liter_fee_rub
        exchange = decimal("exchange_rate_rub_cny")
        revenue = decimal("price_rub") / exchange
        logistics = present?("wb_logistics_override_cny") ? decimal("wb_logistics_override_cny") : base_logistics_rub * decimal("logistics_coeff") / exchange
        return_rate = value_or_default("return_rate", "0.1")
        returns = logistics * return_rate / (1 - return_rate)
        fixed_return = value_or_default("wb_fixed_return_base_rub", "50") / exchange * return_rate / (1 - return_rate)
        damage = (goods + import_vat + duty) * value_or_default("damage_rate", "0")
        sales_tax = if general_company?
          vat_rate = value_or_default("sales_vat_rate", "0.2")
          revenue * vat_rate / (1 + vat_rate) - import_vat
        else
          revenue * value_or_default("tax_rate", "0.06")
        end
        breakdown = {
          goods: goods,
          import_vat: import_vat,
          duty: duty,
          logistics: value_or_default("fbo_delivery_cny", "0") + logistics,
          returns: returns + fixed_return,
          storage: value_or_default("storage_cny", "0"),
          commission: revenue * decimal("commission_rate"),
          acquiring: revenue * value_or_default("acquiring_rate", "0"),
          advertising: revenue * value_or_default("advertising_rate", "0"),
          tax: sales_tax,
          other: damage + value_or_default("misc_cny", "0") + value_or_default("other_cny", "0")
        }
        warnings = optional_warnings("fbo_delivery_cny", "storage_cny", "acquiring_rate", "advertising_rate", "damage_rate", "misc_cny")
        result(revenue: revenue, breakdown: breakdown, warnings: warnings,
          intermediate: { volume_l: volume, billed_volume_l: billed_volume, base_logistics_fee_rub: base_logistics_fee_rub,
            base_logistics_rub: base_logistics_rub, logistics_liter_fee_rub: logistics_liter_fee_rub,
            platform_logistics_cny: logistics, return_amortization_cny: returns, fixed_return_cny: fixed_return })
      end

      private

      def company_type = @context.fetch("company_type", "").to_s.downcase
      def general_company? = company_type == "general"
      def value_or_default(key, default) = present?(key) ? decimal(key) : default.to_d
    end
  end
end
