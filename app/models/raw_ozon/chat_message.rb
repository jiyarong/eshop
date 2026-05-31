module RawOzon
  class ChatMessage < ApplicationRecord
    self.table_name = 'raw_ozon_chat_messages'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
  end
end
