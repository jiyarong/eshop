class GeneralizeEcListingDiagnosesToAISuggestions < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :ec_listing_diagnoses, column: :sku_product_id
    remove_index :ec_listing_diagnoses, name: :idx_ec_listing_diagnoses_on_product_and_created_at
    remove_index :ec_listing_diagnoses, name: :idx_ec_listing_diagnoses_one_active_per_product
    remove_index :ec_listing_diagnoses, name: :index_ec_listing_diagnoses_on_sku_product_id
    remove_check_constraint :ec_listing_diagnoses, name: :ec_listing_diagnoses_status_check

    rename_table :ec_listing_diagnoses, :ec_ai_suggestions
    rename_column :ec_ai_suggestions, :sku_product_id, :suggestable_id
    rename_column :ec_ai_suggestions, :result, :content
    add_column :ec_ai_suggestions, :suggestable_type, :string, null: false, default: "Ec::SkuProduct"
    add_column :ec_ai_suggestions, :suggestion_type, :string, null: false, default: "listing_audit"
    change_column_default :ec_ai_suggestions, :suggestable_type, from: "Ec::SkuProduct", to: nil
    change_column_default :ec_ai_suggestions, :suggestion_type, from: "listing_audit", to: nil

    add_index :ec_ai_suggestions, [ :suggestable_type, :suggestable_id ],
      name: :idx_ec_ai_suggestions_on_suggestable
    add_index :ec_ai_suggestions, [ :suggestable_type, :suggestable_id, :suggestion_type, :created_at ],
      name: :idx_ec_ai_suggestions_on_target_type_created_at
    add_index :ec_ai_suggestions, [ :suggestable_type, :suggestable_id, :suggestion_type ],
      unique: true,
      where: "status IN ('pending', 'running')",
      name: :idx_ec_ai_suggestions_one_active_per_target
    add_check_constraint :ec_ai_suggestions,
      "status IN ('pending', 'running', 'completed', 'failed')",
      name: :ec_ai_suggestions_status_check
  end

  def down
    unsupported = select_value(<<~SQL.squish)
      SELECT 1
      FROM ec_ai_suggestions
      WHERE suggestable_type <> 'Ec::SkuProduct'
         OR suggestion_type <> 'listing_audit'
      LIMIT 1
    SQL
    raise ActiveRecord::IrreversibleMigration, "AI suggestions contain non-listing data" if unsupported

    remove_check_constraint :ec_ai_suggestions, name: :ec_ai_suggestions_status_check
    remove_index :ec_ai_suggestions, name: :idx_ec_ai_suggestions_one_active_per_target
    remove_index :ec_ai_suggestions, name: :idx_ec_ai_suggestions_on_target_type_created_at
    remove_index :ec_ai_suggestions, name: :idx_ec_ai_suggestions_on_suggestable
    remove_column :ec_ai_suggestions, :suggestion_type
    remove_column :ec_ai_suggestions, :suggestable_type
    rename_column :ec_ai_suggestions, :content, :result
    rename_column :ec_ai_suggestions, :suggestable_id, :sku_product_id
    rename_table :ec_ai_suggestions, :ec_listing_diagnoses

    add_index :ec_listing_diagnoses, :sku_product_id,
      name: :index_ec_listing_diagnoses_on_sku_product_id
    add_index :ec_listing_diagnoses, [ :sku_product_id, :created_at ],
      name: :idx_ec_listing_diagnoses_on_product_and_created_at
    add_index :ec_listing_diagnoses, :sku_product_id,
      unique: true,
      where: "status IN ('pending', 'running')",
      name: :idx_ec_listing_diagnoses_one_active_per_product
    add_check_constraint :ec_listing_diagnoses,
      "status IN ('pending', 'running', 'completed', 'failed')",
      name: :ec_listing_diagnoses_status_check
    add_foreign_key :ec_listing_diagnoses, :ec_sku_products, column: :sku_product_id
  end
end
