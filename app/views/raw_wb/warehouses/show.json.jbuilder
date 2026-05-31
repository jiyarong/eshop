json.success true
json.data do
  json.warehouse do
      json.id @warehouse.id
      json.wb_warehouse_id @warehouse.wb_warehouse_id
      json.name @warehouse.name
      json.address @warehouse.address
      json.work_time @warehouse.work_time
      json.city @warehouse.city
      json.longitude @warehouse.longitude
      json.latitude @warehouse.latitude
      json.warehouse_type @warehouse.warehouse_type
      json.is_active @warehouse.is_active
      json.created_at @warehouse.created_at
      json.updated_at @warehouse.updated_at
  end
end
json.message @message || 'ok'
