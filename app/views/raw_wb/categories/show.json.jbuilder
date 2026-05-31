json.success true
json.data do
  json.category do
      json.id @category.id
      json.wb_id @category.wb_id
      json.name @category.name
      json.name_en @category.name_en
      json.name_zh @category.name_zh
      json.synced_at @category.synced_at
  end
end
json.message @message || 'ok'
