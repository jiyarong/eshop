json.success true
json.data do
  json.orders do
    json.array! @orders do |order|
      json.id order.id
      json.wb_order_id order.wb_order_id
      json.delivery_type order.delivery_type
      json.supplier_status order.supplier_status
      json.wb_status order.wb_status
      json.nm_id order.nm_id
      json.article order.article
      json.price order.price
      json.created_at order.created_at
    end
  end
  json.meta do
    json.current_page @orders.current_page
    json.total_pages @orders.total_pages
    json.total_count @orders.total_count
  end
end
json.message @message || 'ok'