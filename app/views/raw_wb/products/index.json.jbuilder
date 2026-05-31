json.success true
json.data do
  json.products do
    json.array! @products do |product|
      json.id product.id
      json.nm_id product.nm_id
      json.vendor_code product.vendor_code
      json.brand product.brand
      json.title product.title
      json.subject_name product.subject_name
      json.is_in_trash product.is_in_trash
      json.synced_at product.synced_at
    end
  end
  json.meta do
    json.current_page @products.current_page
    json.total_pages @products.total_pages
    json.total_count @products.total_count
  end
end
json.message @message || 'ok'