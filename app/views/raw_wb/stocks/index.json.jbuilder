json.success true
json.data do
  json.stocks do
    json.array! @stocks do |stock|
      json.id stock.id
      json.warehouse_id stock.warehouse_id
      json.barcode stock.barcode
      json.quantity stock.quantity
      json.updated_at stock.updated_at
    end
  end
  json.meta do
    json.current_page @stocks.current_page
    json.total_pages @stocks.total_pages
    json.total_count @stocks.total_count
  end
end
json.message @message || 'ok'