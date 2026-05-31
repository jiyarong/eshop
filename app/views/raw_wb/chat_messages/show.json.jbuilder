json.success true
json.data do
  json.chat_message do
    json.id       @chat_message.id
    json.chat_id  @chat_message.chat_id
    json.sender   @chat_message.sender
    json.text     @chat_message.text
    json.file_id  @chat_message.file_id
    json.sent_at  @chat_message.sent_at
  end
end
json.message @message || 'ok'
