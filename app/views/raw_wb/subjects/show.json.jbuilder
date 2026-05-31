json.success true
json.data do
  json.subject do
      json.id @subject.id
      json.wb_id @subject.wb_id
      json.name @subject.name
      json.name_en @subject.name_en
      json.category_id @subject.category_id
      json.synced_at @subject.synced_at
  end
end
json.message @message || 'ok'
