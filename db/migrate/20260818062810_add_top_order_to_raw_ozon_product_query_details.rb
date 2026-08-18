class AddTopOrderToRawOzonProductQueryDetails < ActiveRecord::Migration[8.1]
  def up
    add_column :raw_ozon_product_query_details, :top_order_by, :string, null: false, default: "BY_SEARCHES"
    add_column :raw_ozon_product_query_details, :top_order_rank, :integer

    execute <<~SQL.squish
      UPDATE raw_ozon_product_query_details
      SET top_order_rank = query_index
    SQL

    remove_index :raw_ozon_product_query_details, name: :idx_ozon_product_query_details_unique
    add_index :raw_ozon_product_query_details,
      %i[account_id period_from sku query top_order_by],
      unique: true,
      name: :idx_ozon_product_query_details_unique
    add_index :raw_ozon_product_query_details,
      %i[account_id period_from period_to sku top_order_by top_order_rank],
      name: :idx_ozon_product_query_details_dimension_rank
  end

  def down
    remove_index :raw_ozon_product_query_details, name: :idx_ozon_product_query_details_dimension_rank
    remove_index :raw_ozon_product_query_details, name: :idx_ozon_product_query_details_unique
    remove_column :raw_ozon_product_query_details, :top_order_rank
    remove_column :raw_ozon_product_query_details, :top_order_by
    add_index :raw_ozon_product_query_details,
      %i[account_id period_from sku query],
      unique: true,
      name: :idx_ozon_product_query_details_unique
  end
end
