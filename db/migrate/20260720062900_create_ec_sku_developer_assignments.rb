class CreateEcSkuDeveloperAssignments < ActiveRecord::Migration[8.1]
  def up
    create_table :ec_sku_developer_assignments do |t|
      t.string :sku_code, null: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :ec_sku_developer_assignments,
      [:sku_code, :user_id],
      unique: true,
      name: "idx_ec_sku_developer_assignments_unique"
    add_index :ec_sku_developer_assignments, :sku_code
    add_foreign_key :ec_sku_developer_assignments,
      :ec_skus,
      column: :sku_code,
      primary_key: :sku_code

    execute <<~SQL.squish
      INSERT INTO ec_sku_developer_assignments (sku_code, user_id, created_at, updated_at)
      SELECT DISTINCT ec_sku_products.sku_code,
        ec_sku_product_operators.user_id,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM ec_sku_product_operators
      INNER JOIN ec_sku_products
        ON ec_sku_products.id = ec_sku_product_operators.sku_product_id
      WHERE ec_sku_product_operators.role = 'developer'
      ON CONFLICT (sku_code, user_id) DO NOTHING
    SQL

    execute <<~SQL.squish
      DELETE FROM ec_sku_product_operators
      WHERE role = 'developer'
    SQL
  end

  def down
    drop_table :ec_sku_developer_assignments
  end
end
