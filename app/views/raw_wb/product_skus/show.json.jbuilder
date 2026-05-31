json.success true
json.data do
  json.product_sku do
      json.id @product_sku.id
      json.product_id @product_sku.product_id
      json.chrt_id @product_sku.chrt_id
      json.tech_size @product_sku.tech_size
      json.wb_size @product_sku.wb_size
      json.barcode @product_sku.barcode
      json.created_at @product_sku.created_at
  end
end
json.message @message || 'ok'
