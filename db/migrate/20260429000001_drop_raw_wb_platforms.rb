class DropRawWbPlatforms < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :raw_wb_seller_accounts, :raw_wb_platforms
    remove_column :raw_wb_seller_accounts, :platform_id
    drop_table :raw_wb_platforms
  end

  def down
    create_table :raw_wb_platforms do |t|
      t.string :code, null: false, index: { unique: true }
      t.string :name, null: false
      t.string :base_api_url
      t.timestamps
    end

    add_reference :raw_wb_seller_accounts, :platform,
                  null: false,
                  default: 0,
                  foreign_key: { to_table: :raw_wb_platforms }
  end
end
