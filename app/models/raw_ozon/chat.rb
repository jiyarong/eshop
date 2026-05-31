module RawOzon
  class Chat < ApplicationRecord
    self.table_name = 'raw_ozon_chats'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
    has_many :messages, class_name: 'RawOzon::ChatMessage',
             foreign_key: :chat_id, primary_key: :chat_id
  end
end
