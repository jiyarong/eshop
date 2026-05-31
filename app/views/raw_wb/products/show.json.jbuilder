json.success true
json.data do
  json.product do
      json.id @product.id
      json.nm_id @product.nm_id
      json.imt_id @product.imt_id
      json.vendor_code @product.vendor_code
      json.brand @product.brand
      json.title @product.title
      json.description @product.description
      json.subject_id @product.subject_id
      json.subject_name @product.subject_name
      json.wb_category @product.wb_category
      json.is_in_trash @product.is_in_trash
      json.created_at @product.created_at
      json.updated_at @product.updated_at
      json.synced_at @product.synced_at
  end
end
json.message @message || 'ok'
