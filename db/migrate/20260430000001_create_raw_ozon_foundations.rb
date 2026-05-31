class CreateRawOzonFoundations < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_seller_accounts do |t|
      t.string  :client_id,      null: false, index: { unique: true }
      t.text    :api_key,        null: false
      t.string  :company_name
      t.string  :legal_name
      t.string  :inn
      t.string  :ownership_form
      t.boolean :is_active,      null: false, default: true
      t.text    :memo
      t.jsonb   :raw_json
      t.timestamps
    end
  end
end
