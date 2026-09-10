class CreateEcCompetitorData < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_competitor_data_batches do |t|
      t.references :sku, null: false, foreign_key: { to_table: :ec_skus }, index: false
      t.timestamps
    end

    add_index :ec_competitor_data_batches, [ :sku_id, :created_at ],
      name: :idx_ec_competitor_batches_on_sku_and_created_at

    create_table :ec_competitor_data do |t|
      t.references :competitor_data_batch,
        null: false,
        foreign_key: { to_table: :ec_competitor_data_batches },
        index: { name: :idx_ec_competitor_data_on_batch }
      t.text :markdown, null: false
      t.timestamps
    end
  end
end
