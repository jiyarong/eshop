json.success true
json.data do
  json.stock do
      json.id @stock.id
      json.account_id @stock.account_id
      json.warehouse_id @stock.warehouse_id
      json.sku_id @stock.sku_id
      json.barcode @stock.barcode
      json.quantity @stock.quantity
      json.updated_at @stock.updated_at
  end
end
json.message @message || 'ok'
