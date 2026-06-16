class AddSaleIdToWbStatsSales < ActiveRecord::Migration[8.1]
  def up
    add_column :raw_wb_stats_sales, :sale_id, :string

    # 存量数据：srid 已落库的行，sale_id 暂时用 srid 占位（重刷后会被正确值覆盖）
    execute "UPDATE raw_wb_stats_sales SET sale_id = srid WHERE sale_id IS NULL"

    add_index :raw_wb_stats_sales, %i[account_id sale_id], unique: true,
              name: "index_raw_wb_stats_sales_on_account_id_and_sale_id"

    remove_index :raw_wb_stats_sales, name: "idx_raw_wb_stats_sales_account_srid"
  end

  def down
    add_index :raw_wb_stats_sales, %i[account_id srid], unique: true,
              name: "idx_raw_wb_stats_sales_account_srid"

    remove_index :raw_wb_stats_sales, name: "index_raw_wb_stats_sales_on_account_id_and_sale_id"
    remove_column :raw_wb_stats_sales, :sale_id
  end
end
