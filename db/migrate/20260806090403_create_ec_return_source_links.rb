class CreateEcReturnSourceLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_return_source_links do |t|
      t.references :return, null: false, foreign_key: { to_table: :ec_returns }
      t.references :item, foreign_key: { to_table: :ec_return_items }
      t.string :platform, null: false
      t.string :source_type, null: false
      t.bigint :source_id, null: false
      t.string :source_key
      t.datetime :synced_at
      t.timestamps
    end

    add_index :ec_return_source_links, %i[source_type source_id], unique: true
  end
end
