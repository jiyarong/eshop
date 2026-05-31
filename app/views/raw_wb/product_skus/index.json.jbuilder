json.success true
json.data do
  json.product_skus do
    json.array! @product_skus do |product_sku|
      json.id product_sku.id
      json.product_id product_sku.product_id
      json.chrt_id product_sku.chrt_id
      json.tech_size product_sku.tech_size
      json.wb_size product_sku.wb_size
      json.barcode product_sku.barcode
    end
  end
  json.meta do
    json.current_page @product_skus.current_page
    json.total_pages @product_skus.total_pages
    json.total_count @product_skus.total_count
  end
end
json.message @message || 'ok'