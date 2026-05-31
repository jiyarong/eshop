json.success true
json.data do
  json.questions do
    json.array! @questions do |question|
      json.id question.id
      json.wb_question_id question.wb_question_id
      json.nm_id question.nm_id
      json.was_viewed question.was_viewed
      json.is_answered question.is_answered
      json.wb_created_at question.wb_created_at
    end
  end
  json.meta do
    json.current_page @questions.current_page
    json.total_pages @questions.total_pages
    json.total_count @questions.total_count
  end
end
json.message @message || 'ok'