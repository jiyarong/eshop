class CreateRawWbCatalogs < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_categories do |t|
      t.integer :wb_id, null: false, index: { unique: true }
      t.string :name, null: false
      t.string :name_en
      t.string :name_zh
      t.datetime :synced_at
    end

    create_table :raw_wb_subjects do |t|
      t.integer :wb_id, null: false, index: { unique: true }
      t.references :category, foreign_key: { to_table: :raw_wb_categories }
      t.string :name, null: false
      t.string :name_en
      t.datetime :synced_at
    end

    create_table :raw_wb_characteristics do |t|
      t.integer :wb_id, null: false, index: { unique: true }
      t.references :subject, null: false, foreign_key: { to_table: :raw_wb_subjects }
      t.string :name, null: false
      t.string :data_type
      t.string :unit_name
      t.integer :max_count, default: 1
      t.boolean :is_required, default: false
      t.boolean :is_popular, default: false
      t.datetime :synced_at
    end

    create_table :raw_wb_attribute_dicts do |t|
      t.string :dict_type, null: false
      t.string :wb_id
      t.string :name, null: false
      t.string :name_en
      t.index [:dict_type, :wb_id]
    end
  end
end
