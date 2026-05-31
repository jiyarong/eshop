json.success true
json.data do
  json.order do
      json.id @order.id
      json.wb_order_id @order.wb_order_id
      json.order_uid @order.order_uid
      json.srid @order.srid
      json.delivery_type @order.delivery_type
      json.nm_id @order.nm_id
      json.chrt_id @order.chrt_id
      json.article @order.article
      json.barcode @order.barcode
      json.supplier_status @order.supplier_status
      json.wb_status @order.wb_status
      json.price @order.price
      json.converted_price @order.converted_price
      json.currency_code @order.currency_code
      json.warehouse_id @order.warehouse_id
      json.wb_office @order.wb_office
      json.required_meta @order.required_meta
      json.optional_meta @order.optional_meta
      json.is_zero_order @order.is_zero_order
      json.created_at @order.created_at
      json.updated_at @order.updated_at
      json.synced_at @order.synced_at
  end
end
json.message @message || 'ok'
