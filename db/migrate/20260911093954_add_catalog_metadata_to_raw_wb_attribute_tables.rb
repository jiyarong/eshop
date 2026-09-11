class AddCatalogMetadataToRawWbAttributeTables < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_wb_characteristics, :charc_type, :integer
    add_column :raw_wb_characteristics, :has_filter, :boolean, null: false, default: false
    add_column :raw_wb_characteristics, :dictionary_type, :string
    add_column :raw_wb_characteristics, :raw_json, :jsonb, null: false, default: {}

    remove_index :raw_wb_characteristics, :wb_id, if_exists: true
    add_index :raw_wb_characteristics, [:subject_id, :wb_id],
      unique: true,
      name: "idx_raw_wb_characteristics_subject_charc"
    add_index :raw_wb_characteristics, :dictionary_type

    add_reference :raw_wb_attribute_dicts, :subject, foreign_key: { to_table: :raw_wb_subjects }
    add_column :raw_wb_attribute_dicts, :scope_key, :string, null: false, default: ""
    add_column :raw_wb_attribute_dicts, :value_key, :string, null: false, default: ""
    add_column :raw_wb_attribute_dicts, :parent_name, :string
    add_column :raw_wb_attribute_dicts, :name_zh, :string
    add_column :raw_wb_attribute_dicts, :raw_json, :jsonb, null: false, default: {}
    add_column :raw_wb_attribute_dicts, :synced_at, :datetime

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE raw_wb_attribute_dicts
          SET value_key = COALESCE(NULLIF(wb_id, ''), LOWER(name))
          WHERE value_key = ''
        SQL
        execute <<~SQL.squish
          DELETE FROM raw_wb_attribute_dicts duplicate_rows
          USING raw_wb_attribute_dicts kept_rows
          WHERE duplicate_rows.id > kept_rows.id
            AND duplicate_rows.dict_type = kept_rows.dict_type
            AND duplicate_rows.scope_key = kept_rows.scope_key
            AND duplicate_rows.value_key = kept_rows.value_key
        SQL
      end
    end

    add_index :raw_wb_attribute_dicts, [:dict_type, :scope_key, :value_key],
      unique: true,
      name: "idx_raw_wb_attribute_dicts_unique"
    add_index :raw_wb_attribute_dicts, [:dict_type, :name]
  end
end
