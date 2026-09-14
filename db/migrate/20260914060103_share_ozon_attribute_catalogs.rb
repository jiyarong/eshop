class ShareOzonAttributeCatalogs < ActiveRecord::Migration[8.1]
  def up
    # Attribute catalog rows are disposable caches. Rebuild them under the
    # shared-key model instead of carrying forward the old account-scoped data.
    execute "TRUNCATE TABLE raw_ozon_product_attributes, raw_ozon_attribute_values, raw_ozon_category_attributes"

    remove_foreign_key :raw_ozon_category_attributes, column: :account_id
    remove_foreign_key :raw_ozon_attribute_values, column: :account_id
    remove_index :raw_ozon_category_attributes, name: "idx_raw_ozon_cat_attrs_unique"
    remove_index :raw_ozon_category_attributes, name: "idx_raw_ozon_cat_attrs_category_type"
    remove_index :raw_ozon_category_attributes, name: "idx_raw_ozon_cat_attrs_dictionary"
    remove_index :raw_ozon_category_attributes, name: "idx_raw_ozon_category_attributes_on_account_id"
    remove_index :raw_ozon_attribute_values, name: "idx_raw_ozon_attr_values_unique"
    remove_index :raw_ozon_attribute_values, name: "idx_raw_ozon_attr_values_attribute"
    remove_index :raw_ozon_attribute_values, name: "idx_raw_ozon_attr_values_value"
    remove_index :raw_ozon_attribute_values, name: "idx_raw_ozon_attribute_values_on_account_id"

    remove_column :raw_ozon_category_attributes, :account_id, :bigint
    remove_column :raw_ozon_attribute_values, :account_id, :bigint

    add_index :raw_ozon_category_attributes,
      %i[description_category_id type_id attribute_id attribute_complex_id],
      unique: true,
      name: "idx_raw_ozon_cat_attrs_unique"
    add_index :raw_ozon_category_attributes,
      %i[description_category_id type_id],
      name: "idx_raw_ozon_cat_attrs_category_type"
    add_index :raw_ozon_attribute_values,
      %i[description_category_id type_id attribute_id dictionary_value_id],
      unique: true,
      name: "idx_raw_ozon_attr_values_unique"
    add_index :raw_ozon_attribute_values,
      %i[description_category_id type_id attribute_id],
      name: "idx_raw_ozon_attr_values_attribute"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Shared Ozon attribute catalogs cannot be restored"
  end
end
