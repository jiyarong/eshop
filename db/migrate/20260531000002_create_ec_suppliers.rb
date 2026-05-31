class CreateEcSuppliers < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_suppliers do |t|
      t.string :name, null: false
      t.string :contact_name
      t.string :phone
      t.string :wechat
      t.text :address
      t.boolean :is_active, null: false, default: true
      t.text :memo
      t.timestamps
    end

    add_index :ec_suppliers, :name, unique: true
    add_index :ec_suppliers, :is_active
  end
end
