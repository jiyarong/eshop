class CreateRawOzonCommunication < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_ozon_reviews do |t|
      t.references :account,      null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string  :review_id,       null: false
      t.bigint  :ozon_sku
      t.string  :offer_id
      t.string  :product_name
      t.string  :reviewer_name
      t.integer :rating
      t.string  :title
      t.text    :comment
      t.text    :response
      t.datetime :response_at
      t.string  :response_status
      t.string  :status
      t.jsonb   :media
      t.jsonb   :raw_json,        null: false
      t.datetime :created_at
      t.datetime :updated_at
      t.datetime :synced_at
      t.index [:account_id, :review_id], unique: true
      t.index [:account_id, :ozon_sku]
      t.index [:account_id, :status]
      t.index [:account_id, :rating]
    end

    create_table :raw_ozon_questions do |t|
      t.references :account,      null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string  :question_id,     null: false
      t.bigint  :ozon_sku
      t.string  :offer_id
      t.string  :product_name
      t.text    :text
      t.text    :answer
      t.datetime :answer_at
      t.string  :status
      t.jsonb   :raw_json,        null: false
      t.datetime :created_at
      t.datetime :synced_at
      t.index [:account_id, :question_id], unique: true
      t.index [:account_id, :ozon_sku]
      t.index [:account_id, :status]
    end

    create_table :raw_ozon_chats do |t|
      t.references :account,      null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string  :chat_id,         null: false
      t.string  :chat_type
      t.string  :order_number
      t.integer :unread_count,    default: 0
      t.string  :status
      t.jsonb   :last_message
      t.jsonb   :raw_json,        null: false
      t.datetime :synced_at
      t.index [:account_id, :chat_id], unique: true
      t.index [:account_id, :status]
    end

    create_table :raw_ozon_chat_messages do |t|
      t.references :account,      null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string  :message_id,      null: false
      t.string  :chat_id,         null: false
      t.string  :direction                    # 'in' | 'out'
      t.jsonb   :data
      t.jsonb   :raw_json,        null: false
      t.datetime :created_at
      t.datetime :synced_at
      t.index [:account_id, :message_id], unique: true
      t.index [:account_id, :chat_id]
    end
  end
end
