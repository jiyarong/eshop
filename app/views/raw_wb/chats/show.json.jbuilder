json.success true
json.data do
  json.chat do
      json.id @chat.id
      json.wb_chat_id @chat.wb_chat_id
      json.buyer_id @chat.buyer_id
      json.order_id @chat.order_id
      json.last_message_at @chat.last_message_at
      json.created_at @chat.created_at
      json.updated_at @chat.updated_at
  end
end
json.message @message || 'ok'
