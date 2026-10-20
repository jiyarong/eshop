# Ozon FBO and FBS now share one structure: the route freight plus a small fixed fee per delivered unit
# (`fbs_handover_rub`, the handover and last-mile fee). The bills show it: FBS pays the drop-off at a pickup point or
# sorting centre, the last-mile redistribution and the delivery to the handover place (about 36 RUB per unit in
# Sep-Oct 2026), FBO only the last two (about 12); Ozon's old FBO "warehouse operation fee" (25 RUB + a surcharge)
# does not appear in them at all (docs/sku_workbench_v2/14_场景扩展与可见性.md, section 14).
#
# Every saved Ozon scenario, in every version, gets the default handover fee for its mode, loses the old warehouse
# operation fee and surcharge rate, and is calculated again (which also brings in the route freight of the fixed
# formula). Typed real freight figures and every other parameter stay.
class ResetOzonHandoverFeeAndRecalculate < ActiveRecord::Migration[8.1]
  def up
    defaults = Ec::ProfitCalculators::Ozon::DEFAULT_HANDOVER_RUB
    changed = 0

    Ec::SkuProfitVersionContext.where(platform: "ozon").find_each do |context|
      context.assign_attributes(
        fbs_handover_rub: BigDecimal(defaults.fetch(context.delivery_mode.to_s, defaults.fetch("fbo"))),
        warehouse_operation_rub: nil,
        ozon_warehouse_rate: nil
      )
      result = Ec::SkuProfitCalculator.call_for_context(context)
      context.apply_calculation_result(result, calculated_at: Time.current)
      attributes = context.changes_to_save.transform_values(&:last)
      next if attributes.empty?

      # No audit trail, no updated_at on the version: this is a system-wide correction, not a user edit.
      context.update_columns(attributes.merge("updated_at" => Time.current))
      changed += 1
    end

    say "reset the handover fee of #{changed} Ozon scenarios"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
