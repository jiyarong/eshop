class CreateRawOzonCategoryAttributeCatalogs < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_ozon_category_attributes do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint :description_category_id, null: false
      t.bigint :type_id, null: false, default: 0
      t.bigint :attribute_id, null: false
      t.bigint :attribute_complex_id, null: false, default: 0
      t.string :name
      t.text :description
      t.string :value_type
      t.bigint :group_id
      t.string :group_name
      t.bigint :dictionary_id, null: false, default: 0
      t.boolean :is_required, null: false, default: false
      t.boolean :is_collection, null: false, default: false
      t.boolean :is_aspect, null: false, default: false
      t.boolean :category_dependent, null: false, default: false
      t.integer :max_value_count
      t.boolean :complex_is_collection, null: false, default: false
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at

      t.index [:account_id, :description_category_id, :type_id, :attribute_id, :attribute_complex_id],
        unique: true,
        name: "idx_raw_ozon_cat_attrs_unique"
      t.index [:account_id, :description_category_id, :type_id],
        name: "idx_raw_ozon_cat_attrs_category_type"
      t.index [:account_id, :dictionary_id],
        name: "idx_raw_ozon_cat_attrs_dictionary"
    end

    create_table :raw_ozon_attribute_values do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint :description_category_id, null: false
      t.bigint :type_id, null: false, default: 0
      t.bigint :attribute_id, null: false
      t.bigint :dictionary_value_id, null: false
      t.string :value
      t.string :info
      t.string :picture
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at

      t.index [:account_id, :description_category_id, :type_id, :attribute_id, :dictionary_value_id],
        unique: true,
        name: "idx_raw_ozon_attr_values_unique"
      t.index [:account_id, :attribute_id],
        name: "idx_raw_ozon_attr_values_attribute"
      t.index [:account_id, :value],
        name: "idx_raw_ozon_attr_values_value"
    end
  end
end
