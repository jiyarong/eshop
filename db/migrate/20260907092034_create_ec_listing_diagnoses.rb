class CreateEcListingDiagnoses < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_listing_diagnoses do |t|
      t.references :sku_product, null: false, foreign_key: { to_table: :ec_sku_products }
      t.references :submitted_by, null: false, foreign_key: { to_table: :users }
      t.references :conversation, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.text :result
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :ec_listing_diagnoses, [ :sku_product_id, :created_at ],
      name: :idx_ec_listing_diagnoses_on_product_and_created_at
    add_index :ec_listing_diagnoses, :sku_product_id,
      unique: true,
      where: "status IN ('pending', 'running')",
      name: :idx_ec_listing_diagnoses_one_active_per_product
    add_check_constraint :ec_listing_diagnoses,
      "status IN ('pending', 'running', 'completed', 'failed')",
      name: :ec_listing_diagnoses_status_check
  end
end
