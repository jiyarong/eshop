json.success true
json.data do
  json.categories do
    json.array! @categories do |category|
      json.id category.id
      json.wb_id category.wb_id
      json.name category.name
      json.name_en category.name_en
      json.name_zh category.name_zh
      json.synced_at category.synced_at
      json.subjects do
        json.array! category.subjects.sort_by(&:name) do |subject|
          json.id subject.id
          json.wb_id subject.wb_id
          json.name subject.name
          json.name_en subject.name_en
          json.synced_at subject.synced_at
        end
      end
    end
  end
end
json.message @message || 'ok'
