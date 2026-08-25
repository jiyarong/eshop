class RebuildRawOzonChatsForV3 < ActiveRecord::Migration[8.1]
  def change
    drop_table :raw_ozon_chat_messages
    drop_table :raw_ozon_chats

    create_table :raw_ozon_chats do |t|
      t.references :account, null: false, foreign_key: { to_table: :raw_ozon_seller_accounts }
      t.string :chat_id, null: false
      t.string :chat_type, null: false
      t.string :status
      t.integer :unread_count, null: false, default: 0
      t.bigint :first_unread_message_id
      t.bigint :last_message_id
      t.datetime :opened_at
      t.datetime :last_message_at
      t.string :last_message_user_type
      t.text :last_message_preview
      t.datetime :history_synced_at
      t.boolean :history_complete, null: false, default: false
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false

      t.index %i[account_id chat_id], unique: true
      t.index %i[account_id chat_type last_message_at], name: "idx_raw_ozon_chats_type_last_message"
      t.index %i[account_id unread_count]
    end

    create_table :raw_ozon_chat_messages do |t|
      t.references :chat, null: false, foreign_key: { to_table: :raw_ozon_chats, on_delete: :cascade }
      t.bigint :message_id, null: false
      t.string :user_id
      t.string :user_type
      t.text :message_text
      t.jsonb :message_data, null: false, default: []
      t.boolean :is_read, null: false, default: false
      t.boolean :is_image, null: false, default: false
      t.jsonb :attachment_urls, null: false, default: []
      t.string :platform_sku_id
      t.string :order_number
      t.datetime :sent_at, null: false
      t.jsonb :raw_json, null: false, default: {}
      t.datetime :synced_at, null: false

      t.index %i[chat_id message_id], unique: true
      t.index %i[chat_id sent_at]
      t.index %i[platform_sku_id sent_at]
      t.index %i[user_type sent_at]
    end

    create_table :raw_ozon_chat_sku_links do |t|
      t.references :chat, null: false, foreign_key: { to_table: :raw_ozon_chats, on_delete: :cascade }
      t.string :platform_sku_id, null: false
      t.references :sku_product, foreign_key: { to_table: :ec_sku_products, on_delete: :nullify }
      t.bigint :first_message_id, null: false
      t.bigint :last_message_id, null: false
      t.datetime :linked_at, null: false

      t.index %i[chat_id platform_sku_id], unique: true, name: "idx_raw_ozon_chat_sku_links_unique"
      t.index %i[sku_product_id linked_at], name: "idx_raw_ozon_chat_sku_links_product"
    end
  end
end
