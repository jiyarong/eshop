class AddDateColumnsToRawOzonReturns < ActiveRecord::Migration[8.0]
  def change
    add_column :raw_ozon_returns, :return_date, :datetime
    add_column :raw_ozon_returns, :final_moment, :datetime
    add_column :raw_ozon_returns, :visual_change_moment, :datetime

    add_index :raw_ozon_returns, [:account_id, :return_date],
              name: "idx_raw_ozon_returns_account_return_date"
    add_index :raw_ozon_returns, [:account_id, :final_moment],
              name: "idx_raw_ozon_returns_account_final_moment"
    add_index :raw_ozon_returns, [:account_id, :visual_change_moment],
              name: "idx_raw_ozon_returns_account_visual_change_moment"
  end
end
