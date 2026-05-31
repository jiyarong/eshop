class CreateRawOzonPromotionsReports < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_promotions do |t|
      t.references :account,       null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.bigint  :action_id,        null: false
      t.string  :title
      t.string  :action_type
      t.text    :description
      t.boolean :is_participating, default: false
      t.integer :participating_products_count, default: 0
      t.integer :products_count,   default: 0
      t.jsonb   :raw_json,         null: false
      t.datetime :date_start
      t.datetime :date_end
      t.datetime :freeze_date
      t.datetime :synced_at
      t.index [:account_id, :action_id], unique: true
    end

    create_table :raw_ozon_reports do |t|
      t.references :account,       null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string  :report_code,      null: false
      t.string  :report_type
      t.string  :status
      t.text    :error
      t.text    :file_url
      t.jsonb   :params
      t.jsonb   :raw_json,         null: false
      t.datetime :created_at
      t.datetime :synced_at
      t.index [:account_id, :report_code], unique: true
      t.index [:account_id, :report_type]
      t.index [:account_id, :status]
    end

    create_table :raw_ozon_sync_tasks do |t|
      t.references :account,       null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string  :sync_type,        null: false  # 'setup' | 'daily' | 'weekly'
      t.string  :status,           null: false, default: 'pending'
      t.jsonb   :results
      t.text    :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
      t.index [:account_id, :sync_type]
      t.index [:account_id, :status]
    end
  end
end
