class CreateEcWeeklyRates < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_weekly_rates do |t|
      t.date    :week_start,    null: false
      t.decimal :rate_cny_rub,  precision: 10, scale: 4, null: false
      t.decimal :rate_byn_rub,  precision: 10, scale: 4, null: false
      t.timestamps
    end
    add_index :ec_weekly_rates, :week_start, unique: true
  end
end
