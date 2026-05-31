json.success true
json.data do
  json.categories do
    json.array! @categories do |category|
      json.id category.id
      json.wb_id category.wb_id
      json.name category.name
      json.name_en category.name_en
      json.synced_at category.synced_at
    end
  end
  json.meta do
    json.current_page @categories.current_page
    json.total_pages  @categories.total_pages
    json.total_count  @categories.total_count
  end
end
json.message @message || 'ok'