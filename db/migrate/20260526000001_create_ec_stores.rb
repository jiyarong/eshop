class CreateEcStores < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_stores do |t|
      # 基础
      t.string  :platform,      null: false               # 'wb' / 'ozon'
      t.string  :store_name,    null: false               # 展示名，如 TaxiLink / Nevastal
      t.string  :company_type                             # 'general' / 'small'
      t.boolean :is_active,     null: false, default: true
      t.text    :memo

      # WB 字段
      t.text    :wb_api_token
      t.integer :wb_raw_account_id                        # → raw_wb_seller_accounts.id

      # Ozon 字段
      t.string  :ozon_client_id
      t.text    :ozon_api_key
      t.string  :ozon_performance_client_id
      t.text    :ozon_performance_client_secret
      t.integer :ozon_raw_account_id                      # → raw_ozon_seller_accounts.id

      t.timestamps
    end

    add_index :ec_stores, :platform
    add_index :ec_stores, :ozon_client_id, unique: true, where: "ozon_client_id IS NOT NULL"
  end
end
