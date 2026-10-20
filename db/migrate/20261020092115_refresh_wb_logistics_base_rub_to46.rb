# WB charges one tariff whatever the tax regime (46 RUB for the first litre, 14 for each further one, times the
# warehouse coefficient); the 60 that general-company scenarios carried has no official or measured counterpart
# (docs/sku_workbench_v2/14_场景扩展与可见性.md, section 12). Every saved WB scenario, in every version, gets the 46
# and is calculated again. Typed figures other than the base fee (coefficient, per-litre fee, real freight) stay.
class RefreshWbLogisticsBaseRubTo46 < ActiveRecord::Migration[8.1]
  BASE_RUB = 46

  def up
    scope = Ec::SkuProfitVersionContext.where(platform: "wb")
      .where("wb_logistics_base_rub IS NULL OR wb_logistics_base_rub <> ?", BASE_RUB)
    changed = 0

    scope.find_each do |context|
      context.wb_logistics_base_rub = BASE_RUB
      result = Ec::SkuProfitCalculator.call_for_context(context)
      context.apply_calculation_result(result, calculated_at: Time.current)
      attributes = context.changes_to_save.transform_values(&:last)
      next if attributes.empty?

      # No audit trail, no updated_at on the version: this is a system-wide correction, not a user edit.
      context.update_columns(attributes.merge("updated_at" => Time.current))
      changed += 1
    end

    say "refreshed #{changed} WB scenarios to a #{BASE_RUB} RUB base logistics fee"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
