json.success true
json.data do
  json.chat_messages do
    json.array! @chat_messages do |msg|
      json.id       msg.id
      json.chat_id  msg.chat_id
      json.sender   msg.sender
      json.text     msg.text
      json.file_id  msg.file_id
      json.sent_at  msg.sent_at
    end
  end
  json.meta do
    json.current_page @chat_messages.current_page
    json.total_pages  @chat_messages.total_pages
    json.total_count  @chat_messages.total_count
  end
end
json.message @message || 'ok'