class CreateEcCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_categories do |t|
      t.string :source, null: false
      t.string :source_type, null: false
      t.string :source_id, null: false
      t.references :parent, foreign_key: { to_table: :ec_categories }
      t.string :origin_name, null: false
      t.string :origin_language, null: false
      t.string :name_cn
      t.string :name_en
      t.string :name_ru
      t.datetime :translated_at
      t.text :translation_error
      t.datetime :synced_at

      t.timestamps
    end

    add_index :ec_categories, [:source, :source_type, :source_id], unique: true
    add_index :ec_categories, :source
    add_index :ec_categories, :source_type
    add_index :ec_categories, :origin_language
  end
end
