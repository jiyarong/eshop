json.success true
json.data do
  json.promotion do
      json.id @promotion.id
      json.wb_promotion_id @promotion.wb_promotion_id
      json.name @promotion.name
      json.period_start @promotion.period_start
      json.period_end @promotion.period_end
      json.discount @promotion.discount
      json.synced_at @promotion.synced_at
  end
end
json.message @message || 'ok'
