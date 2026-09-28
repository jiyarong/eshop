class CreateEcSkuOperatorAssignments < ActiveRecord::Migration[8.1]
  def up
    create_table :ec_sku_operator_assignments do |t|
      t.string :sku_code, null: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :ec_sku_operator_assignments, :sku_code, unique: true
    add_foreign_key :ec_sku_operator_assignments, :ec_skus, column: :sku_code, primary_key: :sku_code

    execute <<~SQL.squish
      INSERT INTO ec_sku_operator_assignments (sku_code, user_id, created_at, updated_at)
      SELECT ec_sku_products.sku_code, MIN(ec_sku_product_operators.user_id), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM ec_sku_product_operators
      INNER JOIN ec_sku_products ON ec_sku_products.id = ec_sku_product_operators.sku_product_id
      WHERE ec_sku_product_operators.role = 'operator'
      GROUP BY ec_sku_products.sku_code
      HAVING COUNT(DISTINCT ec_sku_product_operators.user_id) = 1
      ON CONFLICT (sku_code) DO NOTHING
    SQL
  end

  def down
    drop_table :ec_sku_operator_assignments
  end
end
