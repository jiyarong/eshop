json.success true
json.data do
  json.supplies do
    json.array! @supplies do |supply|
      json.id supply.id
      json.wb_supply_id supply.wb_supply_id
      json.name supply.name
      json.is_done supply.is_done
      json.supply_created_at supply.supply_created_at
    end
  end
  json.meta do
    json.current_page @supplies.current_page
    json.total_pages  @supplies.total_pages
    json.total_count  @supplies.total_count
  end
end
json.message @message || 'ok'