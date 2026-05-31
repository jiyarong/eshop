class AddUniqueIndexesForWbSync < ActiveRecord::Migration[8.0]
  def change
    # stats orders/sales dedup by account + srid (NULL srids won't conflict in PG)
    add_index :raw_wb_stats_orders, [:account_id, :srid], unique: true,
              where: 'srid IS NOT NULL', name: 'idx_raw_wb_stats_orders_account_srid'

    add_index :raw_wb_stats_sales, [:account_id, :srid], unique: true,
              where: 'srid IS NOT NULL', name: 'idx_raw_wb_stats_sales_account_srid'

    # stocks dedup by account + warehouse + barcode
    add_index :raw_wb_stocks, [:account_id, :warehouse_id, :barcode], unique: true,
              name: 'idx_raw_wb_stocks_unique'
  end
end
