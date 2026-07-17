class CreateEcSkuDimensions < ActiveRecord::Migration[8.1]
  class MigrationSkuCost < ActiveRecord::Base
    self.table_name = "ec_sku_costs"
  end

  class MigrationSkuDimension < ActiveRecord::Base
    self.table_name = "ec_sku_dimensions"
  end

  def up
    create_table :ec_sku_dimensions do |t|
      t.string :sku_code, null: false
      t.decimal :inner_length_cm, precision: 8, scale: 2
      t.decimal :inner_width_cm, precision: 8, scale: 2
      t.decimal :inner_height_cm, precision: 8, scale: 2
      t.decimal :outer_length_cm, precision: 8, scale: 2
      t.decimal :outer_width_cm, precision: 8, scale: 2
      t.decimal :outer_height_cm, precision: 8, scale: 2

      t.timestamps
    end

    add_index :ec_sku_dimensions, :sku_code, unique: true, name: "idx_ec_sku_dimensions_sku_code"
    add_foreign_key :ec_sku_dimensions, :ec_skus, column: :sku_code, primary_key: :sku_code, on_delete: :cascade

    now = Time.current
    MigrationSkuCost.reset_column_information
    MigrationSkuDimension.reset_column_information
    MigrationSkuCost
      .where.not(pkg_length_cm: nil)
      .or(MigrationSkuCost.where.not(pkg_width_cm: nil))
      .or(MigrationSkuCost.where.not(pkg_height_cm: nil))
      .find_each do |cost|
        MigrationSkuDimension.create!(
          sku_code: cost.sku_code,
          inner_length_cm: cost.pkg_length_cm,
          inner_width_cm: cost.pkg_width_cm,
          inner_height_cm: cost.pkg_height_cm,
          created_at: now,
          updated_at: now
        )
      end

    remove_column :ec_sku_costs, :pkg_length_cm, :decimal
    remove_column :ec_sku_costs, :pkg_width_cm, :decimal
    remove_column :ec_sku_costs, :pkg_height_cm, :decimal
  end

  def down
    add_column :ec_sku_costs, :pkg_length_cm, :decimal, precision: 8, scale: 2
    add_column :ec_sku_costs, :pkg_width_cm, :decimal, precision: 8, scale: 2
    add_column :ec_sku_costs, :pkg_height_cm, :decimal, precision: 8, scale: 2

    MigrationSkuCost.reset_column_information
    MigrationSkuDimension.reset_column_information
    MigrationSkuDimension.find_each do |dimension|
      MigrationSkuCost
        .where(sku_code: dimension.sku_code)
        .update_all(
          pkg_length_cm: dimension.inner_length_cm,
          pkg_width_cm: dimension.inner_width_cm,
          pkg_height_cm: dimension.inner_height_cm
        )
    end

    drop_table :ec_sku_dimensions
  end
end
