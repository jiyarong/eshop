class ReserveMinusOneForRawWbAdvAllApps < ActiveRecord::Migration[8.1]
  def change
    change_column_default :raw_wb_adv_product_daily_stats, :app_type, from: 0, to: -1

    reversible do |direction|
      direction.up do
        execute "UPDATE raw_wb_adv_product_daily_stats SET app_type = -1 WHERE app_type = 0"
      end
      direction.down do
        execute "UPDATE raw_wb_adv_product_daily_stats SET app_type = 0 WHERE app_type = -1"
      end
    end
  end
end
