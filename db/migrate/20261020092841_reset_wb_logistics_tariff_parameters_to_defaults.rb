# The pricing workbench is treated as never having been in use: every saved WB scenario, in every version, gets
# the default tariff parameters (base 46 RUB, 14 RUB per further litre, coefficient 1.55) and is calculated
# again, whatever was typed before. See docs/sku_workbench_v2/14_场景扩展与可见性.md, section 12: the official tariff
# is one 46 / 14 schedule times the warehouse coefficient; 1.55 is the high end that the bulk of the real outbound
# legs fall at or below, and a hand-typed 2.00 / 1.25 / 1.30 matched no measured cost.
# Typed real freight figures and every other parameter stay.
class ResetWbLogisticsTariffParametersToDefaults < ActiveRecord::Migration[8.1]
  PARAMETERS = {
    "wb_logistics_base_rub" => 46,
    "wb_logistics_liter_rub" => 14,
    "logistics_coeff" => BigDecimal("1.55")
  }.freeze

  def up
    changed = 0

    Ec::SkuProfitVersionContext.where(platform: "wb").find_each do |context|
      context.assign_attributes(PARAMETERS)
      result = Ec::SkuProfitCalculator.call_for_context(context)
      context.apply_calculation_result(result, calculated_at: Time.current)
      attributes = context.changes_to_save.transform_values(&:last)
      next if attributes.empty?

      # No audit trail, no updated_at on the version: this is a system-wide correction, not a user edit.
      context.update_columns(attributes.merge("updated_at" => Time.current))
      changed += 1
    end

    say "reset the tariff parameters of #{changed} WB scenarios"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
