module RawWb
  class Chat < ApplicationRecord
    self.table_name = 'raw_wb_chats'

    belongs_to :account, class_name: 'RawWb::SellerAccount'
    belongs_to :order,   class_name: 'RawWb::Order', optional: true

    has_many :chat_messages, class_name: 'RawWb::ChatMessage', foreign_key: :chat_id, dependent: :destroy
  end
end
