json.success true
json.data do
  json.supply do
      json.id @supply.id
      json.wb_supply_id @supply.wb_supply_id
      json.name @supply.name
      json.supply_type @supply.supply_type
      json.is_done @supply.is_done
      json.supply_created_at @supply.supply_created_at
      json.closed_at @supply.closed_at
      json.scan_dt @supply.scan_dt
      json.synced_at @supply.synced_at
  end
end
json.message @message || 'ok'
