json.success true
json.data do
  json.subjects do
    json.array! @subjects do |subject|
      json.id subject.id
      json.wb_id subject.wb_id
      json.name subject.name
      json.category_id subject.category_id
      json.synced_at subject.synced_at
    end
  end
  json.meta do
    json.current_page @subjects.current_page
    json.total_pages @subjects.total_pages
    json.total_count @subjects.total_count
  end
end
json.message @message || 'ok'