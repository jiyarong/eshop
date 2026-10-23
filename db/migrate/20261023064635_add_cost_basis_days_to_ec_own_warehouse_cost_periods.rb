class AddCostBasisDaysToEcOwnWarehouseCostPeriods < ActiveRecord::Migration[8.1]
  def up
    add_column :ec_own_warehouse_cost_periods, :cost_basis_days, :integer, if_not_exists: true
    # Preserve each existing version's daily rate before opening its validity range.
    execute <<~SQL
      UPDATE ec_own_warehouse_cost_periods
      SET cost_basis_days = CASE WHEN effective_to IS NULL THEN 7 ELSE effective_to - effective_from + 1 END
    SQL
    change_column_default :ec_own_warehouse_cost_periods, :cost_basis_days, 7
    change_column_null :ec_own_warehouse_cost_periods, :cost_basis_days, false
    add_check_constraint :ec_own_warehouse_cost_periods, "cost_basis_days > 0", name: "own_wh_cost_periods_basis_days"
    execute <<~SQL
      UPDATE ec_own_warehouse_cost_periods AS latest
      SET effective_to = NULL
      WHERE latest.status = 'confirmed'
        AND NOT EXISTS (
          SELECT 1 FROM ec_own_warehouse_cost_periods AS successor
          WHERE successor.own_warehouse_code = latest.own_warehouse_code
            AND successor.status IN ('confirmed', 'superseded')
            AND successor.effective_from > latest.effective_from
        )
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Continuous validity cannot be converted back to fixed total-cost intervals without changing rates"
  end
end
