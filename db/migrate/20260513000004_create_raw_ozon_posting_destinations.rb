class CreateRawOzonPostingDestinations < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_posting_destinations do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }

      t.string  :posting_number,       null: false
      t.string  :delivery_schema                    # FBO / FBS / RFBS
      t.string  :city                               # analytics_data.city
      t.string  :region
      t.string  :warehouse_name                     # result.warehouse_name
      t.string  :delivery_method_name               # FBS only: delivery_method.name (白俄兜底用)
      t.boolean :is_belarus,           null: false, default: false

      t.datetime :synced_at, null: false
    end

    add_index :raw_ozon_posting_destinations,
              [:account_id, :posting_number],
              unique: true,
              name: 'idx_ozon_posting_dest_unique'

    add_index :raw_ozon_posting_destinations,
              [:account_id, :is_belarus],
              name: 'idx_ozon_posting_dest_belarus'
  end
end
