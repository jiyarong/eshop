json.success true
json.data do
  json.reviews do
    json.array! @reviews do |review|
      json.id review.id
      json.wb_review_id review.wb_review_id
      json.nm_id review.nm_id
      json.rating review.rating
      json.was_viewed review.was_viewed
      json.is_answered review.is_answered
      json.is_pinned review.is_pinned
      json.wb_created_at review.wb_created_at
    end
  end
  json.meta do
    json.current_page @reviews.current_page
    json.total_pages @reviews.total_pages
    json.total_count @reviews.total_count
  end
end
json.message @message || 'ok'