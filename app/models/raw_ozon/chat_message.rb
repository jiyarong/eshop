module RawOzon
  class ChatMessage < ApplicationRecord
    self.table_name = 'raw_ozon_chat_messages'
    belongs_to :chat, class_name: 'RawOzon::Chat'
  end
end
