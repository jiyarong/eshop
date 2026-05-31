json.success true
json.data do
  json.chats do
    json.array! @chats do |chat|
      json.id chat.id
      json.wb_chat_id chat.wb_chat_id
      json.buyer_id chat.buyer_id
      json.order_id chat.order_id
      json.last_message_at chat.last_message_at
    end
  end
  json.meta do
    json.current_page @chats.current_page
    json.total_pages @chats.total_pages
    json.total_count @chats.total_count
  end
end
json.message @message || 'ok'