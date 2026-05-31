json.success true
json.data do
  json.warehouses do
    json.array! @warehouses do |warehouse|
      json.id warehouse.id
      json.wb_warehouse_id warehouse.wb_warehouse_id
      json.name warehouse.name
      json.city warehouse.city
      json.warehouse_type warehouse.warehouse_type
      json.is_active warehouse.is_active
    end
  end
  json.meta do
    json.current_page @warehouses.current_page
    json.total_pages @warehouses.total_pages
    json.total_count @warehouses.total_count
  end
end
json.message @message || 'ok'