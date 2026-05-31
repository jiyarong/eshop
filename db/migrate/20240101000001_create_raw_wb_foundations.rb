class CreateRawWbFoundations < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_platforms do |t|
      t.string :code, null: false, index: { unique: true }
      t.string :name, null: false
      t.string :base_api_url
      t.timestamps
    end

    create_table :raw_wb_seller_accounts do |t|
      t.references :platform, null: false, foreign_key: { to_table: :raw_wb_platforms }
      t.string :name, null: false
      t.text :api_token
      t.string :token_type
      t.datetime :token_expires_at
      t.boolean :is_active, default: true
      t.timestamps
    end
  end
end
