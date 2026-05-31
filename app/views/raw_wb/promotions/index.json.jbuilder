json.success true
json.data do
  json.promotions do
    json.array! @promotions do |promotion|
      json.id promotion.id
      json.wb_promotion_id promotion.wb_promotion_id
      json.name promotion.name
      json.period_start promotion.period_start
      json.period_end promotion.period_end
      json.discount promotion.discount
    end
  end
  json.meta do
    json.current_page @promotions.current_page
    json.total_pages @promotions.total_pages
    json.total_count @promotions.total_count
  end
end
json.message @message || 'ok'