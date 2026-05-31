json.success true
json.data do
  json.question do
      json.id @question.id
      json.wb_question_id @question.wb_question_id
      json.nm_id @question.nm_id
      json.vendor_code @question.vendor_code
      json.text @question.text
      json.was_viewed @question.was_viewed
      json.is_answered @question.is_answered
      json.answer_text @question.answer_text
      json.answer_at @question.answer_at
      json.wb_created_at @question.wb_created_at
      json.synced_at @question.synced_at
  end
end
json.message @message || 'ok'
