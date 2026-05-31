class CreateRawWbCommunication < ActiveRecord::Migration[8.0]
  def change
    create_table :raw_wb_reviews do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.string :wb_review_id, index: { unique: true }
      t.bigint :nm_id
      t.string :vendor_code
      t.string :size
      t.integer :rating
      t.text :text
      t.jsonb :photo_urls
      t.jsonb :video_urls
      t.boolean :was_viewed, default: false
      t.boolean :is_answered, default: false
      t.text :answer_text
      t.datetime :answer_at
      t.boolean :is_pinned, default: false
      t.boolean :is_archived, default: false
      t.datetime :wb_created_at, null: false
      t.datetime :synced_at
    end

    create_table :raw_wb_questions do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.string :wb_question_id, index: { unique: true }
      t.bigint :nm_id
      t.string :vendor_code
      t.text :text
      t.boolean :was_viewed, default: false
      t.boolean :is_answered, default: false
      t.text :answer_text
      t.datetime :answer_at
      t.datetime :wb_created_at, null: false
      t.datetime :synced_at
    end

    create_table :raw_wb_chats do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.string :wb_chat_id, index: { unique: true }
      t.string :buyer_id
      t.references :order, foreign_key: { to_table: :raw_wb_orders }
      t.datetime :last_message_at
      t.timestamps
    end

    create_table :raw_wb_chat_messages do |t|
      t.references :chat, null: false, foreign_key: { to_table: :raw_wb_chats }
      t.string :sender
      t.text :text
      t.string :file_id
      t.datetime :sent_at, null: false
    end

    create_table :raw_wb_return_claims do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_wb_seller_accounts }
      t.string :wb_claim_id, index: { unique: true }
      t.references :order, foreign_key: { to_table: :raw_wb_orders }
      t.bigint :nm_id
      t.string :status
      t.text :reason
      t.text :response_text
      t.datetime :wb_created_at, null: false
      t.datetime :responded_at
      t.datetime :synced_at
    end
  end
end
