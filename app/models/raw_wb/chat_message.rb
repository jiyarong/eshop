module RawWb
  class ChatMessage < ApplicationRecord
    self.table_name = 'raw_wb_chat_messages'

    belongs_to :chat, class_name: 'RawWb::Chat'
  end
end
