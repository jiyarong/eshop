json.success true
json.data do
  json.review do
      json.id @review.id
      json.wb_review_id @review.wb_review_id
      json.nm_id @review.nm_id
      json.vendor_code @review.vendor_code
      json.size @review.size
      json.rating @review.rating
      json.text @review.text
      json.photo_urls @review.photo_urls
      json.video_urls @review.video_urls
      json.was_viewed @review.was_viewed
      json.is_answered @review.is_answered
      json.answer_text @review.answer_text
      json.answer_at @review.answer_at
      json.is_pinned @review.is_pinned
      json.is_archived @review.is_archived
      json.wb_created_at @review.wb_created_at
      json.synced_at @review.synced_at
  end
end
json.message @message || 'ok'
